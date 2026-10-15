"""Model families.

  baseline      plain logistic regression (the bar everything must beat)
  gbm           LightGBM + isotonic calibration (best offline predictor; also the
                reward model for doubly-robust off-policy evaluation)
  hierarchical  Bayesian mixed-effects logistic regression (bambi/PyMC); its
                population posterior becomes the on-device bandit prior
"""
from __future__ import annotations

import os
import warnings

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.isotonic import IsotonicRegression
from sklearn.linear_model import LogisticRegression

import config as C
from dataset import FeatureSpec


# ------------------------------------------------------------- baseline
class Baseline:
    def __init__(self, with_send: bool = False):
        self.with_send = with_send

    def _X(self, df):
        X = self.spec.transform(df)
        if self.with_send:
            for c in list(X.columns):
                X[f"{c}:send"] = X[c] * df["send"].values
            X["send"] = df["send"].values
        return X

    def fit(self, df: pd.DataFrame):
        self.spec = FeatureSpec().fit(df)
        self.m = LogisticRegression(C=1.0, max_iter=2000).fit(self._X(df), df["y"])
        return self

    def predict(self, df: pd.DataFrame) -> np.ndarray:
        return self.m.predict_proba(self._X(df))[:, 1]


# ------------------------------------------------------------------ gbm
class GBM:
    """with_send=True adds the action as a feature, for SlotDecision data / OPE."""

    def __init__(self, with_send: bool = False, **params):
        self.with_send = with_send
        self.params = dict(n_estimators=2000, learning_rate=0.03, num_leaves=15,
                           min_child_samples=30, subsample=0.8, subsample_freq=1,
                           colsample_bytree=0.8, reg_lambda=1.0, verbose=-1) | params

    @property
    def features(self):
        return C.LINEAR_FEATURES + C.GBM_EXTRA_FEATURES + (["send"] if self.with_send else [])

    def _X(self, df):
        X = df[self.features].copy()
        for c in C.GBM_CATEGORICAL:
            X[c] = pd.Categorical(X[c].astype(str), categories=self.cats_[c])
        return X

    def fit(self, df: pd.DataFrame, valid_frac: float = 0.2):
        df = df.sort_values("decision_time")
        cut = int(len(df) * (1 - valid_frac))
        tr, va = df.iloc[:cut], df.iloc[cut:]
        self.cats_ = {c: sorted(df[c].astype(str).unique()) for c in C.GBM_CATEGORICAL}
        mono = [1 if f == "deficit_frac" else 0 for f in self.features]   # more deficit never hurts
        self.m = lgb.LGBMClassifier(monotone_constraints=mono, **self.params)
        with warnings.catch_warnings():   # eval_set is deprecated in lightgbm>=4.6, kept for older versions
            warnings.simplefilter("ignore")
            self.m.fit(self._X(tr), tr["y"], eval_set=[(self._X(va), va["y"])],
                       callbacks=[lgb.early_stopping(100, verbose=False)])
        # isotonic calibration on the (later-in-time) validation slice
        self.iso = IsotonicRegression(out_of_bounds="clip", y_min=1e-4, y_max=1 - 1e-4)
        self.iso.fit(self.m.predict_proba(self._X(va))[:, 1], va["y"])
        return self

    def predict(self, df: pd.DataFrame, calibrated: bool = True) -> np.ndarray:
        p = self.m.predict_proba(self._X(df))[:, 1]
        return self.iso.predict(p) if calibrated else p


