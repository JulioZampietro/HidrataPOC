"""Turns the exported CloudKit tables into model-ready frames.

Two sources of training rows:
  * NotificationEvent  -> one row per reminder sent (bootstrap phase, action = send)
  * SlotDecision       -> one row per slot decision, send or skip (bandit phase)

Both end up with the same raw feature columns (config.LINEAR_FEATURES), so the
same FeatureSpec standardizes them and the device reproduces it from JSON.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

import config as C


# ---------------------------------------------------------------- loading
def load_tables(data_dir: str | Path) -> dict[str, pd.DataFrame]:
    data_dir = Path(data_dir)
    out = {}
    for rt in C.RECORD_TYPES:
        p = data_dir / f"{rt}.parquet"
        out[rt] = pd.read_parquet(p) if p.exists() else pd.DataFrame()
    for name, df in out.items():
        for col in ("sentAt", "timestamp", "slotFiresAt", "decidedAt", "criadoEm", "atualizadoEm"):
            if col in df:
                df[col] = pd.to_datetime(df[col], utc=True)
    return out


def export_time(data_dir: str | Path) -> pd.Timestamp:
    """Written by cloudkit_io.py; rows newer than this minus the window are unresolved."""
    meta = Path(data_dir) / "_meta.json"
    if meta.exists():
        return pd.Timestamp(json.loads(meta.read_text())["exportedAt"])
    return pd.Timestamp.now(tz="UTC")


def latest_profiles(profiles: pd.DataFrame) -> pd.DataFrame:
    """One row per userID (the most recently updated profile)."""
    if profiles.empty:
        return profiles
    sort_col = "atualizadoEm" if "atualizadoEm" in profiles else "criadoEm"
    return profiles.sort_values(sort_col).groupby("userID", as_index=False).last()


def to_local(ts: pd.Series, tz: pd.Series) -> pd.Series:
    """UTC timestamps -> naive local wall-clock time, per row time zone."""
    tz = tz.fillna(C.DEFAULT_TZ)
    out = pd.Series(pd.NaT, index=ts.index, dtype="datetime64[ns]")
    for zone, idx in tz.groupby(tz).groups.items():
        try:
            out.loc[idx] = ts.loc[idx].dt.tz_convert(zone).dt.tz_localize(None).values
        except Exception:  # unknown zone id
            out.loc[idx] = ts.loc[idx].dt.tz_convert(C.DEFAULT_TZ).dt.tz_localize(None).values
    return out


# ---------------------------------------------------------- raw features
def hour_features(hour):
    """Local hour (float or array) -> 24h and 12h harmonics. Mirrored in Swift."""
    w = 2 * np.pi * np.asarray(hour, dtype=float) / 24
    return {"hour_sin": np.sin(w), "hour_cos": np.cos(w),
            "hour_sin2": np.sin(2 * w), "hour_cos2": np.cos(2 * w)}


def _age_from_band(band) -> float:
    """Midpoint of the app's 5-year band ("30-34" -> 32.0, "80+" -> 82.0)."""
    if not isinstance(band, str):
        return np.nan
    if band == "80+":
        return 82.0
    parts = band.split("-")
    if len(parts) != 2:
        return np.nan
    try:
        return (int(parts[0]) + int(parts[1])) / 2
    except ValueError:
        return np.nan


def _profile_features(df: pd.DataFrame) -> pd.DataFrame:
    """`age` and `bmi` come straight from the record when the app pseudonymized them
    (CloudKitSyncService.push(_ profile:) sends `faixaIdade` + `bmi` instead of exact
    age, weight and height). Exports taken before that change still carry the raw
    columns, so both shapes are accepted and the older one wins when present."""
    df = df.copy()
    gen = df.get("genero")
    df["female"] = np.where(gen == "feminino", 1.0, np.where(gen == "masculino", 0.0, np.nan))
    df["goal_l"] = df.get("metaDiariaML") / 1000.0

    if "idade" in df:
        df["age"] = df["idade"]
    elif "faixaIdade" in df:
        df["age"] = df["faixaIdade"].map(_age_from_band)
    else:
        df["age"] = np.nan

    if "pesoKg" in df and "alturaCm" in df:
        h = df["alturaCm"] / 100.0
        df["bmi"] = df["pesoKg"] / (h * h)
    elif "bmi" not in df:
        df["bmi"] = np.nan
    return df


def raw_features_from_events(events: pd.DataFrame, profiles: pd.DataFrame) -> pd.DataFrame:
    """NotificationEvent rows -> raw features + label. All rows have send = 1."""
    df = events.merge(latest_profiles(profiles), on="userID", how="left", suffixes=("", "_profile"))
    df = _profile_features(df)

    local = to_local(df["sentAt"], df.get("fusoHorario", pd.Series(index=df.index, dtype=object)))
    hour = local.dt.hour + local.dt.minute / 60.0
    df["local_date"] = local.dt.date
    df["slot_hour"] = hour.apply(lambda h: min(C.SLOT_HOURS, key=lambda s: abs(s - h)))
    for k, v in hour_features(hour).items():
        df[k] = v
    df["dow"] = local.dt.dayofweek.astype(str)
    df["weekend"] = (local.dt.dayofweek >= 5).astype(float)

    df["apparent_temp"] = df["sensacaoTermicaC"].fillna(df["temperaturaC"])
    df["humidity"] = df["umidadeRelativa"]
    df["busy"] = df["ocupadoNoMomento"].astype(float)
    df["event_density"] = df["densidadeEventosDia"].astype(float)
    df["deficit_frac"] = (df["deficitAcumuladoML"] / df["metaDiariaML"]).clip(-1.0, 1.5)
    mins = df["tempoDesdeUltimoRegistroMin"]
    df["no_intake_yet"] = mins.isna().astype(float)
    df["log_min_since_last"] = np.log1p(mins.clip(lower=0))
    df["variant"] = df["notificationVariant"].fillna("unknown")

    df["send"] = 1
    df["y"] = df["resultouEmConsumo"].astype(int)
    df["decision_time"] = df["sentAt"]
    return _add_user_history(df)


