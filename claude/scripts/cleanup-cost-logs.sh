#!/bin/bash
# Delete cost-log files older than RETENTION_DAYS.
# Files are named YYYY-MM-DD.jsonl; we parse the date from the filename so
# cleanup is based on the log's own date, not filesystem mtime.
# Runs from a SessionStart hook. All failures are silenced so a cleanup
# problem can never block Claude Code from starting.

RETENTION_DAYS="${COST_LOG_RETENTION_DAYS:-30}"
log_dir="$HOME/.claude/cost-logs"

[ -d "$log_dir" ] || exit 0

# Cutoff = midnight UTC, RETENTION_DAYS ago, in seconds since epoch.
cutoff=$(date -u -v-"${RETENTION_DAYS}"d +%s 2>/dev/null) ||
    cutoff=$(date -u -d "${RETENTION_DAYS} days ago" +%s 2>/dev/null) ||
    exit 0

for f in "$log_dir"/*.jsonl; do
    [ -e "$f" ] || continue
    base=$(basename "$f" .jsonl)

    # Expect YYYY-MM-DD; skip anything that doesn't match.
    case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) continue ;;
    esac

    # Convert the filename date to epoch seconds (BSD then GNU date).
    file_epoch=$(date -u -j -f "%Y-%m-%d" "$base" +%s 2>/dev/null) ||
        file_epoch=$(date -u -d "$base" +%s 2>/dev/null) ||
        continue

    if [ "$file_epoch" -lt "$cutoff" ]; then
        rm -f "$f" 2>/dev/null
    fi
done

exit 0