# --------------------------------------------------------- hierarchical
class Hierarchical:
    """Bernoulli mixed-effects logistic regression (bambi/PyMC).

    events mode (send only):
        y ~ 1 + features + (1 + RANDOM_SLOPES | userID)
    decisions mode (send + skip), split parameterization:
        y ~ 0 + skip + send + f_k... + f_s... + (0 + DECISION_RANDOM_TERMS | userID)
        with f_k = f * skip and f_s = f * send. The device's layout is recovered as
        base = skip block, send effect = send block - skip block (see build_prior).
    """

    def __init__(self, with_send: bool = False, draws: int = 1000, tune: int = 1000, chains: int = 2,
                 sampler: str = "pymc"):
        self.with_send = with_send
        self.draws, self.tune, self.chains = draws, tune, chains
        self.sampler = sampler   # "pymc" (default) or "nutpie"

    def formula(self) -> str:
        fx = C.LINEAR_FEATURES
        if self.with_send:
            fixed = " + ".join(["0", "skip", "send"] + [f"{f}_k" for f in fx] + [f"{f}_s" for f in fx])
            re = " + ".join(["0"] + C.DECISION_RANDOM_TERMS)
        else:
            fixed = " + ".join(fx)
            re = " + ".join(["1"] + C.RANDOM_SLOPES)
        return f"y ~ {fixed} + ({re} | userID)"

    def _priors(self):
        import bambi as bmb
        # Weakly informative: features are standardized, so |coef| >> 2 is implausible;
        # between-user SDs are expected well below 1 on the logit scale.
        p = {"common": bmb.Prior("Normal", mu=0.0, sigma=1.0),
             "group_specific": bmb.Prior("Normal", mu=0.0, sigma=bmb.Prior("HalfNormal", sigma=0.5))}
        if self.with_send:
            p["skip"] = bmb.Prior("Normal", mu=-3.0, sigma=1.5)   # un-prompted 10-min rate ~5%
            p["send"] = bmb.Prior("Normal", mu=-1.5, sigma=1.5)
        else:
            p["Intercept"] = bmb.Prior("Normal", mu=-2.0, sigma=1.5)
        return p

    def _data(self, df):
        d = self.spec.transform(df)
        if self.with_send:
            send = df["send"].astype(int).values
            for f in C.LINEAR_FEATURES:
                d[f"{f}_k"] = d[f] * (1 - send)
                d[f"{f}_s"] = d[f] * send
            d = d.drop(columns=C.LINEAR_FEATURES)
            d["skip"], d["send"] = 1 - send, send
        d["y"] = df["y"].astype(int).values
        d["userID"] = df["userID"].astype(str).values
        return d

    def fit(self, df: pd.DataFrame, seed: int = 0):
        import bambi as bmb
        self.spec = FeatureSpec().fit(df)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            self.model = bmb.Model(self.formula(), self._data(df), family="bernoulli", priors=self._priors())
            self.idata = self.model.fit(draws=self.draws, tune=self.tune, chains=self.chains,
                                        inference_method=self.sampler, target_accept=0.9,
                                        random_seed=seed, progressbar=False,
                                        cores=min(self.chains, os.cpu_count() or 1))
        self.check()
        return self

    def check(self) -> dict:
        """Convergence diagnostics; prints a warning when the fit should not be shipped."""
        import arviz as az
        st = self.idata.sample_stats
        out = {"divergences": int(st["diverging"].sum()),
               "max_tree_depth_share": float((st["tree_depth"] >= 10).mean()) if "tree_depth" in st else 0.0}
        if self.chains > 1:
            summ = az.summary(self.idata, var_names=["_sigma$"] + list(self.fixed_samples().keys()),
                              filter_vars="regex")
            out["max_r_hat"] = float(summ["r_hat"].max())
            out["min_ess_bulk"] = float(summ["ess_bulk"].min())
        bad = (out["divergences"] > 0 or out["max_tree_depth_share"] > 0.05
               or out.get("max_r_hat", 1.0) > 1.01 or out.get("min_ess_bulk", 1e9) < 400)
        self.diagnostics = {**out, "ok": not bad}
        if bad:
            print(f"WARNING: fit not converged well enough to ship: {self.diagnostics}")
        return self.diagnostics

    def predict(self, df: pd.DataFrame) -> np.ndarray:
        """Posterior mean P(y=1); unseen users get the population distribution."""
        new = self.model.predict(self.idata, data=self._data(df), kind="response_params",
                                 sample_new_groups=True, inplace=False)
        name = [v for v in new.posterior.data_vars if v not in self.idata.posterior.data_vars]
        name = name[0] if name else "p"
        return new.posterior[name].mean(("chain", "draw")).values

    # ---- pieces the prior builder needs
    def fixed_samples(self) -> dict[str, np.ndarray]:
        """Flattened posterior draws of every population-level coefficient."""
        post = self.idata.posterior
        return {v: post[v].values.ravel() for v in post.data_vars
                if "|" not in v and not v.endswith("_sigma") and post[v].ndim == 2}

    def fixed_effects(self) -> pd.DataFrame:
        rows = [(k, s.mean(), s.var()) for k, s in self.fixed_samples().items()]
        return pd.DataFrame(rows, columns=["term", "mean", "var"]).set_index("term")

    def group_sigmas(self) -> dict[str, float]:
        """Between-user SD for each random term (posterior mean)."""
        post = self.idata.posterior
        return {v.split("|")[0]: float(post[v].mean()) for v in post.data_vars if v.endswith("|userID_sigma")}
