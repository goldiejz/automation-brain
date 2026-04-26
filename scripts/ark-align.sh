#!/usr/bin/env bash
# ark align — standardize imported/existing project to canonical structure
#
# Usage:
#   ark-align.sh                    # Align current directory
#   ark-align.sh /path/to/project   # Align specific project
#   ark-align.sh --dry-run          # Show what would change
#
# What it does:
# 1. Detects existing planning artifacts (lessons.md, STATE.md, etc.)
# 2. Backs up everything before changes
# 3. Standardizes filenames per STRUCTURE.md
# 4. Migrates lessons to vault by-customer/
# 5. Backfills missing canonical files from templates
# 6. Validates conventions, reports deviations
# 7. Logs alignment decision for Phase 6

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="${1:-$(pwd)}"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  PROJECT_DIR="${2:-$(pwd)}"
fi

# Resolve to absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
  echo "❌ Project not found: $PROJECT_DIR"
  exit 1
}

echo "🧠 Ark Align: $PROJECT_DIR"
echo "Mode: $($DRY_RUN && echo 'DRY RUN' || echo 'APPLY')"
echo ""

CHANGES=()
WARNINGS=()

# Detect customer from path or package.json
CUSTOMER="unknown"
if [[ -f "$PROJECT_DIR/package.json" ]]; then
  PKG_NAME=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR/package.json" | head -1 | sed 's/.*"\(.*\)"/\1/')
  if [[ "$PKG_NAME" == strategix-* ]]; then
    CUSTOMER="strategix"
  elif [[ -n "$PKG_NAME" ]]; then
    CUSTOMER=$(echo "$PKG_NAME" | sed 's/-.*//')
  fi
fi

# Detect project type
PROJECT_TYPE="custom"
if grep -qi "service-desk\|servicedesk" "$PROJECT_DIR/package.json" 2>/dev/null; then
  PROJECT_TYPE="service-desk"
elif grep -qi "revops\|crm" "$PROJECT_DIR/package.json" 2>/dev/null; then
  PROJECT_TYPE="revops"
elif grep -qi "ops-intel\|ioc" "$PROJECT_DIR/package.json" 2>/dev/null; then
  PROJECT_TYPE="ops-intelligence"
fi

echo "Detected: customer=$CUSTOMER, type=$PROJECT_TYPE"
echo ""

# === Step 1: Backup ===
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
BACKUP_DIR="$PROJECT_DIR/.parent-automation/pre-align-backup-$TIMESTAMP"

if [[ "$DRY_RUN" == "false" ]]; then
  mkdir -p "$BACKUP_DIR"
  for d in .planning tasks .claude; do
    if [[ -d "$PROJECT_DIR/$d" ]]; then
      cp -r "$PROJECT_DIR/$d" "$BACKUP_DIR/" 2>/dev/null
    fi
  done
  for f in CLAUDE.md README.md; do
    if [[ -f "$PROJECT_DIR/$f" ]]; then
      cp "$PROJECT_DIR/$f" "$BACKUP_DIR/" 2>/dev/null
    fi
  done
  echo "✅ Backup created: $BACKUP_DIR"
fi

# === Step 2: Standardize filenames ===
echo ""
echo "━━━ Standardizing filenames ━━━"

# Parallel arrays for bash 3 compatibility (macOS default)
RENAME_PAIRS=(
  "LEARNINGS.md:tasks/lessons.md"
  "LESSONS.md:tasks/lessons.md"
  "TODO.md:tasks/todo.md"
  "DECISIONS.md:.planning/STATE.md"
  "PLANNING.md:.planning/PROJECT.md"
  "ROADMAP.md:.planning/ROADMAP.md"
)

for pair in "${RENAME_PAIRS[@]}"; do
  src="${pair%%:*}"
  dst="${pair#*:}"
  if [[ -f "$PROJECT_DIR/$src" ]]; then
    if [[ -f "$PROJECT_DIR/$dst" ]]; then
      WARNINGS+=("Both $src and $dst exist — manual merge needed")
    else
      CHANGES+=("Renamed: $src → $dst")
      if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$PROJECT_DIR/$(dirname "$dst")"
        mv "$PROJECT_DIR/$src" "$PROJECT_DIR/$dst"
      fi
    fi
  fi
done

