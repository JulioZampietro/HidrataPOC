"""Synthetic data in the exact shape of the CloudKit export, so the whole
pipeline can be run and tested before real users exist.

    python simulate.py --out data/sim --users 40 --days 30
    python simulate.py --out data/sim --bandit-params out/policy_params.json   # adds SlotDecision

The ground truth is deliberately simple: each user has a preferred time of day,
reminders work worse when the calendar is busy and better when the deficit is high.
"""
from __future__ import annotations

import argparse
import json
import uuid
from pathlib import Path

import numpy as np
import pandas as pd

import config as C
from dataset import hour_features
from policy import ThompsonPolicy

TZ = "America/Sao_Paulo"


def _sig(z):
    return 1 / (1 + np.exp(-z))


def make_users(n: int, rng) -> pd.DataFrame:
    rows = []
    for _ in range(n):
        female = rng.random() < 0.5
        peso = rng.normal(64 if female else 80, 10)
        rows.append(dict(
            id=str(uuid.uuid4()), userID=f"_u{uuid.uuid4().hex[:12]}",
            idade=int(rng.integers(18, 65)), genero="feminino" if female else "masculino",
            pesoKg=round(peso, 1), alturaCm=round(rng.normal(163 if female else 176, 7), 1),
            fusoHorario=TZ, metaDiariaML=int(round(peso * 35, -1)), customIntakeML=300,
            criadoEm=pd.Timestamp("2026-08-01", tz="UTC"), atualizadoEm=pd.Timestamp("2026-08-01", tz="UTC"),
            # hidden ground truth, dropped before writing
            _pref_hour=rng.uniform(9, 20), _nat=rng.normal(0, 0.4), _resp=rng.normal(0, 0.6),
        ))
    return pd.DataFrame(rows)


def slot_context(user, day: pd.Timestamp, hour: int, rng) -> dict:
    weekend = day.dayofweek >= 5
    temp = 22 + 6 * np.sin(np.pi * (hour - 8) / 14) + rng.normal(0, 2.5)
    hum = float(np.clip(rng.normal(70 - 1.2 * (temp - 22), 10), 25, 100))
    busy = rng.random() < (0.45 if (not weekend and 9 <= hour <= 18) else 0.1)
    density = int(rng.poisson(1 if weekend else 3))
    deficit_frac = float(np.clip(rng.normal(0.05 + 0.25 * (hour - 8) / 14, 0.18), -0.5, 1.2))
    mins = None if (hour == 8 and rng.random() < 0.7) else float(rng.exponential(90))
    return dict(hour=hour, weekend=weekend, temp=temp, apparent=temp + 0.05 * (hum - 60),
                hum=hum, busy=busy, density=density, deficit_frac=deficit_frac, mins=mins)


def preferred_hour(user, day_idx: int, shift_day: int | None) -> float:
    """Optionally the user's routine changes: preferred hour moves 6h within 8..20."""
    h = user["_pref_hour"]
    if shift_day is not None and day_idx >= shift_day:
        h = (h - 8 + 6) % 12 + 8
    return h


def true_probs(user, ctx, pref_hour: float) -> tuple[float, float]:
    """(P(intake | skip), P(intake | send)) within the response window."""
    nat = -3.0 + user["_nat"] + 0.8 * ctx["deficit_frac"] + 0.03 * (ctx["apparent"] - 26)
    lift = (1.0 + user["_resp"]
            + 1.2 * np.cos(2 * np.pi * (ctx["hour"] - pref_hour) / 24)
            - 0.9 * ctx["busy"] + 0.6 * ctx["deficit_frac"] - 0.3 * ctx["weekend"])
    return float(_sig(nat)), float(_sig(nat + lift))


def raw_features(user, ctx) -> dict:
    """What the device would write into SlotDecision.featuresJSON."""
    return {
        **{k: float(v) for k, v in hour_features(ctx["hour"]).items()},
        "weekend": float(ctx["weekend"]), "apparent_temp": ctx["apparent"], "humidity": ctx["hum"],
        "busy": float(ctx["busy"]), "event_density": float(ctx["density"]),
        "deficit_frac": ctx["deficit_frac"],
        "log_min_since_last": None if ctx["mins"] is None else float(np.log1p(ctx["mins"])),
        "no_intake_yet": float(ctx["mins"] is None),
        "age": float(user["idade"]), "female": float(user["genero"] == "feminino"),
    }


def variant_for(ctx) -> str:
    if ctx["temp"] >= 28:
        return "hot_day"
    if ctx["temp"] <= 17:
        return "cold_day"
    if ctx["hour"] <= 10:
        return "mild_morning"
    if ctx["hour"] >= 20 and ctx["deficit_frac"] > 0.3:
        return "streak_risk_evening"
    return "midday_neutral"


