"""Fit the hierarchical model on all users and export policy_params.json, the
file the app downloads (or bundles) to initialize every user's bandit.

    # bootstrap: only NotificationEvent exists (every slot was sent)
    python build_prior.py --data data/export --source events --out out/

    # later: refit on SlotDecision (send + skip outcomes, real uplift)
    python build_prior.py --data data/export --source decisions --out out/

Vector layout on the device (length 2 * (1 + n_features)):
    [base: 1, f1..fn | send: 1, f1..fn]
Prior for a NEW user = population posterior mean, with variance = posterior
variance + between-user variance (sigma^2) for terms with random effects, plus a
small floor so every coefficient can still adapt to the individual user.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

import config as C
import dataset as D
from models import Hierarchical
from policy import write_parity_vectors


def _logit(p):
    return float(np.log(p / (1 - p)))


def prior_from_events(h: Hierarchical, natural_rate: float, var_floor: float):
    """Bootstrap: the data only identifies base + send (everything was sent).
    Put a weak, data-informed prior on the base block (natural drinking rate) and
    the rest of the signal in the send block."""
    fe, sig = h.fixed_effects(), h.group_sigmas()
    names = ["Intercept"] + C.LINEAR_FEATURES
    beta = np.array([fe.loc[n, "mean"] for n in names])
    var = np.array([fe.loc[n, "var"] for n in names])
    var += np.array([sig.get("1" if n == "Intercept" else n, 0.0) ** 2 for n in names])

    base_mean = np.zeros(len(names))
    base_mean[0] = _logit(natural_rate)
    base_var = np.full(len(names), 0.3 ** 2)
    base_var[0] = 0.5 ** 2
    send_mean = beta - base_mean
    send_var = np.maximum(var, var_floor)
    return np.concatenate([base_mean, send_mean]), np.concatenate([base_var, send_var])


def prior_from_decisions(h: Hierarchical, var_floor: float):
    """Split fit -> device layout. base = skip block; send effect = send - skip,
    computed draw by draw so the posterior covariance between the two is kept.
    A user's deviation in the send effect is (user send dev - user skip dev)."""
    s, sig = h.fixed_samples(), h.group_sigmas()
    names = ["Intercept"] + C.LINEAR_FEATURES
    base_mean, base_var, send_mean, send_var = [], [], [], []
    for n in names:
        kt, st = ("skip", "send") if n == "Intercept" else (f"{n}_k", f"{n}_s")
        k, d = s[kt], s[st] - s[kt]
        rk, rs = sig.get(kt, 0.0), sig.get(st, 0.0)
        base_mean.append(k.mean())
        base_var.append(k.var() + rk ** 2)
        send_mean.append(d.mean())
        send_var.append(d.var() + rk ** 2 + rs ** 2)
    mean = np.array(base_mean + send_mean)
    return mean, np.maximum(np.array(base_var + send_var), var_floor)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--source", choices=["events", "decisions"], default="events")
    ap.add_argument("--out", default="out")
    ap.add_argument("--objective", choices=["response", "uplift"], default="response")
    ap.add_argument("--lam", type=float, default=0.10,
                    help="cost of one reminder, in units of P(intake). response: send if p_send > lam")
    ap.add_argument("--epsilon", type=float, default=0.10, help="share of uniformly random decisions")
    ap.add_argument("--floor", type=float, default=0.05, help="min probability of either action")
    ap.add_argument("--var-floor", type=float, default=0.15 ** 2,
                    help="min prior variance per coefficient: room for each user to differ")
    ap.add_argument("--decay", type=float, default=C.DAILY_DECAY,
                    help="daily forgetting factor on the device (1.0 = never forget)")
    ap.add_argument("--draws", type=int, default=1000)
    ap.add_argument("--chains", type=int, default=4)
    ap.add_argument("--sampler", default="pymc", choices=["pymc", "nutpie"])
    ap.add_argument("--max-users", type=int, help="fit on a subset of users (quick dry runs only)")
    ap.add_argument("--force", action="store_true", help="write params even if the fit did not converge")
    a = ap.parse_args()

    t = D.load_tables(a.data)
    if a.source == "events":
        df = D.raw_features_from_events(t["NotificationEvent"], t["UserProfile"])
    else:
        df = D.raw_features_from_decisions(t["SlotDecision"], t["UserProfile"])
    df = D.drop_unresolved(df, D.export_time(a.data))
    if a.max_users:
        df = df[df["userID"].isin(sorted(df["userID"].unique())[:a.max_users])]
    print(f"fitting on {len(df)} rows from {df['userID'].nunique()} users ({a.source})")

    h = Hierarchical(with_send=a.source == "decisions", draws=a.draws, tune=a.draws, chains=a.chains,
                     sampler=a.sampler).fit(df)
    print(f"diagnostics: {h.diagnostics}")
    if not h.diagnostics["ok"] and not a.force:
        raise SystemExit("not writing policy_params.json: fit did not converge (use --force for dry runs)")
    if a.source == "events":
        nat = D.estimate_natural_rate(t["IntakeLog"], t["UserProfile"])
        print(f"natural 10-min intake rate (probe windows): {nat:.3f}")
        mean, var = prior_from_events(h, nat, a.var_floor)
    else:
        mean, var = prior_from_decisions(h, a.var_floor)

    body = {"features": h.spec.to_json(), "priorMean": mean.round(6).tolist(),
            "priorVar": var.round(6).tolist()}
    digest = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()[:8]
    params = {
        "policyVersion": f"{datetime.now(timezone.utc):%Y%m%d}-{a.source}-{digest}",
        "createdAt": datetime.now(timezone.utc).isoformat(),
        **body,
        "objective": a.objective, "lambda": a.lam, "epsilon": a.epsilon,
        "propensityFloor": a.floor, "mcSamples": 200,
        "dailyDecay": a.decay,
        "quietStartMinute": C.QUIET_START_MIN, "quietEndMinute": C.QUIET_END_MIN,
        "windowMinutes": C.RESPONSE_WINDOW_MIN, "slotHours": C.ACTIVE_SLOT_HOURS,
        "fitDiagnostics": {**h.diagnostics, "rows": int(len(df)), "users": int(df["userID"].nunique()),
                           "source": a.source},
    }
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "policy_params.json").write_text(json.dumps(params, indent=1))
    write_parity_vectors(params, str(out / "policy_parity_vectors.json"))
    try:   # keep the full posterior for diagnostics (needs h5netcdf or netCDF4)
        h.idata.to_netcdf(out / f"posterior_{params['policyVersion']}.nc")
    except ValueError as e:
        print(f"(posterior not saved: {e})")

    terms = ["Intercept"] + C.LINEAR_FEATURES
    show = pd.DataFrame({"base_mean": mean[:len(terms)], "send_mean": mean[len(terms):],
                         "send_sd": np.sqrt(var[len(terms):])}, index=terms)
    print(show.round(3).to_string())
    print(f"wrote {out/'policy_params.json'} ({params['policyVersion']})")


if __name__ == "__main__":
    main()
