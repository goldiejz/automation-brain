#!/usr/bin/env bash
# Ark SessionEnd/Stop hook — trigger Phase 6 observability after session work
#
# Behavior:
# - If CWD has .parent-automation/ AND new decisions were logged this session,
#   trigger Phase 6 daemon detached so brain learns from this session
# - Silent if no decisions logged or no brain integration
#
# This closes the self-improving loop automatically every session.

set -euo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="$(pwd)"

# Skip if vault doesn't exist
[[ ! -d "$VAULT_PATH" ]] && exit 0

# Skip if we're inside the vault itself
[[ "$PROJECT_DIR" == "$VAULT_PATH"* ]] && exit 0

# Skip if no brain integration
[[ ! -d "$PROJECT_DIR/.parent-automation" ]] && exit 0

# Skip if no decision log (nothing to process)
DECISION_LOG="$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"
[[ ! -f "$DECISION_LOG" ]] && exit 0

# Skip if decision log is empty
[[ ! -s "$DECISION_LOG" ]] && exit 0

# Trigger Phase 6 daemon detached (non-blocking, runs in background)
DAEMON_PATH="$VAULT_PATH/observability/phase-6-daemon.ts"
if [[ -f "$DAEMON_PATH" ]]; then
  (
    cd "$VAULT_PATH"
    nohup npx ts-node "$DAEMON_PATH" > /tmp/brain-phase6-$$.log 2>&1 &
  ) 2>/dev/null

  # Brief notification to Claude context
  DECISIONS=$(wc -l < "$DECISION_LOG" | tr -d ' ')
  cat <<EOF
=== BRAIN: PHASE 6 TRIGGERED ===
Session ending — observability daemon dispatched.
Decisions in log: $DECISIONS
Phase 6 will: detect patterns, update lesson effectiveness, refresh cache.
Output: ~/vaults/ark/observability/
================================
EOF
fi

exit 0
