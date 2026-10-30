# sView: benchmark results

One line per run of `make bench` on a commit that touches loading (SV-701). Targets (SV-102): first pixels under 100 ms for a 4 MB JPEG, cold launch under 300 ms.

- 2026-10-25 0ddae4b Mac16,8: launch to first frame 289.6 ms median of 5 (5504 KB JPEG, runs: 836.7 278.7 308.8 287.6 289.6); next image 12.9 ms median, 21.0 ms p95 over 99 steps of 1920x1280 JPEGs; 791 MB footprint after browsing (cache_mb 512)
- 2026-10-25 07a5ae8 Mac16,8: launch to first frame 208.5 ms median of 5 (5504 KB JPEG, runs: 202.6 205.1 208.9 209.0 208.5); next image 16.3 ms median, 17.4 ms p95 over 99 steps of 1920x1280 JPEGs; 382 MB resident, 25 MB footprint after browsing (cache_mb 512)