# === Step 2b: Discover and categorize ALL .md files ===
echo ""
echo "━━━ Scanning all .md files (including symlinks) ━━━"

# Find all .md files (including those reachable via symlinks)
# -L: follow symlinks; -type f: regular files; -type l: symlinks
MD_FILES=$(find -L "$PROJECT_DIR" \
  -path "$PROJECT_DIR/.git" -prune -o \
  -path "$PROJECT_DIR/node_modules" -prune -o \
  -path "$PROJECT_DIR/.parent-automation/brain-snapshot" -prune -o \
  -path "$PROJECT_DIR/.parent-automation/pre-align-backup-*" -prune -o \
  \( -name "*.md" -type f -o -name "*.md" -type l \) \
  -print 2>/dev/null)

DOC_INVENTORY="$PROJECT_DIR/.planning/doc-inventory.md"
if [[ "$DRY_RUN" == "false" ]]; then
  mkdir -p "$PROJECT_DIR/.planning"
  {
    echo "# Documentation Inventory — $TIMESTAMP"
    echo ""
    echo "**Project:** $(basename "$PROJECT_DIR")"
    echo "**Total .md files:** $(echo "$MD_FILES" | grep -c .)"
    echo ""
    echo "## File Listing"
    echo ""
    echo "| Path | Type | Symlink Target | Category |"
    echo "|------|------|----------------|----------|"
  } > "$DOC_INVENTORY"
fi

while IFS= read -r mdfile; do
  [[ -z "$mdfile" ]] && continue
  REL_PATH="${mdfile#$PROJECT_DIR/}"

  # Determine type
  FILE_TYPE="file"
  SYMLINK_TARGET="-"
  if [[ -L "$mdfile" ]]; then
    FILE_TYPE="symlink"
    SYMLINK_TARGET=$(readlink "$mdfile" 2>/dev/null || echo "broken")
    # Check if symlink is broken
    if [[ ! -e "$mdfile" ]]; then
      WARNINGS+=("Broken symlink: $REL_PATH → $SYMLINK_TARGET")
    fi
  fi

  # Categorize by location and name pattern
  CATEGORY="unclassified"
  case "$REL_PATH" in
    .planning/*) CATEGORY="planning" ;;
    tasks/*) CATEGORY="tasks" ;;
    docs/*|documentation/*|architecture/*|adr/*|decisions/*) CATEGORY="documentation" ;;
    runbooks/*|operations/*) CATEGORY="runbooks" ;;
    specs/*|requirements/*) CATEGORY="specs" ;;
    src/*|lib/*) CATEGORY="inline-code-doc" ;;
    test/*|tests/*|__tests__/*) CATEGORY="test-doc" ;;
    examples/*|samples/*) CATEGORY="examples" ;;
    .parent-automation/*) CATEGORY="brain-internal" ;;
    CLAUDE.md|README.md|LICENSE.md|CHANGELOG.md|CONTRIBUTING.md|SECURITY.md) CATEGORY="standard-root" ;;
    */CLAUDE.md|*/README.md) CATEGORY="nested-readme" ;;
    *)
      # Pattern-match by content
      if [[ -r "$mdfile" ]]; then
        FIRST_LINE=$(head -1 "$mdfile" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$FIRST_LINE" in
          *learning*|*lesson*) CATEGORY="lessons-loose" ;;
          *todo*|*backlog*) CATEGORY="todo-loose" ;;
          *decision*|*adr*) CATEGORY="decision-loose" ;;
          *roadmap*|*plan*) CATEGORY="planning-loose" ;;
          *requirement*|*spec*) CATEGORY="spec-loose" ;;
          *) CATEGORY="other" ;;
        esac
      fi
      ;;
  esac

  if [[ "$DRY_RUN" == "false" ]]; then
    echo "| $REL_PATH | $FILE_TYPE | $SYMLINK_TARGET | $CATEGORY |" >> "$DOC_INVENTORY"
  fi

  # Auto-relocate loose canonical files
  case "$CATEGORY" in
    lessons-loose)
      TARGET="$PROJECT_DIR/tasks/lessons.md"
      if [[ ! -f "$TARGET" ]]; then
        CHANGES+=("Categorized: $REL_PATH → tasks/lessons.md (was loose)")
        if [[ "$DRY_RUN" == "false" ]]; then
          mkdir -p "$PROJECT_DIR/tasks"
          mv "$mdfile" "$TARGET"
        fi
      else
        WARNINGS+=("Loose lessons file: $REL_PATH (target tasks/lessons.md exists, manual merge needed)")
      fi
      ;;
    todo-loose)
      TARGET="$PROJECT_DIR/tasks/todo.md"
      if [[ ! -f "$TARGET" ]]; then
        CHANGES+=("Categorized: $REL_PATH → tasks/todo.md (was loose)")
        if [[ "$DRY_RUN" == "false" ]]; then
          mkdir -p "$PROJECT_DIR/tasks"
          mv "$mdfile" "$TARGET"
        fi
      else
        WARNINGS+=("Loose todo file: $REL_PATH (target tasks/todo.md exists, manual merge needed)")
      fi
      ;;
    decision-loose)
      WARNINGS+=("Loose decision file: $REL_PATH — consider moving to docs/decisions/ or .planning/")
      ;;
  esac
