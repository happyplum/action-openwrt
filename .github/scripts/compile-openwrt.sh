#!/usr/bin/env bash
set -euo pipefail

log=$(mktemp "$RUNNER_TEMP/openwrt-build.XXXXXX")
trap 'rm -f "$log"' EXIT

# V=s exposes OpenWrt's per-target wall times. Keep CI output small on success
# and show full compiler diagnostics on the existing single-thread retry.
if ! make -j"$1" V=s 2>&1 | tee "$log" | awk '/^time: / { print; fflush() }'; then
    tail -n 80 "$log"
    make -j1 V=sc 2>&1 | tee -a "$log"
fi

{
    echo '### 本次编译缓存'
    echo '```text'
    PATH="$PWD/staging_dir/host/bin:$PATH" ccache --show-log-stats
    du -sh "$CCACHE_DIR" dl
    echo '```'
    echo '### 最慢的编译目标（单位为秒，并行目标的耗时有重叠）'
    echo '```text'
    awk -F '#' '/^time: .*\/(host-)?compile#[0-9.]+#[0-9.]+#[0-9.]+$/ {
        printf "%9.2f  %s\n", $4, substr($1, 7)
    }' "$log" | sort -nr | sed -n '1,10p'
    echo '```'
} >> "$GITHUB_STEP_SUMMARY"
