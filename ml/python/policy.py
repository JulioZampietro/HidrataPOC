"""Reference implementation of the on-device policy. ThompsonPolicy.swift must
behave identically; `write_parity_vectors` produces fixtures for a Swift unit test.

Model: Bayesian logistic regression with a diagonal Gaussian posterior, per user.
    P(intake in window | context x, action a) = sigmoid(w . phi(x, a))
    phi(x, a) = [x, a * x]   with x = [1, standardized features], a = 1 for send
The first block is the user's natural drinking tendency in that context; the
second is the extra effect of sending a reminder.

Decision per slot (objective set in the params):
    response: send if p_send - lambda > 0
    uplift:   send if p_send - lambda > p_skip
Thompson sampling + epsilon + propensity floor; the propensity of the chosen
action is logged. Quiet hours are a hard rule: never send, nothing logged.

Adapting over time: before each decision or update, precision decays toward
the prior precision by dailyDecay ** days_elapsed. Means are kept, so the policy
remembers what it learned but becomes less sure of it, explores again, and lets
recent outcomes move it if the user's routine has changed.
"""
from __future__ import annotations

import json
import math

import numpy as np

from dataset import FeatureSpec


def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-z))


def is_quiet(params: dict, minute_of_day: float) -> bool:
    s, e = params["quietStartMinute"], params["quietEndMinute"]
    return (minute_of_day >= s or minute_of_day < e) if s > e else (s <= minute_of_day < e)


def encode(raw: dict, spec: FeatureSpec) -> np.ndarray:
    """Raw feature dict (as stored in SlotDecision.featuresJSON) -> [1, x...]."""
    x = [1.0]
    for n in spec.names:
        v = raw.get(n)
        v = spec.impute[n] if v is None or (isinstance(v, float) and math.isnan(v)) else float(v)
        x.append((v - spec.mean[n]) / spec.std[n])
    return np.array(x)


def phi(x: np.ndarray, send: bool) -> np.ndarray:
    return np.concatenate([x, x if send else np.zeros_like(x)])


