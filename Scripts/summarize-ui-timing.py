import math
import re
import statistics
import sys
from pathlib import Path


def events(paths):
    result = set()
    for path in paths:
        for line in Path(path).read_text(errors="replace").splitlines():
            if "CF_UI_TIMELINE " not in line:
                continue
            fields = dict(re.findall(r"\b(id|pid|side|event|uptime)=([^\s]+)", line))
            if not {"id", "event", "uptime"} <= fields.keys():
                continue
            try:
                time = float(fields["uptime"])
            except ValueError:
                continue
            result.add((time, fields["id"].lower(), fields.get("side", "app"), fields["event"], fields.get("pid", "")))
    runner_ids = {test_id for _, test_id, side, _, _ in result if side == "runner"}
    return sorted(record for record in result if record[1] in runner_ids)


def durations(records, start_side, start_event, end_side, end_event):
    samples = []
    for index, start in enumerate(records):
        time, test_id, side, event, pid = start
        if (side, event) != (start_side, start_event):
            continue
        for end in records[index + 1:]:
            if end[1] != test_id:
                continue
            if (end[2], end[3]) == (start_side, start_event):
                break
            if (end[2], end[3]) == (end_side, end_event):
                if start_side == end_side == "app" and pid != end[4]:
                    continue
                samples.append(end[0] - time)
                break
    return samples


def main(paths):
    if not paths:
        raise SystemExit("usage: python3 Scripts/summarize-ui-timing.py <runner.log> <app-timeline.log> [...]")
    records = events(paths)
    intervals = [
        ("launch begin → process entry", "runner", "launch-begin", "app", "process-entry"),
        ("process entry → overlay committed", "app", "process-entry", "app", "overlay-committed"),
        ("overlay committed → session ready", "app", "overlay-committed", "app", "session-ready"),
        ("session ready → exposed root", "app", "session-ready", "app", "seeded-screen-visible"),
        ("launch begin → launch return", "runner", "launch-begin", "runner", "launch-return"),
        ("launch return → first element", "runner", "launch-return", "runner", "first-element-found"),
        ("reset begin → reset return", "runner", "reset-begin", "runner", "reset-return"),
        ("reset begin → first screen element", "runner", "reset-begin", "runner", "first-element-found"),
    ]
    print("| interval | samples | p50 seconds | p95 seconds |")
    print("| --- | ---: | ---: | ---: |")
    for label, *keys in intervals:
        samples = sorted(durations(records, *keys))
        if samples:
            p95 = samples[max(0, math.ceil(len(samples) * 0.95) - 1)]
            print(f"| {label} | {len(samples)} | {statistics.median(samples):.3f} | {p95:.3f} |")
        else:
            print(f"| {label} | 0 | pending | pending |")
    failures = sum(event == "reset-failed" or event == "seed-route-failed" for _, _, _, event, _ in records)
    print(f"\nTimeline events: {len(records)}; reset/seed failures: {failures}")


if __name__ == "__main__":
    main(sys.argv[1:])
