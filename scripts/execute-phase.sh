#!/usr/bin/env bash
# execute-phase.sh — actually write code for a phase by dispatching to Codex per task
#
# Usage: execute-phase.sh <project_dir> <phase_num>
#
# What it does:
# 1. Parses .planning/phase-<N>/PLAN.md for task list
# 2. For each task:
#    a. Builds full context (CLAUDE.md, lessons, current state, task spec)
#    b. Dispatches to Codex with structured prompt
#    c. Applies Codex's output (writes/edits files)
#    d. Runs targeted verification (tsc, relevant tests)
#    e. If pass: commits atomically + moves to next
#    f. If fail: dispatches self-heal, retries once, then escalates
# 3. Logs all dispatches + outcomes to vault for learning

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

# === AOS policy lib + escalations (graceful degradation if missing) ===
if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-policy.sh"
fi
if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-escalations.sh"
fi

# Resolve phase dir respecting GSD layout (phases/NN-slug/) or legacy (phase-N/)
source "$VAULT_PATH/scripts/lib/gsd-shape.sh"
PHASE_DIR=$(gsd_resolve_phase_dir "$PHASE_NUM" "$PROJECT_DIR")
CONTEXT_FILE="$PHASE_DIR/.context-$$.md"
mkdir -p "$PHASE_DIR" 2>/dev/null

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[exec]${NC} $1"
}

ok() {
  echo -e "${GREEN}[exec]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[exec]${NC} $1"
}

err() {
  echo -e "${RED}[exec]${NC} $1"
}

# === Build context block for Codex ===
build_context() {
  local task_desc="$1"
  {
    echo "# Project Context"
    echo ""
    echo "**Project:** $(basename "$PROJECT_DIR")"
    echo "**Phase:** $PHASE_NUM"
    echo "**Task:** $task_desc"
    echo ""

    if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
      echo "## Repo Instructions (CLAUDE.md)"
      echo ""
      head -100 "$PROJECT_DIR/CLAUDE.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/.planning/PROJECT.md" ]]; then
      echo "## Project Definition"
      echo ""
      cat "$PROJECT_DIR/.planning/PROJECT.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      echo "## Current State"
      echo ""
      cat "$PROJECT_DIR/.planning/STATE.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/tasks/lessons.md" ]]; then
      echo "## Project Lessons (must apply)"
      echo ""
      cat "$PROJECT_DIR/tasks/lessons.md"
      echo ""
    fi

    # Include critical anti-patterns from brain
    if [[ -f "$VAULT_PATH/bootstrap/anti-patterns.md" ]]; then
      echo "## Universal Anti-Patterns (from brain)"
      echo ""
      head -60 "$VAULT_PATH/bootstrap/anti-patterns.md"
      echo ""
    fi

    # Show current file structure
    echo "## Current File Tree"
    echo "\`\`\`"
    cd "$PROJECT_DIR"
    find . -type f \
      -not -path './node_modules/*' \
      -not -path './.git/*' \
      -not -path './.parent-automation/brain-snapshot/*' \
      -not -path './.parent-automation/pre-align-backup-*/*' \
      | head -40
    echo "\`\`\`"
    echo ""

    # Show package.json for stack context
    if [[ -f "$PROJECT_DIR/package.json" ]]; then
      echo "## package.json"
      echo "\`\`\`json"
      cat "$PROJECT_DIR/package.json"
      echo "\`\`\`"
      echo ""
    fi
  } > "$CONTEXT_FILE"
}

# === Parse tasks from ALL plan files (GSD multi-plan or Ark single PLAN.md) ===
parse_tasks() {
  local plans
  plans=$(gsd_find_plan_files "$PHASE_DIR")
  if [[ -z "$plans" ]]; then
    err "No plan files found in $PHASE_DIR"
    return 1
  fi

  # Iterate plan files in sorted order; extract unchecked tasks from each.
  while IFS= read -r pf; do
    [[ -z "$pf" ]] && continue
    grep -E "^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\]" "$pf" 2>/dev/null | \
      sed -E 's/^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\][[:space:]]+//' || true
  done <<< "$plans"
}