done <<< "$MD_FILES"

# === Step 2c: Index symlinks pointing into vault or external docs ===
SYMLINK_COUNT=$(echo "$MD_FILES" | xargs -I{} test -L {} && echo "{}" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SYMLINK_COUNT" -gt 0 ]]; then
  CHANGES+=("Found $SYMLINK_COUNT symlinked .md files (cataloged in doc-inventory.md)")
fi

if [[ "$DRY_RUN" == "false" ]]; then
  CHANGES+=("Generated doc-inventory.md (categorized all .md files)")
fi

# === Step 3: Migrate project lessons to vault ===
echo ""
echo "━━━ Migrating lessons to vault ━━━"

if [[ -f "$PROJECT_DIR/tasks/lessons.md" ]]; then
  CUSTOMER_LESSONS_DIR="$VAULT_PATH/lessons/by-customer/$CUSTOMER"
  if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$CUSTOMER_LESSONS_DIR"
    cp "$PROJECT_DIR/tasks/lessons.md" "$CUSTOMER_LESSONS_DIR/$(basename "$PROJECT_DIR")-lessons-$TIMESTAMP.md"
  fi
  CHANGES+=("Migrated lessons to vault/lessons/by-customer/$CUSTOMER/")
fi

# === Step 4: Backfill missing canonical files ===
echo ""
echo "━━━ Backfilling missing files ━━━"

CANONICAL_FILES=(
  ".planning/PROJECT.md"
  ".planning/STATE.md"
  ".planning/ALPHA.md"
  ".planning/ROADMAP.md"
  ".planning/REQUIREMENTS.md"
  ".planning/bootstrap-decisions.jsonl"
  "tasks/todo.md"
  "tasks/lessons.md"
)

for f in "${CANONICAL_FILES[@]}"; do
  if [[ ! -f "$PROJECT_DIR/$f" ]]; then
    CHANGES+=("Created stub: $f")
    if [[ "$DRY_RUN" == "false" ]]; then
      mkdir -p "$PROJECT_DIR/$(dirname "$f")"
      case "$f" in
        *PROJECT.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# $(basename "$PROJECT_DIR") — Project Definition

**Customer:** $CUSTOMER
**Type:** $PROJECT_TYPE
**Created:** $TIMESTAMP

## Purpose

[TODO: Define durable purpose]

## Stakeholders

[TODO: Who owns this]

## Out of Scope

[TODO: Explicit boundaries]
EOF
          ;;
        *STATE.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# $(basename "$PROJECT_DIR") — Implementation State

**Last updated:** $TIMESTAMP
**Phase:** Aligned (post-import)

## Current Phase

Imported and aligned to canonical structure.

## Shipped

[TODO: List what currently works]

## Open

[TODO: List what's pending]
EOF
          ;;
        *ALPHA.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# $(basename "$PROJECT_DIR") — Alpha Gate

[TODO: Define gate criteria for alpha readiness]
EOF
          ;;
        *ROADMAP.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# $(basename "$PROJECT_DIR") — Roadmap

## Phase 0 — Bootstrap (current)
- [x] Aligned to canonical structure
- [ ] Ark integration verified
- [ ] Initial implementation

## Phase 1 — Core
[TODO]

## Phase 2 — Hardening
[TODO]
EOF
          ;;
        *REQUIREMENTS.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# $(basename "$PROJECT_DIR") — Requirements

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
EOF
          ;;
        *todo.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# Todo

## Active

- [ ] Verify post-alignment state
- [ ] Update PROJECT.md with real purpose

## Backlog

[TODO]
EOF
          ;;
        *lessons.md)
          cat > "$PROJECT_DIR/$f" <<EOF
# Project Lessons

Captured corrections (rules, not descriptions).

EOF
          ;;
        *bootstrap-decisions.jsonl)
          touch "$PROJECT_DIR/$f"
          ;;
      esac
    fi
  fi
