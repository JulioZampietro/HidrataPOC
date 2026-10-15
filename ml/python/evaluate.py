"""Compare the models offline on NotificationEvent data.

    python evaluate.py --data data/export            # baseline + gbm
    python evaluate.py --data data/export --hier     # + hierarchical (slower)

Two protocols:
  time split    train on the past, test on the last 20%  -> "known users, future days"
  user folds    GroupKFold by userID                      -> "brand-new users" (cold start)

While the app still sends every slot, P(intake | send) is observed at every slot,
so this evaluation is unbiased for the response objective. Once the bandit starts
skipping slots, use ope.py instead.
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd
from sklearn.metrics import brier_score_loss, log_loss, roc_auc_score
from sklearn.model_selection import GroupKFold

import dataset as D
from models import GBM, Baseline, Hierarchical


def ece(y, p, bins=10) -> float:
    """Expected calibration error: matters because the policy thresholds probabilities."""
    edges = np.quantile(p, np.linspace(0, 1, bins + 1))
    idx = np.clip(np.searchsorted(edges, p, side="right") - 1, 0, bins - 1)
    return float(sum(abs(y[idx == b].mean() - p[idx == b].mean()) * (idx == b).mean()
                     for b in range(bins) if (idx == b).any()))


def top_k_hit_rate(df: pd.DataFrame, p: np.ndarray, k: int = 3) -> float:
    """If we had sent only the k best-scored slots per user-day, how often would
    they have converted? Compare with the all-slots rate."""
    d = df.assign(p=p)
    top = d.sort_values("p", ascending=False).groupby(["userID", "local_date"]).head(k)
    return float(top["y"].mean())


def metrics(df, p) -> dict:
    y = df["y"].values
    return {"logloss": log_loss(y, p, labels=[0, 1]), "brier": brier_score_loss(y, p),
            "auc": roc_auc_score(y, p) if len(set(y)) > 1 else np.nan,
            "ece": ece(y, p), "top3_rate": top_k_hit_rate(df, p, 3), "all_rate": y.mean()}


def run(df: pd.DataFrame, use_hier: bool, folds: int = 5) -> pd.DataFrame:
    factories = {"baseline": Baseline, "gbm": GBM}
    if use_hier:
        factories["hierarchical"] = lambda: Hierarchical(draws=500, tune=500)
    rows = []

    tr, te = D.time_split(df)
    for name, make in factories.items():
        rows.append({"protocol": "time", "model": name, **metrics(te, make().fit(tr).predict(te))})

    gkf = GroupKFold(n_splits=min(folds, df["userID"].nunique()))
    for name, make in factories.items():
        preds = np.zeros(len(df))
        for tr_idx, te_idx in gkf.split(df, groups=df["userID"]):
            m = make().fit(df.iloc[tr_idx])
            preds[te_idx] = m.predict(df.iloc[te_idx])
        rows.append({"protocol": "new_users", "model": name, **metrics(df, preds)})
    return pd.DataFrame(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--hier", action="store_true")
    a = ap.parse_args()
    t = D.load_tables(a.data)
    df = D.raw_features_from_events(t["NotificationEvent"], t["UserProfile"])
    df = D.drop_unresolved(df, D.export_time(a.data))
    print(f"{len(df)} events, {df['userID'].nunique()} users, base rate {df['y'].mean():.3f}")
    with pd.option_context("display.float_format", "{:.4f}".format, "display.width", 140):
        print(run(df, a.hier).to_string(index=False))


if __name__ == "__main__":
    main()