# === Dispatch a single task to Codex ===
dispatch_task() {
  local task_desc="$1"
  local task_num="$2"

  log "━━━ Task $task_num: $task_desc ━━━"

  # Build context
  build_context "$task_desc"

  # Construct prompt for Codex
  local prompt="You are an autonomous code generation agent for this project.

$(cat "$CONTEXT_FILE")

## Your Task

$task_desc

## Output Format

Output a structured response with:

1. ANALYSIS: One paragraph explaining what files need to change and why
2. FILES: List of files you'll create or modify (relative paths)
3. CODE: For each file, provide the full new content in a code block tagged with the file path:

\`\`\`<filepath>
<full file content>
\`\`\`

4. TESTS: Briefly describe what to test
5. RISK: LOW/MEDIUM/HIGH and one sentence explaining

Constraints:
- Follow ALL conventions in CLAUDE.md (currency suffix, RBAC centralization, route/compute split, etc.)
- Apply lessons from tasks/lessons.md
- Avoid all anti-patterns listed
- Write idiomatic, production-quality code
- Include error handling and proper types
- If you need to add dependencies, list them but don't run npm install"

  # Helper: cross-platform timeout (macOS doesn't have 'timeout', uses 'gtimeout' from coreutils)
  local TIMEOUT_CMD=""
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 180"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 180"
  fi

  # === Pre-flight: check budget tier before dispatching ===
  local current_tier="GREEN"
  if [[ -f "$PROJECT_DIR/.planning/budget-tier.txt" ]]; then
    current_tier=$(cat "$PROJECT_DIR/.planning/budget-tier.txt")
    if [[ "$current_tier" == "BLACK" ]]; then
      # AOS: delegate to policy. AUTO_RESET → recompute and proceed; ESCALATE → fail fast (queued).
      if type policy_budget_decision >/dev/null 2>&1 && [[ -f "$PROJECT_DIR/.planning/budget.json" ]]; then
        local _bd
        _bd=$(BUDGET_FILE="$PROJECT_DIR/.planning/budget.json" python3 - <<'PY'
import json, os
b = json.load(open(os.environ['BUDGET_FILE']))
print(b.get('phase_used', 0), b.get('phase_cap_tokens', 50000), b.get('monthly_used', 0), b.get('monthly_cap_tokens', 1000000))
PY
)
        # shellcheck disable=SC2086
        local decision; decision=$(policy_budget_decision $_bd)
        case "$decision" in
          AUTO_RESET)
            log "Policy auto-reset on BLACK (monthly headroom available)"
            bash "$VAULT_PATH/scripts/ark-budget.sh" --reset >/dev/null 2>&1 || true
            current_tier=$(cat "$PROJECT_DIR/.planning/budget-tier.txt" 2>/dev/null || echo GREEN)
            ;;
          ESCALATE_MONTHLY_CAP)
            err "Monthly budget cap reached — escalation queued (no manual reset required)"
            return 1
            ;;
          PROCEED)
            log "Policy: PROCEED on BLACK (under monthly cap)"
            ;;
        esac
      else
        # Graceful degradation: no policy lib loaded — keep historic refusal but no interactive prompt.
        err "Budget BLACK — refusing to dispatch (policy lib not loaded; see ark budget)"
        return 1
      fi
    fi
    log "Current budget tier: $current_tier"
  fi

  # === Auto-detect runtime context: am I in Claude Code? ===
  local primary_dispatcher
  primary_dispatcher=$(bash "$VAULT_PATH/scripts/ark-context.sh" --primary 2>/dev/null || echo "regex-fallback")
  log "Auto-detected primary dispatcher: $primary_dispatcher"

  # If running inside Claude Code, the active session IS the engineer.
  # Don't waste cycles probing exhausted external CLIs — emit a structured
  # request that the calling Claude Code session can fulfill via Agent tool.
  if [[ "$primary_dispatcher" == "claude-code-session" ]]; then
    log "🤖 Active Claude Code session detected — handing task to session dispatcher"
    local session_handoff_file="$PHASE_DIR/task-$task_num-claude-handoff.md"
    cat > "$session_handoff_file" <<HANDOFF
# Task Handoff to Claude Code Session

**Project:** $(basename "$PROJECT_DIR")
**Phase:** $PHASE_NUM
**Task #$task_num:** $task_desc

## Context Files (read these)
- $PROJECT_DIR/CLAUDE.md
- $PROJECT_DIR/.planning/PROJECT.md
- $PROJECT_DIR/.planning/STATE.md
- $PROJECT_DIR/tasks/lessons.md (if exists)
- $PHASE_DIR/PLAN.md

## Required Action
The Claude Code session should now:
1. Read context files
2. Write the file(s) directly using Write/Edit tools
3. Run \`npm test\` and \`npx tsc --noEmit\` for verification
4. Commit atomically per task

## Why This Path
- Codex CLI: $(bash "$VAULT_PATH/scripts/ark-context.sh" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dispatchers']['codex']['status'])")
- Gemini CLI: $(bash "$VAULT_PATH/scripts/ark-context.sh" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dispatchers']['gemini']['status'])")
- Haiku API: $(bash "$VAULT_PATH/scripts/ark-context.sh" --json | python3 -c "import json,sys; d=json.load(sys.stdin); print('available' if d['dispatchers']['haiku-api']['available'] else 'no API key')")

The active session is the most reliable dispatcher right now.
HANDOFF
    log "Handoff written: $session_handoff_file"
    log "→ Claude Code session should now write files directly via Write tool"
    return 2  # Special exit code: 2 = handoff to session, not failure
  fi

  # Get recommended model for current tier (used when not in Claude Code)
  local recommended_model=""
  if cd "$PROJECT_DIR" 2>/dev/null; then
    recommended_model=$(bash "$VAULT_PATH/scripts/ark-budget.sh" --route engineering 2>/dev/null || echo "$primary_dispatcher")
  fi
  log "Tier-recommended model: $recommended_model"

  # Try Codex first — write prompt to temp file, pass as stdin via redirection
  local prompt_file="/tmp/brain-codex-prompt-$$.txt"
  echo "$prompt" > "$prompt_file"

  local output=""

  # Skip paid models if tier says fallback only
  if [[ "$recommended_model" == "regex-fallback" ]]; then
    log "RED tier: skipping AI dispatch, using cached templates only"
    output="[REGEX FALLBACK — cached pattern only, no AI dispatch]"
  elif command -v codex >/dev/null 2>&1; then
    log "Dispatching to Codex..."
    if [[ -n "$TIMEOUT_CMD" ]]; then
      output=$($TIMEOUT_CMD codex exec - < "$prompt_file" 2>&1 || echo "")
    else
      output=$(codex exec - < "$prompt_file" 2>&1 || echo "")
    fi

    # Estimate tokens used (rough: 4 chars/token)
    if [[ -n "$output" ]]; then
      local est_tokens=$(( ${#output} / 4 + ${#prompt} / 4 ))
      if cd "$PROJECT_DIR" 2>/dev/null; then
        bash "$VAULT_PATH/scripts/ark-budget.sh" --record "$est_tokens" "codex" 2>/dev/null | tail -1
      fi
    fi
  fi

  # Fall back to Gemini
  if [[ -z "$output" ]] || [[ "$output" == *"No prompt"* ]] || [[ "$output" == *"hit your usage limit"* ]] || [[ "$output" == *"quota"* ]]; then
    if command -v gemini >/dev/null 2>&1; then
      log "Codex unavailable, falling back to Gemini..."
      if [[ -n "$TIMEOUT_CMD" ]]; then
        output=$($TIMEOUT_CMD gemini -p - < "$prompt_file" 2>&1 || echo "")
      else
        output=$(gemini -p - < "$prompt_file" 2>&1 || echo "")
      fi
    fi
  fi

  # Clean up prompt file
  rm -f "$prompt_file"

  # Last resort: Haiku via API
  if [[ -z "$output" ]] || [[ "$output" == *"quota"* ]]; then
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
      log "Falling back to Haiku API..."
      output=$(curl -s -X POST https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        --data "$(python3 -c "
import json, sys
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 8000,
    'messages': [{'role': 'user', 'content': open('$CONTEXT_FILE').read() + '''

Task: $task_desc

Output structured: ANALYSIS, FILES, CODE blocks with file paths, TESTS, RISK.'''}]
}))")" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except: pass
")
    fi
  fi

  if [[ -z "$output" ]]; then
    err "All AI dispatchers unavailable for task: $task_desc"
    return 1
  fi

  # Save output for audit
  echo "$output" > "$PHASE_DIR/task-$task_num-output.md"

  # Apply the output
  apply_task_output "$output" "$task_num" "$task_desc"
  return $?
}

# === Apply Codex output: parse code blocks and write files (robust multi-format) ===
apply_task_output() {
  local output="$1"
  local task_num="$2"
  local task_desc="$3"

  log "Applying changes..."

  # Pass output via temp file to avoid shell escaping bugs
  local out_file="/tmp/brain-output-$$.txt"
  echo "$output" > "$out_file"

  # Robust Python parser handling 3 common AI output formats:
  # 1. ```<filepath>\n<content>\n```
  # 2. **File: `<filepath>`**\n```language\n<content>\n```
  # 3. ## <filepath>\n```\n<content>\n```
  export BRAIN_OUTPUT_FILE="$out_file"
  export BRAIN_PROJECT_DIR="$PROJECT_DIR"
  local applied_files=$(python3 <<'PYEOF'
import re
import os

with open(os.environ['BRAIN_OUTPUT_FILE'], 'r') as f:
    output = f.read()

project_dir = os.environ['BRAIN_PROJECT_DIR']
applied = []

# Common file extensions we expect
VALID_EXTS = {'.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs',
              '.java', '.kt', '.swift', '.rb', '.php', '.html',
              '.css', '.scss', '.json', '.yaml', '.yml', '.toml',
              '.md', '.sql', '.sh', '.txt', '.env'}

def is_valid_filepath(path):
    """Reject language tags, accept only paths that look like files"""
    if not path:
        return False
    if len(path) > 200:
        return False
    if '..' in path or path.startswith('/'):
        return False
    # Must have an extension OR a directory separator
    has_ext = any(path.endswith(ext) for ext in VALID_EXTS)
    has_dir = '/' in path
    if not (has_ext or has_dir):
        return False
    # Reject known language identifiers
    if path.lower() in {'typescript', 'javascript', 'python', 'go',
                         'rust', 'json', 'yaml', 'toml', 'bash', 'shell',
                         'sh', 'tsx', 'jsx', 'ts', 'js', 'py', 'rs',
                         'html', 'css', 'sql', 'diff', 'plain', 'text'}:
        return False
    return True

# Pattern 1: ```<path>\n<content>\n```
pattern1 = r'```([^\n`]+)\n(.*?)\n```'
for filepath, content in re.findall(pattern1, output, re.DOTALL):
    filepath = filepath.strip()
    if not is_valid_filepath(filepath):
        continue
    full_path = os.path.join(project_dir, filepath)
    dir_part = os.path.dirname(full_path)
    if dir_part:
        os.makedirs(dir_part, exist_ok=True)
    with open(full_path, 'w') as f:
        f.write(content)
    applied.append(filepath)

# Pattern 2: **File: `<path>`**\n```...\n<content>\n```
if not applied:
    pattern2 = r'(?:\*\*)?(?:File|Path):\s*`([^`\n]+)`(?:\*\*)?\s*\n```[a-z]*\n(.*?)\n```'
    for filepath, content in re.findall(pattern2, output, re.DOTALL | re.IGNORECASE):
        filepath = filepath.strip()
        if not is_valid_filepath(filepath):
            continue
        full_path = os.path.join(project_dir, filepath)
        dir_part = os.path.dirname(full_path)
        if dir_part:
            os.makedirs(dir_part, exist_ok=True)
        with open(full_path, 'w') as f:
            f.write(content)
        applied.append(filepath)

# Pattern 3: Header followed by code block
if not applied:
    pattern3 = r'(?:^|\n)#+\s*(?:\*\*)?([^\n*]+\.[a-z]+)(?:\*\*)?\s*\n+```[a-z]*\n(.*?)\n```'
    for filepath, content in re.findall(pattern3, output, re.DOTALL):
        filepath = filepath.strip()
        if not is_valid_filepath(filepath):
            continue
        full_path = os.path.join(project_dir, filepath)
        dir_part = os.path.dirname(full_path)
        if dir_part:
            os.makedirs(dir_part, exist_ok=True)
        with open(full_path, 'w') as f:
            f.write(content)
        applied.append(filepath)

for f in applied:
    print(f)
PYEOF
)
  rm -f "$out_file"

  if [[ -z "$applied_files" ]]; then
    warn "No file changes applied (AI may have output explanation only)"
    return 1
  fi

  ok "Applied $(echo "$applied_files" | wc -l | tr -d ' ') file(s):"
  echo "$applied_files" | sed 's/^/    /'

  # Run targeted verification
  cd "$PROJECT_DIR"

  # TypeScript check (compilation)
  if [[ -f "$PROJECT_DIR/tsconfig.json" ]]; then
    log "Running tsc check..."
    if ! npx tsc --noEmit 2>&1 | tail -5; then
      warn "tsc check has errors — task may need rework"
      return 1
    fi
  fi

  # Atomic commit per task
  log "Committing task $task_num..."
  git add -A 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Phase $PHASE_NUM Task $task_num: $task_desc

Auto-generated via ark deliver
Files changed: $(echo "$applied_files" | wc -l | tr -d ' ')

$(echo "$applied_files" | sed 's/^/  - /')" --quiet 2>/dev/null
    ok "Committed"
  else
    warn "No changes to commit (output may have been redundant)"
  fi

  return 0
}

# === Main ===
main() {
  if [[ ! -d "$PROJECT_DIR" ]]; then
    err "Project not found: $PROJECT_DIR"
    exit 1
  fi

  log "Executing Phase $PHASE_NUM tasks for $(basename "$PROJECT_DIR") (phase dir: $PHASE_DIR)"

  local tasks
  tasks=$(parse_tasks)

  if [[ -z "$tasks" ]]; then
    warn "No tasks found in PLAN.md"
    exit 0
  fi

  local task_num=0
  local failed=0
  echo "$tasks" | while IFS= read -r task; do
    [[ -z "$task" ]] && continue
    task_num=$((task_num + 1))

    if dispatch_task "$task" "$task_num"; then
      ok "Task $task_num complete"
    else
      err "Task $task_num failed"

      # Self-heal attempt
      log "Attempting self-heal..."
      bash "$VAULT_PATH/scripts/self-heal.sh" "$PHASE_DIR/task-$task_num-output.md" "task-$task_num-failure" 2>&1 | tail -5

      # Retry once
      log "Retrying task $task_num..."
      if dispatch_task "$task" "$task_num-retry"; then
        ok "Task $task_num passed on retry"
      else
        err "Task $task_num failed after retry — escalating"
        failed=1
      fi
    fi
  done

  # Cleanup context file
  rm -f "$CONTEXT_FILE"

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
