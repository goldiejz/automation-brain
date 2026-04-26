#!/usr/bin/env bash
# ark-observer — continuous observation of base automation tooling
#
# Tails logs of ark itself (hooks, daemons, deliver runs) and pattern-matches
# in real time. When a known signature fires N times, escalates to lesson.
# When a NEW pattern emerges, captures it for human review.
#
# This is the meta-layer: the system watches itself improve.
#
# Usage:
#   ark observe              # foreground (Ctrl+C to stop)
#   ark observe --daemon     # background, writes PID file
#   ark observe --stop       # stop daemon
#   ark observe --status     # is it running?
#   ark observe --tail       # show recent observations
#   ark observe --analyze    # one-shot batch analysis (no daemon)

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
OBSERVER_DIR="$VAULT_PATH/observability/observer"
PID_FILE="$OBSERVER_DIR/observer.pid"
OBSERVATIONS_LOG="$OBSERVER_DIR/observations.jsonl"
PATTERNS_FILE="$OBSERVER_DIR/patterns.json"
LESSONS_OUT="$VAULT_PATH/lessons/auto-captured/observer-derived"

mkdir -p "$OBSERVER_DIR" "$LESSONS_OUT"

ACTION="${1:-foreground}"

# === Initialize patterns library if missing ===
init_patterns() {
  if [[ -f "$PATTERNS_FILE" ]]; then
    return
  fi
  cat > "$PATTERNS_FILE" <<'EOF'
{
  "patterns": [
    {
      "id": "quota-exhausted-codex",
      "regex": "(QUOTA_EXHAUSTED|hit your usage limit).*(codex|Codex)",
      "category": "infrastructure",
      "severity": "high",
      "lesson_after_n": 3,
      "auto_fix": "tier-down",
      "description": "Codex CLI hit quota — auto-degrade to next tier"
    },
    {
      "id": "quota-exhausted-gemini",
      "regex": "(TerminalQuotaError|hit your usage limit|capacity).*?(gemini|Gemini)",
      "category": "infrastructure",
      "severity": "high",
      "lesson_after_n": 3,
      "auto_fix": "tier-down",
      "description": "Gemini CLI hit quota — auto-degrade to next tier"
    },
    {
      "id": "dispatch-no-prompt",
      "regex": "No prompt provided via stdin",
      "category": "bug",
      "severity": "critical",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Dispatch failure — prompt not reaching CLI (stdin issue)"
    },
    {
      "id": "phase-no-tasks",
      "regex": "No tasks found in PLAN\\.md|no actionable tasks",
      "category": "workflow",
      "severity": "medium",
      "lesson_after_n": 2,
      "auto_fix": "log-only",
      "description": "Phase has no tasks — should auto-skip rather than fail"
    },
    {
      "id": "broken-symlink",
      "regex": "(BROKEN symlink|cannot find module)",
      "category": "infrastructure",
      "severity": "high",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Broken symlink or missing module — points to file ops issue"
    },
    {
      "id": "permission-denied",
      "regex": "Permission denied|EACCES",
      "category": "infrastructure",
      "severity": "high",
      "lesson_after_n": 2,
      "auto_fix": "log-only",
      "description": "Permission issues — likely chmod or sandbox-related"
    },
    {
      "id": "git-push-fail",
      "regex": "(push (declined|rejected)|non-fast-forward|GH013)",
      "category": "infrastructure",
      "severity": "medium",
      "lesson_after_n": 2,
      "auto_fix": "log-only",
      "description": "Git push failing — branch protection or stale local"
    },
    {
      "id": "ts-error",
      "regex": "TS[0-9]{4}: ",
      "category": "code-quality",
      "severity": "medium",
      "lesson_after_n": 5,
      "auto_fix": "log-only",
      "description": "Recurring TypeScript errors — may indicate template defect"
    },
    {
      "id": "false-positive-block",
      "regex": "(BLOCKED|REJECTED).*(error blob|never actually ran|dispatch error)",
      "category": "logic-bug",
      "severity": "critical",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "PM rejected work that wasn't reviewed — verdict logic gap"
    },
    {
      "id": "vault-stale",
      "regex": "snapshot is stale|sync needed|>7 days old",
      "category": "workflow",
      "severity": "low",
      "lesson_after_n": 5,
      "auto_fix": "auto-sync",
      "description": "Project snapshot stale — auto-sync trigger candidate"
    },
    {
      "id": "gsd-multi-plan-missed",
      "regex": "(0 tasks to execute|No tasks found).*phases/[0-9]",
      "category": "logic-bug",
      "severity": "critical",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Ark dispatched empty phase while GSD plan files exist — multi-plan blindness"
    },
    {
      "id": "gsd-phase-dir-collision",
      "regex": "phases/[0-9]+(\\.[0-9]+)?-NEW|sibling.*phase-",
      "category": "logic-bug",
      "severity": "high",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Ark created sibling/placeholder phase dir on a GSD project — shape detection regressed"
    },
    {
      "id": "empty-plan-dispatched",
      "regex": "team dispatch.*0 tasks|architect.*no plan",
      "category": "logic-bug",
      "severity": "high",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Team role dispatched with zero actionable tasks — caller skipped task validation"
    },
    {
      "id": "phase-dir-creation-without-tasks",
      "regex": "Created.*\\.planning/phases?/.*(NEW|placeholder)|wrote PLAN\\.md.*0 tasks",
      "category": "logic-bug",
      "severity": "high",
      "lesson_after_n": 1,
      "auto_fix": "log-only",
      "description": "Ark wrote a phase dir without finding/creating real tasks — bypass of plan validation"
    }
  ]
}
EOF
  echo "✅ Initialized patterns: $PATTERNS_FILE"
}

