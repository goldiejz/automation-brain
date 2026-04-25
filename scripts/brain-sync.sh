#!/usr/bin/env bash
# brain-sync — Update sub-project's brain snapshot from vault
#
# Usage:
#   brain-sync.sh                    # Sync current dir's snapshot
#   brain-sync.sh /path/to/project   # Sync specific project
#
# What it does:
#   1. Pull latest vault from GitHub (origin/main)
#   2. Validate vault snapshot integrity
#   3. Copy lessons/cache/templates to local .parent-automation/brain-snapshot/
#   4. Update SNAPSHOT-MANIFEST.json with new version + timestamp
#   5. Report what changed

set -euo pipefail

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
TARGET_PROJECT="${1:-$(pwd)}"

# Resolve target project root (look for .parent-automation/)
if [[ ! -d "$TARGET_PROJECT/.parent-automation" ]]; then
  echo "❌ No .parent-automation/ found in $TARGET_PROJECT"
  echo "   Run from project root, or pass project path as argument"
  exit 1
fi

SNAPSHOT_TARGET="$TARGET_PROJECT/.parent-automation/brain-snapshot"

echo "🧠 Brain Sync: $TARGET_PROJECT"
echo ""

# Step 1: Pull latest vault
echo "Step 1: Pulling latest vault from GitHub..."
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git fetch origin main --quiet
  BEFORE=$(git rev-parse HEAD)
  git pull origin main --quiet
  AFTER=$(git rev-parse HEAD)
  if [[ "$BEFORE" == "$AFTER" ]]; then
    echo "  ✅ Vault already up to date ($BEFORE)"
  else
    echo "  ✅ Vault updated: $BEFORE → $AFTER"
  fi
else
  echo "  ⚠️  Vault is not a git repo, skipping pull"
fi

# Step 2: Validate vault has required content
echo ""
echo "Step 2: Validating vault contents..."
REQUIRED_DIRS=("lessons" "cache" "bootstrap")
for dir in "${REQUIRED_DIRS[@]}"; do
  if [[ ! -d "$VAULT_PATH/$dir" ]]; then
    echo "  ❌ Missing required directory: $dir"
    exit 1
  fi
done
echo "  ✅ Vault structure valid"

# Step 3: Backup existing snapshot
echo ""
echo "Step 3: Backing up existing snapshot..."
if [[ -d "$SNAPSHOT_TARGET" ]]; then
  BACKUP_DIR="$SNAPSHOT_TARGET.backup.$(date +%s)"
  cp -r "$SNAPSHOT_TARGET" "$BACKUP_DIR"
  echo "  ✅ Backed up to: $BACKUP_DIR"
fi

# Step 4: Sync snapshot contents
echo ""
echo "Step 4: Syncing snapshot..."
mkdir -p "$SNAPSHOT_TARGET"

# Copy lessons (universal + customer-specific)
if [[ -d "$VAULT_PATH/lessons" ]]; then
  rsync -a --delete "$VAULT_PATH/lessons/" "$SNAPSHOT_TARGET/lessons/"
  LESSON_COUNT=$(find "$SNAPSHOT_TARGET/lessons" -name "*.md" | wc -l | tr -d ' ')
  echo "  ✅ Lessons: $LESSON_COUNT files"
fi

# Copy cache (query-responses)
if [[ -d "$VAULT_PATH/cache" ]]; then
  rsync -a --delete "$VAULT_PATH/cache/" "$SNAPSHOT_TARGET/cache/"
  CACHE_COUNT=$(find "$SNAPSHOT_TARGET/cache" -name "*.md" | wc -l | tr -d ' ')
  echo "  ✅ Cache: $CACHE_COUNT entries"
fi

# Copy bootstrap templates
if [[ -d "$VAULT_PATH/bootstrap" ]]; then
  mkdir -p "$SNAPSHOT_TARGET/templates"
  if [[ -d "$VAULT_PATH/bootstrap/project-types" ]]; then
    rsync -a "$VAULT_PATH/bootstrap/project-types/" "$SNAPSHOT_TARGET/templates/"
  fi
  if [[ -f "$VAULT_PATH/bootstrap/anti-patterns.md" ]]; then
    cp "$VAULT_PATH/bootstrap/anti-patterns.md" "$SNAPSHOT_TARGET/templates/"
  fi
  TEMPLATE_COUNT=$(find "$SNAPSHOT_TARGET/templates" -name "*.md" | wc -l | tr -d ' ')
  echo "  ✅ Templates: $TEMPLATE_COUNT files"
fi

# Step 5: Update manifest
echo ""
echo "Step 5: Updating manifest..."
cat > "$SNAPSHOT_TARGET/SNAPSHOT-MANIFEST.json" <<EOF
{
  "version": "$(date +%Y%m%d-%H%M%S)",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "synced_from": "$VAULT_PATH",
  "vault_commit": "$(cd "$VAULT_PATH" && git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "project_type": "auto-detected",
  "customer": "auto-detected",
  "contents": {
    "lessons": ${LESSON_COUNT:-0},
    "cache_entries": ${CACHE_COUNT:-0},
    "templates": ${TEMPLATE_COUNT:-0}
  },
  "manifest_version": "2.0",
  "offline_capable": true
}
EOF
echo "  ✅ Manifest updated"

# Step 6: Show summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BRAIN SYNC COMPLETE"
echo ""
echo "  Project: $TARGET_PROJECT"
echo "  Vault commit: $(cd "$VAULT_PATH" && git rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
echo "  Lessons: ${LESSON_COUNT:-0}"
echo "  Cache: ${CACHE_COUNT:-0}"
echo "  Templates: ${TEMPLATE_COUNT:-0}"
echo ""
echo "Next: Run bootstrap or use queries — snapshot is fresh."
