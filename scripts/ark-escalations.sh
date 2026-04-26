#!/usr/bin/env bash
# ark-escalations.sh — Async escalation queue (writer + CLI lister)
#
# Phase 2 Plan 02-02 (REQ-AOS-03). Per CONTEXT.md decision #3:
# Phase 2 implements queue WRITE only. Consumption is Phase 7.
#
# Two modes:
#   1. Sourced: defines ark_escalate <class> <title> <body>
#   2. Invoked: --list (default) | --show <id> | --resolve <id> [note] | --all
#
# ESCALATIONS.md is created on first call (not at source time). Each escalation
# also writes a class:escalation audit-log line via _policy_log if ark-policy.sh
# is sourced (NEW-B-2: single writer, single schema).
#
# Section header (LOCKED format — Phase 7 parser depends on it):
#   ## ESC-YYYYMMDD-HHMMSS-<6char> — <class> — (open|resolved)
#
# The 4 escalation classes (CONTEXT.md):
#   monthly-budget | architectural-ambiguity | destructive-op | repeated-failure

# Detect sourced vs invoked. Bash 3 compatible.
_ARK_ESC_SOURCED=0
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  _ARK_ESC_SOURCED=1
fi

# Only enforce strict mode when invoked, not when sourced (caller may not want it).
if [[ "$_ARK_ESC_SOURCED" -eq 0 ]]; then
  set -uo pipefail
fi

_ark_esc_vault() {
  echo "${ARK_HOME:-$HOME/vaults/ark}"
}

_ark_esc_file() {
  echo "$(_ark_esc_vault)/ESCALATIONS.md"
}

# Valid escalation classes (CONTEXT.md). Bash 3: no associative arrays.
_ARK_ESC_VALID_CLASSES="monthly-budget architectural-ambiguity destructive-op repeated-failure"

_ark_esc_validate_class() {
  local class="$1"
  local c
  for c in $_ARK_ESC_VALID_CLASSES; do
    if [[ "$class" == "$c" ]]; then
      return 0
    fi
  done
  return 1
}

_ark_esc_gen_id() {
  local ts rand
  ts="$(date -u +%Y%m%d-%H%M%S)"
  # 6 chars [a-z0-9] from /dev/urandom; macOS-safe (no xxd).
  rand="$(head -c 16 /dev/urandom 2>/dev/null | base64 | tr -dc 'a-z0-9' | cut -c1-6)"
  if [[ -z "$rand" ]] || [[ "${#rand}" -ne 6 ]]; then
    # Fallback for hostile environments
    rand=$(printf '%04x%02x' "$RANDOM" "$((RANDOM % 256))" | cut -c1-6)
  fi
  echo "ESC-${ts}-${rand}"
}

_ark_esc_init_file() {
  local file
  file="$(_ark_esc_file)"
  if [[ -f "$file" ]]; then
    return 0
  fi
  local dir
  dir="$(dirname "$file")"
  mkdir -p "$dir" 2>/dev/null || return 1
  cat > "$file" <<'EOF'
# Ark Escalations Queue

> Async queue of true blockers. User reviews on session start or `ark escalations`.
> Phase 2 writer-only. Phase 7 will consume responses from this file.

EOF
}