# === Logs to watch ===
get_log_paths() {
  # Returns list of log files to tail
  ls -1 \
    /tmp/ark-*.log \
    /tmp/brain-*.log \
    "$HOME/.claude/hooks/ark-hook-debug.log" \
    "$VAULT_PATH/logs/"*.log \
    "$HOME/code/"*"/.planning/delivery-logs/"*.log \
    2>/dev/null | sort -u
}

# === Match a line against patterns ===
match_patterns() {
  local line="$1"
  local source="$2"

  # Use env vars to avoid heredoc interpolation issues with f-strings
  export OBS_LINE="$line"
  export OBS_SOURCE="$source"
  export OBS_PATTERNS="$PATTERNS_FILE"
  export OBS_LOG="$OBSERVATIONS_LOG"

  python3 <<'PYEOF'
import json, re, datetime, os, sys

with open(os.environ['OBS_PATTERNS']) as f:
    patterns = json.load(f)["patterns"]

line = os.environ.get('OBS_LINE', '')
source = os.environ.get('OBS_SOURCE', 'unknown')

for p in patterns:
    if re.search(p["regex"], line, re.IGNORECASE):
        observation = {
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "pattern_id": p["id"],
            "category": p["category"],
            "severity": p["severity"],
            "source": source,
            "line": line[:300],
            "auto_fix": p["auto_fix"]
        }
        with open(os.environ['OBS_LOG'], "a") as f:
            f.write(json.dumps(observation) + "\n")
        sys.stderr.write(f"[{p['severity']}] {p['id']} from {source}\n")
        break
PYEOF
}

# === Aggregate occurrences and emit lessons when threshold reached ===
emit_lessons_if_threshold() {
  export OBS_LOG="$OBSERVATIONS_LOG"
  export OBS_PATTERNS="$PATTERNS_FILE"
  export OBS_LESSONS_DIR="$LESSONS_OUT"

  python3 <<'PYEOF'
import json, datetime, collections, os

obs_log = os.environ['OBS_LOG']
patterns_file = os.environ['OBS_PATTERNS']
lessons_dir = os.environ['OBS_LESSONS_DIR']

if not os.path.exists(obs_log):
    exit(0)

# Load observations
observations = []
with open(obs_log) as f:
    for line in f:
        try:
            observations.append(json.loads(line))
        except:
            pass

# Load patterns + their thresholds
with open(patterns_file) as f:
    patterns = {p["id"]: p for p in json.load(f)["patterns"]}

# Count occurrences per pattern
counts = collections.Counter(o["pattern_id"] for o in observations)

# Track which patterns we've already turned into lessons
already_lessoned = set()
os.makedirs(lessons_dir, exist_ok=True)
for fn in os.listdir(lessons_dir):
    if fn.endswith(".md"):
        pattern_id = fn.replace(".md", "")
        already_lessoned.add(pattern_id)

# For each pattern over threshold, write a lesson if not already done
new_lessons = 0
for pattern_id, count in counts.items():
    p = patterns.get(pattern_id, {})
    threshold = p.get("lesson_after_n", 3)
    if count >= threshold and pattern_id not in already_lessoned:
        recent = [o for o in observations if o["pattern_id"] == pattern_id][-5:]

        lesson_path = os.path.join(lessons_dir, pattern_id + ".md")
        with open(lesson_path, "w") as f:
            f.write("# Observer-Derived Lesson: " + pattern_id + "\n\n")
            f.write("**Source:** ark-observer (continuous monitoring)\n")
            f.write("**Captured:** " + datetime.datetime.utcnow().isoformat() + "Z\n")
            f.write("**Category:** " + p.get("category", "?") + "\n")
            f.write("**Severity:** " + p.get("severity", "?") + "\n")
            f.write("**Occurrences:** " + str(count) + " (threshold: " + str(threshold) + ")\n\n")
            f.write("## Pattern\n\n")
            f.write("`" + p.get("regex", "") + "`\n\n")
            f.write("## Description\n\n")
            f.write(p.get("description", "No description") + "\n\n")
            f.write("## Recent Occurrences\n\n")
            for o in recent:
                f.write("- **" + o["timestamp"] + "** in `" + o["source"] + "`:\n")
                f.write("  ```\n  " + o["line"] + "\n  ```\n")
            f.write("\n## Auto-Fix Suggestion\n\n")
            f.write("`" + p.get("auto_fix", "none") + "`\n")
            f.write("\n*Generated by ark-observer — review and codify into ark scripts if confirmed.*\n")

        print("Lesson emitted: " + pattern_id + " (" + str(count) + "x)")
        new_lessons += 1

if new_lessons > 0:
    print("\n" + str(new_lessons) + " new lesson(s) written to " + lessons_dir)
PYEOF
}