def raw_features_from_decisions(decisions: pd.DataFrame, profiles: pd.DataFrame) -> pd.DataFrame:
    """SlotDecision rows -> raw features exactly as the device saw them."""
    d = decisions[decisions["intakeInWindow"].notna()].copy()   # resolved only
    feats = pd.DataFrame([json.loads(s) for s in d["featuresJSON"]], index=d.index)
    df = pd.concat([d, feats], axis=1)
    prof = _profile_features(latest_profiles(profiles))
    df = df.merge(prof[["userID", "bmi", "goal_l", "fusoHorario"]], on="userID", how="left")
    local = to_local(df["slotFiresAt"], df["fusoHorario"])
    df["local_date"] = local.dt.date
    df["slot_hour"] = df["slotHour"]
    df["dow"] = local.dt.dayofweek.astype(str)
    df["variant"] = df["notificationVariant"].fillna("none")
    df["send"] = (df["actionRaw"] == "send").astype(int)
    df["y"] = df["intakeInWindow"].astype(int)
    df["decision_time"] = df["decidedAt"]
    return _add_user_history(df)


def _add_user_history(df: pd.DataFrame) -> pd.DataFrame:
    """Leak-free per-user response history (only outcomes before this row)."""
    df = df.sort_values(["userID", "decision_time"]).copy()
    g = df.groupby("userID")["y"]
    df["user_prev_n"] = g.cumcount()
    prev_hits = g.cumsum() - df["y"]
    df["user_prev_rate"] = (prev_hits + 1) / (df["user_prev_n"] + 4)   # Beta(1,3) smoothing
    return df.reset_index(drop=True)


def drop_unresolved(df: pd.DataFrame, export_time: pd.Timestamp) -> pd.DataFrame:
    """Outcomes need RESPONSE_WINDOW_MIN to resolve; drop rows that are too recent."""
    cutoff = export_time - pd.Timedelta(minutes=C.RESPONSE_WINDOW_MIN + 5)
    return df[df["decision_time"] < cutoff]


# -------------------------------------------- natural (un-prompted) rate
def estimate_natural_rate(intakes: pd.DataFrame, profiles: pd.DataFrame,
                          offset_min: int = 60) -> float:
    """Share of 10-minute probe windows (slot + 60 min, far from reminders) that
    contain a manual log, over user-days with at least one log. A rough prior for
    P(intake | skip). Replace it with real skip outcomes once SlotDecision exists."""
    if intakes.empty:
        return 0.05
    df = intakes.merge(latest_profiles(profiles)[["userID", "fusoHorario"]], on="userID", how="left")
    df["local"] = to_local(df["timestamp"], df["fusoHorario"])
    df["date"] = df["local"].dt.date
    manual = df[df["origem"] == "manual"] if "origem" in df else df
    hits, total = 0, 0
    for (_, _), day in df.groupby(["userID", "date"]):
        m = manual.loc[manual.index.intersection(day.index), "local"]
        mins = (m.dt.hour * 60 + m.dt.minute).values
        for s in C.ACTIVE_SLOT_HOURS:
            start = s * 60 + offset_min
            total += 1
            hits += int(((mins >= start) & (mins < start + C.RESPONSE_WINDOW_MIN)).any())
    return (hits + 1) / (total + 20)


# ------------------------------------------------------- standardization
@dataclass
class FeatureSpec:
    """Imputation + standardization for LINEAR_FEATURES. Exported to the device."""
    names: list[str] = field(default_factory=lambda: list(C.LINEAR_FEATURES))
    mean: dict = field(default_factory=dict)
    std: dict = field(default_factory=dict)
    impute: dict = field(default_factory=dict)

    def fit(self, df: pd.DataFrame) -> "FeatureSpec":
        for n in self.names:
            col = df[n].astype(float)
            med = col.median()
            self.impute[n] = float(0.5 if np.isnan(med) else (col.mean() if n in C.BINARY_FEATURES else med))
            if n in C.BINARY_FEATURES:
                self.mean[n], self.std[n] = 0.0, 1.0
            else:
                filled = col.fillna(self.impute[n])
                sd = filled.std()
                self.mean[n] = float(filled.mean())
                self.std[n] = float(sd if sd and sd > 1e-9 else 1.0)
        return self

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        out = pd.DataFrame(index=df.index)
        for n in self.names:
            out[n] = (df[n].astype(float).fillna(self.impute[n]) - self.mean[n]) / self.std[n]
        return out

    def to_json(self) -> list[dict]:
        return [{"name": n,
                 "kind": "binary" if n in C.BINARY_FEATURES else "numeric",
                 "mean": self.mean[n], "std": self.std[n], "impute": self.impute[n]}
                for n in self.names]

    @classmethod
    def from_json(cls, items: list[dict]) -> "FeatureSpec":
        s = cls(names=[i["name"] for i in items])
        for i in items:
            s.mean[i["name"]], s.std[i["name"]], s.impute[i["name"]] = i["mean"], i["std"], i["impute"]
        return s


# ----------------------------------------------------------------- splits
def time_split(df: pd.DataFrame, test_frac: float = 0.2):
    cut = df["decision_time"].quantile(1 - test_frac)
    return df[df["decision_time"] < cut].copy(), df[df["decision_time"] >= cut].copy()