# === Public: ark_escalate <class> <title> <body> ===
# Appends a section to ESCALATIONS.md. Idempotent: same class+title within 60s
# returns the existing id without appending. Returns the id on stdout.
ark_escalate() {
  local class="${1:-}"
  local title="${2:-}"
  local body="${3:-}"

  if [[ -z "$class" ]] || [[ -z "$title" ]]; then
    echo "ark_escalate: usage: ark_escalate <class> <title> <body>" >&2
    return 1
  fi

  if ! _ark_esc_validate_class "$class"; then
    echo "ark_escalate: invalid class '$class'. Must be one of: $_ARK_ESC_VALID_CLASSES" >&2
    return 1
  fi

  _ark_esc_init_file || {
    echo "ark_escalate: failed to initialize escalations file" >&2
    return 1
  }

  local file
  file="$(_ark_esc_file)"

  # === Idempotency check: same class+title within 60s = re-use existing id ===
  local existing_id
  existing_id="$(ARK_ESC_FILE="$file" ARK_ESC_CLASS="$class" ARK_ESC_TITLE="$title" python3 - <<'PY'
import os, re, sys
from datetime import datetime, timezone

path = os.environ['ARK_ESC_FILE']
want_class = os.environ['ARK_ESC_CLASS']
want_title = os.environ['ARK_ESC_TITLE']

try:
    with open(path) as f:
        text = f.read()
except FileNotFoundError:
    sys.exit(0)

header_re = re.compile(
    r'^## (ESC-\d{8}-\d{6}-[a-z0-9]{6}) — (\S+) — (open|resolved)\s*$',
    re.MULTILINE
)

now = datetime.now(timezone.utc)

# Iterate through sections; locate ones matching class + open + recent + same title
for m in header_re.finditer(text):
    esc_id, klass, status = m.group(1), m.group(2), m.group(3)
    if klass != want_class or status != 'open':
        continue
    # Section body: from end of header to next "\n---\n" or EOF
    start = m.end()
    end_marker = text.find('\n---\n', start)
    section = text[start:] if end_marker == -1 else text[start:end_marker]
    # Pull title line
    title_m = re.search(r'^\*\*Title:\*\*\s*(.*?)\s*$', section, re.MULTILINE)
    if not title_m or title_m.group(1) != want_title:
        continue
    # Pull created ts
    ts_m = re.search(r'^\*\*Created:\*\*\s*(\S+)\s*$', section, re.MULTILINE)
    if not ts_m:
        continue
    try:
        # Format: 2026-04-26T09:30:15Z
        created = datetime.strptime(ts_m.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        continue
    age = (now - created).total_seconds()
    if 0 <= age < 60:
        print(esc_id)
        sys.exit(0)
PY
)"

  if [[ -n "$existing_id" ]]; then
    echo "$existing_id"
    return 0
  fi

  # === Append new section ===
  local id ts
  id="$(_ark_esc_gen_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '## %s — %s — open\n' "$id" "$class"
    printf '**Created:** %s\n' "$ts"
    printf '**Class:** %s\n' "$class"
    printf '**Title:** %s\n' "$title"
    printf '\n%s\n' "$body"
    printf '\n---\n\n'
  } >> "$file"

  # === Audit log via _policy_log (NEW-B-2: single writer) ===
  if declare -f _policy_log >/dev/null 2>&1; then
    local context_json
    # Escape title/class for JSON; keep it simple (no embedded quotes in titles expected,
    # but be defensive)
    context_json="$(ARK_ESC_ID="$id" ARK_ESC_TITLE="$title" python3 -c '
import os, json
print(json.dumps({"escalation_id": os.environ["ARK_ESC_ID"], "title": os.environ["ARK_ESC_TITLE"]}))
' 2>/dev/null)"
    if [[ -z "$context_json" ]]; then
      context_json="null"
    fi
    _policy_log "escalation" "QUEUED" "$class" "$context_json" >/dev/null 2>&1 || true
  fi

  echo "$id"
}

# === CLI: --list ===
_ark_esc_cmd_list() {
  local include_resolved="${1:-false}"
  local file
  file="$(_ark_esc_file)"
  if [[ ! -f "$file" ]]; then
    echo "No escalations queue yet. (File: $file)"
    return 0
  fi

  ARK_ESC_FILE="$file" ARK_ESC_INCLUDE_RESOLVED="$include_resolved" python3 - <<'PY'
import os, re
from datetime import datetime, timezone

path = os.environ['ARK_ESC_FILE']
include_resolved = os.environ['ARK_ESC_INCLUDE_RESOLVED'] == 'true'

with open(path) as f:
    text = f.read()

header_re = re.compile(
    r'^## (ESC-\d{8}-\d{6}-[a-z0-9]{6}) — (\S+) — (open|resolved)\s*$',
    re.MULTILINE
)

now = datetime.now(timezone.utc)
rows = []

matches = list(header_re.finditer(text))
for i, m in enumerate(matches):
    esc_id, klass, status = m.group(1), m.group(2), m.group(3)
    if status == 'resolved' and not include_resolved:
        continue
    start = m.end()
    end = matches[i+1].start() if i+1 < len(matches) else len(text)
    section = text[start:end]
    title_m = re.search(r'^\*\*Title:\*\*\s*(.*?)\s*$', section, re.MULTILINE)
    ts_m = re.search(r'^\*\*Created:\*\*\s*(\S+)\s*$', section, re.MULTILINE)
    title = title_m.group(1) if title_m else ''
    age = ''
    if ts_m:
        try:
            created = datetime.strptime(ts_m.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
            secs = int((now - created).total_seconds())
            if secs < 60:
                age = f'{secs}s'
            elif secs < 3600:
                age = f'{secs//60}m'
            elif secs < 86400:
                age = f'{secs//3600}h'
            else:
                age = f'{secs//86400}d'
        except ValueError:
            age = '?'
    rows.append((esc_id, klass, status, age, title))

# Newest-first by id (id encodes ts)
rows.sort(key=lambda r: r[0], reverse=True)

if not rows:
    if include_resolved:
        print('No escalations.')
    else:
        print('No open escalations.')
else:
    # Tabular
    print(f'{"ID":<28} {"CLASS":<24} {"STATUS":<9} {"AGE":<6} TITLE')
    for esc_id, klass, status, age, title in rows:
        # Truncate title for display
        tdisp = title if len(title) <= 60 else title[:57] + '...'
        print(f'{esc_id:<28} {klass:<24} {status:<9} {age:<6} {tdisp}')
PY
}

# === CLI: --show <id> ===
_ark_esc_cmd_show() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    echo "ark-escalations: --show requires <id>" >&2
    return 1
  fi
  local file
  file="$(_ark_esc_file)"
  if [[ ! -f "$file" ]]; then
    echo "No escalations queue exists." >&2
    return 1
  fi

  ARK_ESC_FILE="$file" ARK_ESC_ID="$id" python3 - <<'PY'
import os, re, sys

path = os.environ['ARK_ESC_FILE']
want_id = os.environ['ARK_ESC_ID']

with open(path) as f:
    text = f.read()

header_re = re.compile(
    r'^## (ESC-\d{8}-\d{6}-[a-z0-9]{6}) — (\S+) — (open|resolved)\s*$',
    re.MULTILINE
)

matches = list(header_re.finditer(text))
for i, m in enumerate(matches):
    if m.group(1) != want_id:
        continue
    start = m.start()
    end = matches[i+1].start() if i+1 < len(matches) else len(text)
    sys.stdout.write(text[start:end].rstrip() + '\n')
    sys.exit(0)
sys.stderr.write(f'Escalation not found: {want_id}\n')
sys.exit(1)
PY
}