# === Continuous foreground watcher ===
run_foreground() {
  echo "🔭 Ark Observer — continuous monitoring"
  echo "   Vault:        $VAULT_PATH"
  echo "   Observations: $OBSERVATIONS_LOG"
  echo "   Lessons out:  $LESSONS_OUT"
  echo ""

  init_patterns

  local logs
  logs=$(get_log_paths)
  if [[ -z "$logs" ]]; then
    echo "ℹ️  No logs to watch yet — observer will pick them up as they appear"
    sleep 5
  fi

  echo "Watching:"
  echo "$logs" | sed 's/^/  - /'
  echo ""
  echo "Press Ctrl+C to stop"
  echo ""

  # tail -F follows multiple files even if they get rotated
  # shellcheck disable=SC2086
  tail -n 0 -F $logs 2>/dev/null | while IFS= read -r line; do
    # Strip the "==> filename <==" prefix that tail emits
    if [[ "$line" =~ ^\==\>\ (.*)\ \<==$ ]]; then
      current_source="${BASH_REMATCH[1]}"
      continue
    fi
    [[ -z "$line" ]] && continue
    match_patterns "$line" "${current_source:-unknown}"
  done

  # Periodically check thresholds (this loop exits on Ctrl+C)
  while true; do
    emit_lessons_if_threshold
    sleep 60
  done
}

# === Daemon mode ===
run_daemon() {
  if [[ -f "$PID_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
      echo "⚠️  Observer already running (PID $existing_pid)"
      exit 1
    else
      rm -f "$PID_FILE"
    fi
  fi

  init_patterns

  # Fork to background
  nohup bash "$0" foreground > "$OBSERVER_DIR/daemon.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  disown 2>/dev/null || true

  echo "✅ Observer daemon started (PID $pid)"
  echo "   Stop:    ark observe --stop"
  echo "   Status:  ark observe --status"
  echo "   Logs:    $OBSERVER_DIR/daemon.log"
}

stop_daemon() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "ℹ️  Observer not running"
    exit 0
  fi
  local pid
  pid=$(cat "$PID_FILE")
  if kill "$pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "✅ Observer stopped (was PID $pid)"
  else
    echo "⚠️  Process $pid not found"
    rm -f "$PID_FILE"
  fi
}

show_status() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "🔭 Observer RUNNING (PID $pid)"
      if [[ -f "$OBSERVATIONS_LOG" ]]; then
        local count
        count=$(wc -l < "$OBSERVATIONS_LOG" | tr -d ' ')
        echo "   Observations recorded: $count"
      fi
      if [[ -d "$LESSONS_OUT" ]]; then
        local lessons
        lessons=$(ls "$LESSONS_OUT"/*.md 2>/dev/null | wc -l | tr -d ' ')
        echo "   Lessons emitted:       $lessons"
      fi
      echo "   PID file: $PID_FILE"
      return
    else
      rm -f "$PID_FILE"
    fi
  fi
  echo "⚫ Observer NOT running"
  echo "   Start: ark observe --daemon"
}

show_tail() {
  if [[ ! -f "$OBSERVATIONS_LOG" ]]; then
    echo "ℹ️  No observations yet"
    exit 0
  fi
  echo "Recent observations:"
  tail -20 "$OBSERVATIONS_LOG" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        o = json.loads(line)
        print(f\"  {o['timestamp']}  [{o['severity']:8}]  {o['pattern_id']:30}  {o['source'][:40]}\")
    except: pass
"
}

run_analyze() {
  init_patterns
  echo "🔍 Batch analysis of all logs..."
  echo ""
  local logs
  logs=$(get_log_paths)
  for log in $logs; do
    [[ -f "$log" ]] || continue
    echo "  Scanning: $log"
    while IFS= read -r line; do
      match_patterns "$line" "$(basename "$log")"
    done < "$log"
  done
  echo ""
  emit_lessons_if_threshold
}

case "$ACTION" in
  foreground|"") run_foreground ;;
  --daemon|daemon) run_daemon ;;
  --stop|stop) stop_daemon ;;
  --status|status) show_status ;;
  --tail|tail) show_tail ;;
  --analyze|analyze) run_analyze ;;
  *) echo "Usage: ark observe [--daemon|--stop|--status|--tail|--analyze]"; exit 1 ;;
esac