class ThompsonPolicy:
    def __init__(self, params: dict, mean=None, precision=None, last_update_days=None):
        self.p = params
        self.spec = FeatureSpec.from_json(params["features"])
        self.prior_mean = np.array(params["priorMean"], dtype=float)
        self.prior_prec = 1.0 / np.array(params["priorVar"], dtype=float)
        self.mean = self.prior_mean.copy() if mean is None else np.array(mean, dtype=float)
        self.prec = self.prior_prec.copy() if precision is None else np.array(precision, dtype=float)
        self.last_t = last_update_days          # days since epoch (float) of the last decay

    # ------------------------------------------------------------ forgetting
    def decay_to(self, t_days: float | None) -> None:
        if t_days is None:
            return
        if self.last_t is not None and t_days > self.last_t:
            g = self.p["dailyDecay"] ** (t_days - self.last_t)
            self.prec = self.prior_prec + g * (self.prec - self.prior_prec)
        self.last_t = t_days if self.last_t is None else max(self.last_t, t_days)

    # ---------------------------------------------------------------- decide
    def _prefers_send(self, w: np.ndarray, x: np.ndarray) -> bool:
        p_send = sigmoid(w @ phi(x, True))
        p_skip = sigmoid(w @ phi(x, False))
        skip_score = p_skip if self.p["objective"] == "uplift" else 0.0
        return (p_send - self.p["lambda"]) > skip_score

    def prob_send(self, x: np.ndarray, rng: np.random.Generator) -> float:
        """P(send | x) under the logging policy: Monte Carlo Thompson + epsilon + floor."""
        m = self.p["mcSamples"]
        sd = 1.0 / np.sqrt(self.prec)
        draws = self.mean + sd * rng.standard_normal((m, self.mean.size))
        p_send = sigmoid(draws @ phi(x, True))
        p_skip = sigmoid(draws @ phi(x, False))
        skip_score = p_skip if self.p["objective"] == "uplift" else 0.0
        p_ts = float(np.mean((p_send - self.p["lambda"]) > skip_score))
        eps, floor = self.p["epsilon"], self.p["propensityFloor"]
        p = eps * 0.5 + (1 - eps) * p_ts
        return float(min(max(p, floor), 1 - floor))

    def decide(self, raw: dict, rng: np.random.Generator, slot_minute: float,
               t_days: float | None = None) -> tuple[bool, float] | None:
        """Returns (send, propensity of the chosen action), or None for a quiet slot
        (no decision is made or logged there)."""
        if is_quiet(self.p, slot_minute):
            return None
        self.decay_to(t_days)
        ps = self.prob_send(encode(raw, self.spec), rng)
        send = rng.random() < ps
        return send, (ps if send else 1 - ps)

    def greedy_prob_send(self, x: np.ndarray) -> float:
        """Deterministic version (posterior mean), used as a target policy in OPE."""
        return 1.0 if self._prefers_send(self.mean, x) else 0.0

    # ---------------------------------------------------------------- update
    def update(self, raw: dict, send: bool, y: bool, t_days: float | None = None) -> None:
        """Exact MAP for one observation under a diagonal Gaussian prior, then a
        Laplace precision update. w = m + (y - p) Q^-1 phi, with p solving
        p = sigmoid(m.phi + (y - p) s), s = sum(phi^2 / q)."""
        self.decay_to(t_days)
        f = phi(encode(raw, self.spec), send)
        a = float(self.mean @ f)
        s = float(np.sum(f * f / self.prec))
        yv = 1.0 if y else 0.0
        lo, hi = 0.0, 1.0
        for _ in range(60):                       # bisection: g(p) is increasing in p
            mid = 0.5 * (lo + hi)
            if mid - sigmoid(a + (yv - mid) * s) > 0:
                hi = mid
            else:
                lo = mid
        p = 0.5 * (lo + hi)
        self.mean = self.mean + (yv - p) * f / self.prec
        self.prec = self.prec + p * (1 - p) * f * f

    @classmethod
    def rebuilt(cls, params: dict, history: list[tuple[dict, bool, bool, float]]) -> "ThompsonPolicy":
        """A new prior arrived: replay the user's resolved decisions (raw, send, y, t_days)
        on top of it, oldest first, so personalization survives prior updates."""
        pol = cls(params)
        for raw, send, y, t in sorted(history, key=lambda h: h[3]):
            pol.update(raw, send, y, t)
        return pol


def write_parity_vectors(params: dict, path: str, n: int = 6, seed: int = 0) -> None:
    """Fixtures for ThompsonPolicyTests.swift: encoded x and posterior after each
    update, including imputation and decay across days."""
    rng = np.random.default_rng(seed)
    pol = ThompsonPolicy(params)
    cases, t = [], 20000.0
    for i in range(n):
        raw = {f["name"]: float(rng.normal(f["mean"], f["std"])) if f["kind"] == "numeric"
               else float(rng.integers(0, 2)) for f in params["features"]}
        if i == 0:
            raw.pop("log_min_since_last", None)          # exercise imputation
        send, y = bool(i % 2 == 0), bool(i % 3 == 0)
        t += 0.1 if i % 2 else 3.0                        # exercise decay
        x = encode(raw, pol.spec)
        pol.update(raw, send, y, t)
        cases.append({"raw": raw, "send": send, "y": y, "tDays": t, "encoded": x.tolist(),
                      "meanAfter": pol.mean.tolist(), "precisionAfter": pol.prec.tolist()})
    quiet = {str(m): is_quiet(params, m) for m in (0, 7 * 60 + 59, 8 * 60, 20 * 60, 21 * 60 + 59, 22 * 60)}
    with open(path, "w") as fh:
        json.dump({"policyVersion": params["policyVersion"], "cases": cases, "quiet": quiet}, fh, indent=1)