# === CLI: --resolve <id> [note] ===
_ark_esc_cmd_resolve() {
  local id="${1:-}"
  local note="${2:-}"
  if [[ -z "$id" ]]; then
    echo "ark-escalations: --resolve requires <id>" >&2
    return 1
  fi
  local file
  file="$(_ark_esc_file)"
  if [[ ! -f "$file" ]]; then
    echo "No escalations queue exists." >&2
    return 1
  fi

  ARK_ESC_FILE="$file" ARK_ESC_ID="$id" ARK_ESC_NOTE="$note" python3 - <<'PY'
import os, re, sys
from datetime import datetime, timezone

path = os.environ['ARK_ESC_FILE']
want_id = os.environ['ARK_ESC_ID']
note = os.environ['ARK_ESC_NOTE']

with open(path) as f:
    text = f.read()

header_re = re.compile(
    r'^## (ESC-\d{8}-\d{6}-[a-z0-9]{6}) — (\S+) — (open|resolved)\s*$',
    re.MULTILINE
)

matches = list(header_re.finditer(text))
target_idx = None
for i, m in enumerate(matches):
    if m.group(1) == want_id:
        target_idx = i
        break

if target_idx is None:
    sys.stderr.write(f'Escalation not found: {want_id}\n')
    sys.exit(1)

m = matches[target_idx]
status = m.group(3)
if status == 'resolved':
    sys.stderr.write(f'Escalation {want_id} already resolved.\n')
    sys.exit(1)

# Rewrite header line: open -> resolved
new_header = f'## {m.group(1)} — {m.group(2)} — resolved'
old_header = m.group(0)

# Find section end so we can append resolution metadata before the next section
section_end = matches[target_idx+1].start() if target_idx+1 < len(matches) else len(text)
section = text[m.end():section_end]

# Append resolution metadata. Convention: just before any trailing "\n---\n" if present.
ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
resolution_block = f'\n**Resolved:** {ts}\n'
if note:
    resolution_block += f'**Resolution note:** {note}\n'

# Strip the trailing "---\n\n" if present, append resolution, re-add "---\n\n"
sep = '\n---\n'
if section.endswith(sep + '\n'):
    body = section[:-len(sep + '\n')]
    new_section = body.rstrip() + resolution_block + sep + '\n'
elif section.rstrip().endswith('---'):
    # Some other trailing whitespace shape
    body = section.rstrip()[:-3].rstrip()
    new_section = body + resolution_block + '\n---\n\n'
else:
    new_section = section.rstrip() + resolution_block + '\n---\n\n'

new_text = text[:m.start()] + new_header + new_section + text[section_end:]

with open(path, 'w') as f:
    f.write(new_text)

print(f'Resolved {want_id}')
PY
}

_ark_esc_usage() {
  cat <<EOF
Usage: ark-escalations.sh [OPTIONS]

  --list              List open escalations (default)
  --all               List open and resolved
  --show <id>         Show full body of escalation
  --resolve <id> [note]  Mark escalation resolved, with optional note
  --help              Show this help

Sourced API:
  ark_escalate <class> <title> <body>
    classes: $_ARK_ESC_VALID_CLASSES
EOF
}

# === Direct invocation dispatcher ===
if [[ "$_ARK_ESC_SOURCED" -eq 0 ]]; then
  case "${1:-}" in
    ""|--list)
      _ark_esc_cmd_list false
      ;;
    --all)
      _ark_esc_cmd_list true
      ;;
    --show)
      shift
      _ark_esc_cmd_show "$@"
      ;;
    --resolve)
      shift
      _ark_esc_cmd_resolve "$@"
      ;;
    -h|--help|help)
      _ark_esc_usage
      ;;
    *)
      echo "ark-escalations: unknown option '$1'" >&2
      _ark_esc_usage >&2
      exit 1
      ;;
  esac
fi
