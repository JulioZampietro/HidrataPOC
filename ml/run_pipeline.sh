#!/usr/bin/env bash
# One entry point for the reminder-timing prior. Run from the repo root.
#
#   ml/run_pipeline.sh setup                 # create venv + install deps (once)
#   ml/run_pipeline.sh export                # CloudKit -> ml/data/export/*.parquet (+ row counts)
#   ml/run_pipeline.sh counts                # row counts of an existing export
#   ml/run_pipeline.sh evaluate              # compare baseline / LightGBM / hierarchical
#   ml/run_pipeline.sh prior [events|decisions]   # fit -> ml/out/policy_params.json (default: events)
#   ml/run_pipeline.sh install               # copy the prior + parity fixture into the app + tests
#   ml/run_pipeline.sh publish               # push the prior to CloudKit (devices download it)
#
# `export` and `publish` need CK_KEY_ID and CK_KEY_FILE (see ml/PIPELINE_README.md > CloudKit setup).
# Set CK_ENV=development to hit the development database (default: production).
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")"
VENV=.venv
ENVNAME="${CK_ENV:-production}"
py() { "$VENV/bin/python" "$@"; }

case "${1:-}" in
  setup)
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q -r python/requirements.txt
    # PyTensor passes -ld64 on macOS >= 15, but current Xcode no longer ships that
    # linker, so its C compile step fails; drop the flag from the venv copy.
    f=$(echo "$VENV"/lib/python3*/site-packages/pytensor/link/c/cmodule.py)
    sed -i '' 's/cxxflags.append("-ld64")/pass/' "$f"
    echo "ready (needs: brew install libomp)" ;;
  export)
    : "${CK_KEY_ID:?set CK_KEY_ID}" "${CK_KEY_FILE:?set CK_KEY_FILE}"
    (cd python && ../"$VENV"/bin/python cloudkit_io.py export --env "$ENVNAME" --out ../data/export)
    "$SELF" counts ;;
  counts)
    py - <<'PY'
import json, pandas as pd
from pathlib import Path
d = Path("data/export")
for t in ["UserProfile", "IntakeLog", "NotificationEvent", "SlotDecision"]:
    p = d / f"{t}.parquet"
    if not p.exists():
        print(f"{t:<18} (missing)"); continue
    df = pd.read_parquet(p)
    users = df["userID"].nunique() if "userID" in df else "-"
    extra = ""
    if t == "NotificationEvent" and "statusInteracao" in df:
        extra = f"  resolved={int(df['statusInteracao'].notna().sum())}"
    if t == "SlotDecision" and "intakeInWindow" in df:
        extra = f"  resolved={int(df['intakeInWindow'].notna().sum())}  skips={int((df['actionRaw']=='skip').sum())}"
    print(f"{t:<18} rows={len(df):<6} users={users}{extra}")
PY
    ;;
  evaluate)
    (cd python && ../"$VENV"/bin/python evaluate.py --data ../data/export --hier) ;;
  prior)
    (cd python && ../"$VENV"/bin/python build_prior.py --data ../data/export --source "${2:-events}" --out ../out) ;;
  install)
    cp out/policy_params.json ../HidrataPOC/Policy/policy_params.json
    cp out/policy_parity_vectors.json ../HidrataPOCTests/Fixtures/policy_parity_vectors.json
    echo "copied. Rebuild the app and run ThompsonPolicyTests." ;;
  publish)
    : "${CK_KEY_ID:?set CK_KEY_ID}" "${CK_KEY_FILE:?set CK_KEY_FILE}"
    (cd python && ../"$VENV"/bin/python cloudkit_io.py publish --env "$ENVNAME" --params ../out/policy_params.json) ;;
  *)
    sed -n 2,13p "$SELF"; exit 1 ;;
esac
