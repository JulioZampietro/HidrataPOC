#!/usr/bin/env python3
"""Counts the rows the app has stored locally in every iOS Simulator (read-only).

    python3 ml/check_local_data.py

Only covers Simulators on this Mac. Data from physical devices / TestFlight users lives
in CloudKit: use `ml/run_pipeline.sh export` for that.
"""
import sqlite3
import sys
from pathlib import Path

TABLES = ["ZUSERPROFILE", "ZNOTIFICATIONEVENT", "ZINTAKELOG", "ZSLOTDECISION", "ZUIINTERACTIONEVENT"]
ROOT = Path.home() / "Library/Developer/CoreSimulator/Devices"


def count(db: Path, table: str):
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            return con.execute(f"select count(*) from {table}").fetchone()[0]
        finally:
            con.close()
    except sqlite3.Error:
        return None


def main() -> int:
    stores = sorted(ROOT.glob("*/data/Containers/**/*.store"))
    stores = [s for s in stores if s.name == "default.store"]
    if not stores:
        print("no simulator stores found")
        return 1
    totals = dict.fromkeys(TABLES, 0)
    for db in stores:
        counts = {t: count(db, t) for t in TABLES}
        if all(v is None for v in counts.values()):
            continue
        print(f"\n{db.relative_to(ROOT)}")
        for t, n in counts.items():
            if n is not None:
                print(f"  {t[1:].title():<22}{n}")
                totals[t] += n
    print("\nTOTAL across simulators: " + ", ".join(f"{t[1:].title()}={n}" for t, n in totals.items()))
    print("A usable prior needs hundreds+ of resolved NotificationEvent rows across >= ~10 users.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
