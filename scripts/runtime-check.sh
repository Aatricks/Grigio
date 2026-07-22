#!/bin/zsh

set -euo pipefail

duration="${1:-60}"
if ! [[ "$duration" =~ '^[0-9]+$' ]] || (( duration < 1 )); then
    print -u2 "usage: $0 [duration-seconds]"
    exit 2
fi

pid="$(pgrep -x grayscale-auto | head -n 1)"
if [[ -z "$pid" ]]; then
    print -u2 "grayscale-auto is not running"
    exit 1
fi

repo_root="${0:A:h:h}"
evidence_dir="$repo_root/build/evidence"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
sample_file="$evidence_dir/runtime-$timestamp.tsv"
log_file="$evidence_dir/transitions-$timestamp.log"
mkdir -p "$evidence_dir"

/usr/bin/log stream --style compact --predicate 'subsystem == "com.aatricks.grayscale-auto"' >"$log_file" 2>&1 &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true' EXIT INT TERM

print 'timestamp\tcpu_percent\trss_kib' >"$sample_file"
for (( second = 0; second < duration; second++ )); do
    if ! kill -0 "$pid" 2>/dev/null; then
        print -u2 "grayscale-auto exited during the run"
        exit 1
    fi
    read -r cpu rss <<<"$(ps -p "$pid" -o %cpu=,rss=)"
    print "$(date -u +%Y-%m-%dT%H:%M:%SZ)\t$cpu\t$rss" >>"$sample_file"
    sleep 1
done

kill "$log_pid" 2>/dev/null || true
wait "$log_pid" 2>/dev/null || true
trap - EXIT INT TERM

average_cpu="$(awk 'NR > 1 { sum += $2; count++ } END { if (count) printf "%.3f", sum / count; else print "n/a" }' "$sample_file")"
print "average CPU: $average_cpu%"
print "samples: $sample_file"
print "transitions: $log_file"
