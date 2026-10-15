"""Does the on-device policy personalize, and does it re-adapt when a user's
routine changes? Simulation only (needs the hidden ground truth).

    python check_adaptation.py --params out/policy_params.json --days 70 --shift-day 35

For every slot decision we measure the circular distance between the slot and
the user's CURRENT preferred hour, and report the send rate near (<= 2h) vs far
(>= 5h) from it, per week. A personalized policy shows a growing gap; after the
shift, a policy that forgets re-opens the gap, one that never forgets lags.
"""
from __future__ import annotations

import argparse
import copy
import json

import numpy as np
import pandas as pd

import simulate as S


def run(params, users, days, shift_day, seed):
    rng = np.random.default_rng(seed)
    _, _, dec = S.simulate(users, days, rng, params, shift_day)
    d = (dec["slotHour"] - dec["_pref_hour"]).abs()
    dec["dist"] = np.minimum(d, 24 - d)
    dec["week"] = ((dec["slotFiresAt"] - dec["slotFiresAt"].min()).dt.days // 7) + 1
    dec["send"] = dec["actionRaw"] == "send"
    near = dec[dec["dist"] <= 2].groupby("week")["send"].mean()
    far = dec[dec["dist"] >= 5].groupby("week")["send"].mean()
    hit = dec[dec["send"]].groupby("week")["intakeInWindow"].mean()
    return pd.DataFrame({"send_near": near, "send_far": far, "gap": near - far,
                         "response_rate_of_sends": hit})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", default="out/policy_params.json")
    ap.add_argument("--users", type=int, default=30)
    ap.add_argument("--days", type=int, default=70)
    ap.add_argument("--shift-day", type=int, default=35)
    ap.add_argument("--seed", type=int, default=3)
    a = ap.parse_args()
    params = json.load(open(a.params))
    users = S.make_users(a.users, np.random.default_rng(a.seed))

    for decay in (1.0, params["dailyDecay"]):
        p = copy.deepcopy(params)
        p["dailyDecay"] = decay
        res = run(p, users, a.days, a.shift_day, a.seed + 1)
        label = "no forgetting" if decay == 1.0 else f"dailyDecay={decay}"
        print(f"\n== {label}  (routine shifts at day {a.shift_day}, week {a.shift_day // 7 + 1})")
        print(res.round(2).to_string())


if __name__ == "__main__":
    main()
