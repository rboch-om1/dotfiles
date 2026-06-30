#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract current directory from JSON input
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
in_worktree=$(echo "$input" | jq -r '.workspace.git_worktree // false')

# Extract context usage (full window, e.g. 1M for opus-4-7[1m])
percent=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Extract model name and version
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cc_version=$(echo "$input" | jq -r '.version // ""')

# Extract session cost
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Live-context token totals — used only to compute the 200K-budget bar.
live_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
live_output=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
live_total=$((live_input + live_output + cache_read + cache_create))
exceeds_200k=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')

# 5-hour rate limit (Pro/Max only; absent → 0)
rate_5h_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
rate_5h_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0' | cut -d. -f1)

# Persistent log: append authoritative session cost + 5h rate-limit usage on every fire.
# Lets cost-analyzer answer "when did the cap step down" without re-deriving from JSONL.
# Failures are silenced — never let a logging issue break the status bar.
{
    cost_log_dir="$HOME/.claude/cost-logs"
    [ -d "$cost_log_dir" ] || mkdir -p "$cost_log_dir"
    echo "$input" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
        ts: $ts,
        session_id: .session_id,
        cwd: .workspace.current_dir,
        model: .model.id,
        cost_usd: .cost.total_cost_usd,
        rate_5h_used_pct: .rate_limits.five_hour.used_percentage,
        rate_5h_resets_at: .rate_limits.five_hour.resets_at
    }' >> "$cost_log_dir/$(date -u +%Y-%m-%d).jsonl"
} 2>/dev/null || true

# Helpers: build a colored bar of given width
make_bar() {
    local pct=$1
    local width=$2
    local color=$3
    local filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$((width - filled))
    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    printf "%b%s\033[0m" "$color" "$bar"
}

# 1M bar color: green < 40%, yellow 40-75%, red >= 75%
if [ "$percent" -ge 75 ]; then
    bar1m_color="\033[0;31m"
elif [ "$percent" -ge 40 ]; then
    bar1m_color="\033[0;33m"
else
    bar1m_color="\033[0;32m"
fi
bar1m=$(make_bar "$percent" 10 "$bar1m_color")

# 200K bar: percentage of the 200K compaction-relevant budget
pct_200k=$((live_total * 100 / 200000))
[ "$pct_200k" -gt 999 ] && pct_200k=999
# Yellow at >=80% (160K), red when CC's exceeds_200k_tokens fires
if [ "$exceeds_200k" = "true" ]; then
    bar200_color="\033[0;31m"
    warn_glyph=" \033[0;31m⚠\033[0m"
elif [ "$pct_200k" -ge 80 ]; then
    bar200_color="\033[0;33m"
    warn_glyph=""
else
    bar200_color="\033[0;32m"
    warn_glyph=""
fi
bar200=$(make_bar "$pct_200k" 5 "$bar200_color")

# Combined context meter: 1M bar + 200K bar
context_meter=$(printf "1M:[%b] %3d%% \xC2\xB7 200K:[%b] %3d%%%b" "$bar1m" "$percent" "$bar200" "$pct_200k" "$warn_glyph")

# Get current directory basename
dir_name=$(basename "$cwd")

# Check if in a git repository
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    # Get current branch name
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Worktree marker (from CC JSON; falls back silently if absent)
    wt_marker=""
    [ "$in_worktree" = "true" ] && wt_marker=" \033[0;35m+wt\033[0m"

    # Check if working directory is dirty
    if git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null && git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
        git_info=$(printf "\033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m%b" "$branch" "$wt_marker")
    else
        git_info=$(printf "\033[1;34mgit:(\033[0;31m%s\033[1;34m) \033[0;33m✗\033[0m%b" "$branch" "$wt_marker")
    fi
else
    git_info=""
fi

# Format model name and version (dim/gray)
model_display=$(printf "\033[0;90m%s    ccver: %s\033[0m" "$model_name" "$cc_version")

# Rate-limit indicator: show REMAINING (more actionable) + countdown to reset.
# Color thresholds based on remaining: <=20% red, <=50% yellow, else light gray.
rate_display=""
if [ "$rate_5h_used" -gt 0 ] 2>/dev/null; then
    rate_5h_left=$((100 - rate_5h_used))
    if [ "$rate_5h_left" -le 20 ]; then
        rate_color="\033[0;31m"
    elif [ "$rate_5h_left" -le 50 ]; then
        rate_color="\033[0;33m"
    else
        rate_color="\033[0;37m"  # light gray (more visible than \033[0;90m)
    fi
    # Time-to-reset (h:mm), only if resets_at is in the future
    rate_eta=""
    if [ "$rate_5h_resets" -gt 0 ] 2>/dev/null; then
        now=$(date +%s)
        secs_left=$((rate_5h_resets - now))
        if [ "$secs_left" -gt 0 ]; then
            h=$((secs_left / 3600))
            m=$(((secs_left % 3600) / 60))
            rate_eta=$(printf " %dh%02dm" "$h" "$m")
        fi
    fi
    rate_display=$(printf "%b5h:%d%% left%s\033[0m " "$rate_color" "$rate_5h_left" "$rate_eta")
fi

# Format: rate-limit (if any) then cumulative session cost
cost_display=$(printf "%b\033[0;33m\$%.2f\033[0m" "$rate_display" "$session_cost")

# Build left side: arrow + directory + git info + context meter + cost
left_side=$(printf "\033[1;32m➜\033[0m  \033[0;36m%s\033[0m %s     %b        %b" "$dir_name" "$git_info" "$context_meter" "$cost_display")

# Output with model name right-justified using wide spacing
printf "%b%*s%b" "$left_side" 10 "" "$model_display"