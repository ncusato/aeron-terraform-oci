#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <client-results-tar.gz> [more-client-results-tar.gz ...]" >&2
  exit 1
fi

python3 - "$@" <<'PY'
import pathlib
import re
import statistics
import subprocess
import sys
import tarfile
import tempfile

# Prefer local aggregate-results in current scripts dir, fallback to known paths.
cwd = pathlib.Path.cwd()
candidates = [
    cwd / "aggregate-results",
    pathlib.Path("/opt/aeron/benchmarks-dist/scripts/aggregate-results"),
    pathlib.Path("/home/ubuntu/benchmarks/scripts/aggregate-results"),
]
agg = next((p for p in candidates if p.exists()), None)
if agg is None:
    print("ERROR: aggregate-results executable not found", file=sys.stderr)
    sys.exit(1)

def extract_metrics(report_path: pathlib.Path):
    p50 = p99 = p999 = maxv = None
    for line in report_path.read_text(errors="ignore").splitlines():
        s = line.strip()
        if s.startswith("#[Max"):
            m = re.search(r"Max\s*=\s*([0-9.]+)", s)
            if m:
                maxv = float(m.group(1))
        elif s and (s[0].isdigit() or s[0] == "."):
            parts = s.split()
            if len(parts) < 2:
                continue
            val = float(parts[0])
            pct = parts[1]
            if pct == "0.500000000000":
                p50 = val
            elif pct == "0.990625000000":
                p99 = val
            elif pct == "0.999023437500":
                p999 = val
    return p50, p99, p999, maxv

print("archive,scenario,valid_runs,median_p50_us,median_p99_us,median_p999_us,median_max_us")
for arg in sys.argv[1:]:
    tar_path = pathlib.Path(arg).expanduser().resolve()
    if not tar_path.exists():
        print(f"{tar_path.name},ERROR:not-found,0,,,,")
        continue

    with tempfile.TemporaryDirectory(prefix="aeron-compare-") as td:
        td_path = pathlib.Path(td)
        with tarfile.open(tar_path, "r:gz") as t:
            t.extractall(td_path)

        scenario_dirs = [
            p for p in td_path.iterdir()
            if p.is_dir() and (p.name.startswith("java-vs-") or p.name.startswith("c-vs-"))
        ]
        if not scenario_dirs:
            # Fallback for nested extraction layouts.
            scenario_dirs = [p for p in td_path.rglob("*_length=*_*") if p.is_dir()]

        for scenario in sorted(set(scenario_dirs)):
            metrics = []
            for run_dir in sorted(scenario.glob("run-*")):
                if not any(x.suffix == ".hdr" for x in run_dir.iterdir() if x.is_file()):
                    continue
                subprocess.run([str(agg), str(run_dir)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                reports = list(run_dir.glob("*-report.hgrm"))
                if not reports:
                    continue
                p50, p99, p999, maxv = extract_metrics(reports[0])
                if None not in (p50, p99, p999, maxv):
                    metrics.append((p50, p99, p999, maxv))

            if not metrics:
                print(f"{tar_path.name},{scenario.name},0,,,,")
                continue

            print(
                f"{tar_path.name},{scenario.name},{len(metrics)},"
                f"{statistics.median([m[0] for m in metrics]):.3f},"
                f"{statistics.median([m[1] for m in metrics]):.3f},"
                f"{statistics.median([m[2] for m in metrics]):.3f},"
                f"{statistics.median([m[3] for m in metrics]):.3f}"
            )
PY
