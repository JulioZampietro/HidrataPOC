"""Off-policy evaluation on SlotDecision logs: "if we had run policy X instead of
the one that generated these logs, what would the average reward have been?"

    python ope.py --data data/export --params out/policy_params.json

Reward per slot decision (lambda = cost of a reminder, from the params):
    response objective:  r = send * (y - lambda)
    uplift objective:    r = y - lambda * send
Estimators: IPS, self-normalized IPS, and doubly robust with a cross-fitted
LightGBM reward model. Requires the logged propensity, which is why the app
stores SlotDecision.propensity for every decision.
"""
from __future__ import annotations

import argparse
import json

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupKFold

import dataset as D
from models import GBM
from policy import ThompsonPolicy, encode


def reward(y, send, objective, lam):
    return send * (y - lam) if objective == "response" else y - lam * send


def crossfit_q(df: pd.DataFrame, folds: int = 3) -> tuple[np.ndarray, np.ndarray]:
    """q(x, send=1), q(x, send=0), each predicted by a model that never saw that user."""
    q1, q0 = np.zeros(len(df)), np.zeros(len(df))
    for tr, te in GroupKFold(n_splits=folds).split(df, groups=df["userID"]):
        m = GBM(with_send=True).fit(df.iloc[tr])
        part = df.iloc[te]
        q1[te] = m.predict(part.assign(send=1))
        q0[te] = m.predict(part.assign(send=0))
    return q1, q0


def estimate(df, pi_send, q1, q0, objective, lam) -> dict:
    send = df["send"].values
    y = df["y"].values
    mu = df["propensity"].values                       # P(logged action | x) under logging policy
    pi_a = np.where(send == 1, pi_send, 1 - pi_send)   # P(logged action | x) under target policy
    w = pi_a / mu
    r = reward(y, send, objective, lam)
    r1, r0 = reward(q1, 1, objective, lam), reward(q0, 0, objective, lam)
    dm = pi_send * r1 + (1 - pi_send) * r0
    q_logged = np.where(send == 1, r1, r0)
    return {"IPS": np.mean(w * r), "SNIPS": np.sum(w * r) / np.sum(w),
            "DR": np.mean(dm + w * (r - q_logged)), "ESS": np.sum(w) ** 2 / np.sum(w ** 2),
            "send_rate": float(np.mean(pi_send))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--params", required=True)
    a = ap.parse_args()
    params = json.load(open(a.params))
    obj, lam = params["objective"], params["lambda"]

    t = D.load_tables(a.data)
    df = D.raw_features_from_decisions(t["SlotDecision"], t["UserProfile"])
    df = D.drop_unresolved(df, D.export_time(a.data)).reset_index(drop=True)
    print(f"{len(df)} decisions, logged send rate {df['send'].mean():.2f}, objective={obj}, lambda={lam}")

    q1, q0 = crossfit_q(df)
    pop = ThompsonPolicy(params)
    feats = [json.loads(s) for s in df["featuresJSON"]]
    skip_ref = q0 if obj == "uplift" else 0.0
    policies = {
        "always_send": np.ones(len(df)),
        "never_send": np.zeros(len(df)),
        "population_prior_greedy": np.array([pop.greedy_prob_send(encode(f, pop.spec)) for f in feats]),
        "gbm_greedy": ((q1 - lam) > skip_ref).astype(float),
    }

    rows = []
    for name, pi in policies.items():
        row = {"policy": name, **estimate(df, pi, q1, q0, obj, lam)}
        if "_p_send" in df:   # simulation only: ground truth
            ps, pk = df["_p_send"].values, df["_p_skip"].values
            row["TRUE"] = np.mean(pi * reward(ps, 1, obj, lam) + (1 - pi) * reward(pk, 0, obj, lam))
        rows.append(row)
    logged = reward(df["y"].values, df["send"].values, obj, lam).mean()
    with pd.option_context("display.float_format", "{:.4f}".format, "display.width", 140):
        print(pd.DataFrame(rows).to_string(index=False))
    print(f"logged policy (on-policy average): {logged:.4f}")


if __name__ == "__main__":
    main()
