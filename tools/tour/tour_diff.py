"""Turn the replies of a tour run into state reads, and diff two runs.

tour_diff.py reads SCRIPT REPLIES OUT: writes the state reads of one run as JSON.
tour_diff.py diff REFERENCE RUN: prints each difference and exits 1 on any.
"""

import json
import sys
from pathlib import Path

VOLATILE = {
    line.strip()
    for line in (Path(__file__).parent / "volatile.txt").read_text().splitlines()
    if line.strip() and not line.startswith("#")
}
# Physics and float maths may move a value in its last digits between runs.
TOLERANCE = 0.01
# A walking actor moves about 1.2 units a frame, and the app runs a frame or two between
# worldReady and the tour's pause, so places match within 2 units.
KEY_TOLERANCE = {"position": 2.0, "distance": 2.0, "feet": 2.0}


def steps(script):
    lines = Path(script).read_text().splitlines()
    return [json.loads(line) for line in lines if line.strip() and not line.startswith("#")]


def replies(path):
    """The reply lines of `game run`, in order; events and the summary line are left out."""
    out = []
    for line in Path(path).read_text().splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and "ok" in value and "steps" not in value:
            out.append(value)
    return out


def stable(value):
    if isinstance(value, dict):
        return {key: stable(item) for key, item in value.items() if key not in VOLATILE}
    if isinstance(value, list):
        return [stable(item) for item in value]
    return value


def reads(script, reply_path, out):
    plan = steps(script)
    got = replies(reply_path)
    if len(got) != len(plan):
        sys.exit(f"[ERROR] {len(got)} replies for {len(plan)} steps; read {reply_path}")
    points = []
    for number, (step, reply) in enumerate(zip(plan, got, strict=True), start=1):
        if step["command"].startswith("state."):
            label = f"{number} {step['command']} {json.dumps(step.get('args', {}))}"
            points.append({"point": label, "result": stable(reply.get("result"))})
    Path(out).write_text(json.dumps(points, indent=2, sort_keys=True) + "\n")
    print(f"[ OK ] {len(points)} state reads -> {out}")


def differences(path, old, new, tolerance=TOLERANCE):
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(old.keys() | new.keys()):
            limit = KEY_TOLERANCE.get(key, TOLERANCE)
            yield from differences(f"{path}.{key}", old.get(key), new.get(key), limit)
    elif isinstance(old, list) and isinstance(new, list) and len(old) == len(new):
        for index, (a, b) in enumerate(zip(old, new, strict=True)):
            yield from differences(f"{path}[{index}]", a, b, tolerance)
    elif isinstance(old, bool) or isinstance(new, bool) or old is None or new is None:
        if old != new:
            yield f"{path}: {json.dumps(old)} -> {json.dumps(new)}"
    elif isinstance(old, int | float) and isinstance(new, int | float):
        if abs(old - new) > tolerance:
            yield f"{path}: {old} -> {new}"
    elif old != new:
        yield f"{path}: {json.dumps(old)} -> {json.dumps(new)}"


def diff(reference, run):
    old = json.loads(Path(reference).read_text())
    new = json.loads(Path(run).read_text())
    found = []
    for a, b in zip(old, new, strict=False):
        found += differences(a["point"], a["result"], b["result"])
    if len(old) != len(new):
        found.append(f"{len(old)} state reads in the reference, {len(new)} in this run")
    for line in found:
        print(f"[DIFF] {line}")
    if found:
        sys.exit(f"[ERROR] {len(found)} differences from {reference}")
    print(f"[ OK ] all {len(new)} state reads match {reference}")


if __name__ == "__main__":
    if sys.argv[1:2] == ["diff"]:
        diff(*sys.argv[2:4])
    else:
        reads(*sys.argv[1:4])
