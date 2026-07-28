#!/bin/bash
# Seeds a booted simulator with an in-progress workout whose first exercise has
# no weight yet, so the weight-field UI test has a first-exposure row to check.
set -euo pipefail
C=$(xcrun simctl get_app_container booted rohansingh.Health-Tracker data)
D="$C/Library/Application Support/Today"
mkdir -p "$D"
python3 - "$D/private-data.json" <<'PY'
import json, sys, uuid, datetime
EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
ts = lambda dt: (dt - EPOCH).total_seconds()
now = datetime.datetime.now(datetime.timezone.utc)

def sets(weight, reps, n):
    return [{"id": str(uuid.uuid4()).upper(), "weight": weight, "reps": reps,
             "isComplete": False, "rir": 0} for _ in range(n)]

active = {
    "id": str(uuid.uuid4()).upper(),
    "kind": "upper",
    "startedAt": ts(now - datetime.timedelta(minutes=6)),
    "endedAt": None,
    "exercises": [
        # weight 0 == never loaded: the placeholder case
        {"id": str(uuid.uuid4()).upper(), "exerciseID": "machine-chest-fly", "sets": sets(0, 8, 2)},
        {"id": str(uuid.uuid4()).upper(), "exerciseID": "lat-pulldown", "sets": sets(205, 7, 2)},
    ],
}
weights = [{"id": str(uuid.uuid4()).upper(), "date": ts(now - datetime.timedelta(days=i)), "pounds": p}
           for i, p in enumerate([183.8, 184.2, 183.6])]
json.dump({"weights": weights, "workouts": [], "activeWorkout": active, "goalWeight": 175},
          open(sys.argv[1], "w"))
print("seeded", sys.argv[1])
PY