done

# === Step 5: Validate conventions ===
echo ""
echo "━━━ Validating conventions ━━━"

# Check for inline role arrays (RBAC anti-pattern)
if grep -r "\['admin'.*'staff'\]\|\[\"admin\".*\"staff\"\]" "$PROJECT_DIR/src" 2>/dev/null | grep -v "rbac.ts" | head -1 >/dev/null; then
  WARNINGS+=("Inline RBAC role arrays found — should use requireRole() from src/lib/rbac.ts")
fi

# Check for unsuffixed currency columns
if grep -r "_amount\|_price\|_cost\|_total" "$PROJECT_DIR/src" 2>/dev/null | grep -v "_zar\|_usd\|_minutes\|_seconds" | head -1 >/dev/null; then
  WARNINGS+=("Unsuffixed currency/duration columns found — must end in _zar/_usd/_minutes/_seconds")
fi

# === Step 6: Generate alignment report ===
echo ""
echo "━━━ Generating alignment report ━━━"

REPORT="$PROJECT_DIR/.planning/alignment-report.md"

if [[ "$DRY_RUN" == "false" ]]; then
  mkdir -p "$PROJECT_DIR/.planning"
  {
    echo "# Alignment Report — $TIMESTAMP"
    echo ""
    echo "**Project:** $PROJECT_DIR"
    echo "**Customer:** $CUSTOMER"
    echo "**Type:** $PROJECT_TYPE"
    echo "**Backup:** $BACKUP_DIR"
    echo ""
    echo "## Changes Applied"
    echo ""
    if [[ ${#CHANGES[@]} -eq 0 ]]; then
      echo "_No changes needed_"
    else
      for c in "${CHANGES[@]}"; do
        echo "- $c"
      done
    fi
    echo ""
    echo "## Warnings (manual review)"
    echo ""
    if [[ ${#WARNINGS[@]} -eq 0 ]]; then
      echo "_None_"
    else
      for w in "${WARNINGS[@]}"; do
        echo "- $w"
      done
    fi
    echo ""
    echo "## Next Steps"
    echo ""
    echo "1. Review the changes above"
    echo "2. Update stub files (PROJECT.md, STATE.md) with real content"
    echo "3. Address warnings if any"
    echo "4. Run \`ark bootstrap\` to log alignment decision"
    echo "5. Run \`ark status\` to verify"
  } > "$REPORT"
  echo "✅ Report: $REPORT"
fi

# === Step 7: Log alignment decision ===
if [[ "$DRY_RUN" == "false" ]] && [[ -f "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" ]]; then
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"projectType\":\"$PROJECT_TYPE\",\"customer\":\"$CUSTOMER\",\"projectName\":\"$(basename "$PROJECT_DIR")\",\"decisionsApplied\":[\"alignment-applied\",\"canonical-structure-enforced\"],\"contradictionsResolved\":[],\"lessonsUsed\":[],\"timeMs\":0,\"tokenEstimate\":0,\"alignmentChanges\":${#CHANGES[@]},\"alignmentWarnings\":${#WARNINGS[@]}}" >> "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"
fi

# === Summary ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "✅ DRY RUN COMPLETE — no changes made"
else
  echo "✅ ALIGNMENT COMPLETE"
fi
echo ""
echo "Changes: ${#CHANGES[@]}"
echo "Warnings: ${#WARNINGS[@]}"
echo ""
if [[ ${#CHANGES[@]} -gt 0 ]]; then
  echo "Changed:"
  printf '  - %s\n' "${CHANGES[@]}"
fi
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Warnings:"
  printf '  ⚠️  %s\n' "${WARNINGS[@]}"
fi
echo ""
echo "Next: ark bootstrap"