def _utc(day, hour, minute=0.0):
    return (day + pd.Timedelta(hours=hour, minutes=minute)).tz_localize(TZ).tz_convert("UTC")


def simulate(users: pd.DataFrame, days: int, rng, params: dict | None = None,
             shift_day: int | None = None):
    events, intakes, decisions = [], [], []
    start = pd.Timestamp("2026-09-01")
    policies = {u: ThompsonPolicy(params) for u in users["userID"]} if params else {}
    for _, u in users.iterrows():
        for d in range(days):
            day = start + pd.Timedelta(days=d)
            # background (un-prompted) manual logs
            for _ in range(rng.poisson(5)):
                t = _utc(day, rng.uniform(7, 23))
                intakes.append(dict(id=str(uuid.uuid4()), userID=u["userID"], timestamp=t, volumeML=250,
                                    tipoEntrada="copo", origem="manual", source="app"))
            # bootstrap mimics today's app (all 8 slots, 22h included); the bandit
            # phase respects quiet hours, so 22h is never a candidate
            for h in (C.ACTIVE_SLOT_HOURS if params else C.SLOT_HOURS):
                ctx = slot_context(u, day, h, rng)
                pref = preferred_hour(u, d, shift_day)
                p_skip, p_send = true_probs(u, ctx, pref)
                raw = raw_features(u, ctx)
                fire = _utc(day, h)
                t_days = fire.timestamp() / 86400
                if params:                                  # bandit phase
                    decision = policies[u["userID"]].decide(raw, rng, h * 60, t_days - 110 / 1440)
                    if decision is None:                    # quiet slot: nothing sent, nothing logged
                        continue
                    send, prop = decision
                else:                                       # current app: send every slot
                    send, prop = True, 1.0
                y = rng.random() < (p_send if send else p_skip)
                ev_id = None
                if send:
                    ev_id = str(uuid.uuid4())
                    events.append(dict(
                        id=ev_id, userID=u["userID"], sentAt=fire, diaSemana=int(day.dayofweek) + 1,
                        fimDeSemana=bool(ctx["weekend"]), feriado=False,
                        temperaturaC=ctx["temp"], umidadeRelativa=ctx["hum"], sensacaoTermicaC=ctx["apparent"],
                        ocupadoNoMomento=bool(ctx["busy"]), densidadeEventosDia=ctx["density"],
                        deficitAcumuladoML=ctx["deficit_frac"] * u["metaDiariaML"],
                        tempoDesdeUltimoRegistroMin=ctx["mins"], notificationVariant=variant_for(ctx),
                        statusInteracao="aberta" if y else rng.choice(["ignorada", "soneca"]),
                        tempoAteAgirMin=float(rng.uniform(0, 10)) if y else None, resultouEmConsumo=bool(y)))
                if y:
                    intakes.append(dict(id=str(uuid.uuid4()), userID=u["userID"],
                                        timestamp=fire + pd.Timedelta(minutes=rng.uniform(0, 10)),
                                        volumeML=250, tipoEntrada="copo",
                                        origem="notificacao" if send else "manual", source="app",
                                        notificationEventID=ev_id))
                if params:
                    policies[u["userID"]].update(raw, send, y, t_days + C.RESPONSE_WINDOW_MIN / 1440)
                    decisions.append(dict(
                        id=str(uuid.uuid4()), userID=u["userID"], slotFiresAt=fire,
                        decidedAt=fire - pd.Timedelta(minutes=110), slotHour=h,
                        actionRaw="send" if send else "skip", propensity=prop,
                        policyVersion=params["policyVersion"], featuresJSON=json.dumps(raw),
                        notificationVariant=variant_for(ctx) if send else None,
                        notificationEventID=ev_id, intakeInWindow=bool(y),
                        _p_send=p_send, _p_skip=p_skip, _pref_hour=pref))   # ground truth
    return pd.DataFrame(events), pd.DataFrame(intakes), pd.DataFrame(decisions)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/sim")
    ap.add_argument("--users", type=int, default=40)
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--bandit-params", help="policy_params.json: also simulate the bandit phase")
    ap.add_argument("--shift-day", type=int, help="day on which every user's routine changes")
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    users = make_users(a.users, rng)
    params = json.load(open(a.bandit_params)) if a.bandit_params else None
    events, intakes, decisions = simulate(users, a.days, rng, params, a.shift_day)

    users.drop(columns=[c for c in users if c.startswith("_")]).to_parquet(out / "UserProfile.parquet")
    users.to_parquet(out / "_truth_users.parquet")
    events.to_parquet(out / "NotificationEvent.parquet")
    intakes.to_parquet(out / "IntakeLog.parquet")
    if params:
        decisions.to_parquet(out / "SlotDecision.parquet")
    print(f"users={len(users)} events={len(events)} intakes={len(intakes)} decisions={len(decisions)} -> {out}")


if __name__ == "__main__":
    main()
