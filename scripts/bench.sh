#!/bin/sh
# Loading benchmarks (SV-701): cold launch to first frame on a ~4 MB JPEG
# (SV-102 targets under 300 ms launch, under 100 ms first pixels) and
# next-image latency plus memory while browsing a folder. Appends one line
# to bench/RESULTS.md.
set -eu
APP=build/sView.app/Contents/MacOS/sView
DATA=build/bench
RUNS=${RUNS:-5}
if [ ! -f "$DATA/launch/large.jpg" ]; then
    xcrun swift scripts/make-bench-images.swift "$DATA" 100
fi

launch=""
for _ in $(seq "$RUNS"); do
    ms=$(SVIEW_BENCH=launch "$APP" "$PWD/$DATA/launch/large.jpg" 2>/dev/null | awk '/first-frame-ms/ {print $2}')
    launch="$launch $ms"
done
median=$(echo "$launch" | tr ' ' '\n' | grep . | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
browse=$(SVIEW_BENCH=browse "$APP" "$PWD/$DATA/browse/img-001.jpg" 2>/dev/null)
next=$(echo "$browse" | awk '/next-ms/ {print $3 " ms median, " $5 " ms p95"}')
resident=$(echo "$browse" | awk '/rss-mb/ {print $2}')
footprint=$(echo "$browse" | awk '/rss-mb/ {print $4}')
size=$(du -k "$DATA/launch/large.jpg" | awk '{print $1}')

line="- $(date +%Y-%m-%d) $(git rev-parse --short HEAD) $(sysctl -n hw.model): launch to first frame ${median} ms median of ${RUNS} (${size} KB JPEG, runs:${launch}); next image ${next} over 99 steps of 1920x1280 JPEGs; ${resident} MB resident, ${footprint} MB footprint after browsing (cache_mb 512)"
echo "$line"
if [ ! -f bench/RESULTS.md ]; then
    printf '# sView: benchmark results\n\nOne line per run of `make bench` on a commit that touches loading (SV-701). Targets (SV-102): first pixels under 100 ms for a 4 MB JPEG, cold launch under 300 ms.\n\n' > bench/RESULTS.md
fi
echo "$line" >> bench/RESULTS.md
