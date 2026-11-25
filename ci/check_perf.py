import json
import sys

report = json.load(open(sys.argv[1]))
mib = 1024 * 1024
first = float(report["firstLaunchSeconds"])
median = float(report["coldLaunchMedianSeconds"])
samples = report["launchSamples"]
print("launch first", first, "median", median, "samples", samples)
if len(samples) != 6 or first <= 0.05 or median <= 0.05 or any(sample <= 0.05 for sample in samples):
    raise SystemExit(f"launch samples are not real timings: {samples}")
final = int(report["finalRSS"])
base = int(report["afterTabsRSS"])
gap = float(report["maxMainThreadGapSeconds"])
print("rss final", round(final / mib, 1), "after tabs", round(base / mib, 1), "gap", gap)
if final >= 200 * mib:
    raise SystemExit(f"final RSS {final} is not under 200 MiB")
if final > base + 30 * mib:
    raise SystemExit(f"final RSS {final} is more than 30 MiB above the post-tabs {base}")
if gap <= 0.001 or gap >= 0.1:
    raise SystemExit(f"main-thread gap {gap} is not a real value under 100 ms")
tools = report["tools"]
slowest = report["slowest"]
if len(tools) < 90 or len(slowest) != 10:
    raise SystemExit(f"expected every tool time and 10 slowest, got {len(tools)} and {len(slowest)}")
print("slowest")
for row in slowest:
    print(f"{row['seconds']:.3f} {row['tool']}")
