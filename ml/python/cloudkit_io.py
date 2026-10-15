"""Talk to the app's CloudKit PUBLIC database with a server-to-server key.

    export CK_KEY_ID=...                 # from CloudKit Console > Tokens & Keys
    export CK_KEY_FILE=eckey.pem         # private key you generated (see README)

    python cloudkit_io.py export  --env production --out data/export
    python cloudkit_io.py publish --env production --params out/policy_params.json

export   pulls every record of each type into <out>/<RecordType>.parquet, plus
         _meta.json with the export time (used to drop unresolved outcomes).
publish  writes the prior as a PolicyParams record named "current" (the app reads
         it) and an immutable copy named after the policyVersion (audit trail).

TestFlight builds talk to the PRODUCTION environment.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

import config as C

API = "https://api.apple-cloudkit.com"
BOOL_FIELDS = {"fimDeSemana", "feriado", "ocupadoNoMomento", "resultouEmConsumo", "intakeInWindow"}


class CloudKit:
    def __init__(self, key_id: str, key_file: str, env: str = "production", container: str = C.CONTAINER):
        self.key_id = key_id
        self.key = serialization.load_pem_private_key(Path(key_file).read_bytes(), password=None)
        self.base = f"/database/1/{container}/{env}/public"

    def _post(self, op: str, body: dict) -> dict:
        subpath = f"{self.base}/{op}"
        payload = json.dumps(body, separators=(",", ":"))
        date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        body_hash = base64.b64encode(hashlib.sha256(payload.encode()).digest()).decode()
        sig = self.key.sign(f"{date}:{body_hash}:{subpath}".encode(), ec.ECDSA(hashes.SHA256()))
        r = requests.post(API + subpath, data=payload, timeout=60, headers={
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": base64.b64encode(sig).decode(),
        })
        if r.status_code != 200:
            raise RuntimeError(f"CloudKit {op} failed ({r.status_code}): {r.text[:500]}")
        return r.json()

    def query_all(self, record_type: str) -> list[dict]:
        """Needs a QUERYABLE index on recordName for this type (CloudKit Console > Indexes)."""
        records, marker = [], None
        while True:
            body = {"zoneID": {"zoneName": "_defaultZone"}, "resultsLimit": 200,
                    "query": {"recordType": record_type}}
            if marker:
                body["continuationMarker"] = marker
            res = self._post("records/query", body)
            for rec in res.get("records", []):
                if "serverErrorCode" in rec:
                    raise RuntimeError(f"{record_type}: {rec['serverErrorCode']} {rec.get('reason')}")
                records.append(rec)
            marker = res.get("continuationMarker")
            if not marker:
                return records

    def force_replace(self, record_type: str, record_name: str, fields: dict) -> None:
        ops = [{"operationType": "forceReplace",
                "record": {"recordType": record_type, "recordName": record_name,
                           "fields": {k: {"value": v} for k, v in fields.items()}}}]
        res = self._post("records/modify", {"operations": ops, "atomic": False})
        for rec in res.get("records", []):
            if "serverErrorCode" in rec:
                raise RuntimeError(f"{record_name}: {rec['serverErrorCode']} {rec.get('reason')}")


def records_to_frame(records: list[dict]) -> pd.DataFrame:
    rows = []
    for rec in records:
        row = {"recordName": rec["recordName"]}
        for name, f in rec.get("fields", {}).items():
            v, t = f.get("value"), f.get("type")
            if t == "TIMESTAMP":
                v = pd.Timestamp(v, unit="ms", tz="UTC")
            elif t == "REFERENCE":
                v = v.get("recordName")
            row[name] = v
        rows.append(row)
    df = pd.DataFrame(rows)
    if "id" not in df and "recordName" in df:
        df["id"] = df["recordName"]
    for c in BOOL_FIELDS & set(df.columns):
        df[c] = df[c].map(lambda v: None if pd.isna(v) else bool(v))
    return df


def cmd_export(ck: CloudKit, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for rt in C.RECORD_TYPES:
        try:
            df = records_to_frame(ck.query_all(rt))
        except RuntimeError as e:
            print(f"{rt}: skipped ({e})")     # e.g. SlotDecision before the type exists
            continue
        df.to_parquet(out / f"{rt}.parquet")
        print(f"{rt}: {len(df)} records")
    (out / "_meta.json").write_text(json.dumps({"exportedAt": datetime.now(timezone.utc).isoformat()}))


def cmd_publish(ck: CloudKit, params_path: Path) -> None:
    text = params_path.read_text()
    version = json.loads(text)["policyVersion"]
    fields = {"json": text, "policyVersion": version}
    ck.force_replace("PolicyParams", f"v-{version}", fields)   # audit copy first
    ck.force_replace("PolicyParams", "current", fields)
    print(f"published {version}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["export", "publish"])
    ap.add_argument("--env", default="production", choices=["production", "development"])
    ap.add_argument("--out", default="data/export")
    ap.add_argument("--params", default="out/policy_params.json")
    a = ap.parse_args()
    ck = CloudKit(os.environ["CK_KEY_ID"], os.environ["CK_KEY_FILE"], a.env)
    if a.command == "export":
        cmd_export(ck, Path(a.out))
    else:
        cmd_publish(ck, Path(a.params))


if __name__ == "__main__":
    main()
