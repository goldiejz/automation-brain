#!/usr/bin/env bash
# brain backup — disaster recovery for the vault
#
# Creates timestamped backup of vault to ~/.brain-backups/
# Auto-rotates old backups (keep last 30)

set -uo pipefail

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
BACKUP_ROOT="$HOME/.brain-backups"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_ROOT/vault-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_ROOT"

echo "💾 Brain Backup"
echo "  Source: $VAULT_PATH"
echo "  Target: $BACKUP_PATH"
echo ""

# Tar+gzip excluding node_modules and logs
tar -czf "$BACKUP_PATH" \
  --exclude="node_modules" \
  --exclude="logs/*.log" \
  --exclude=".git/objects/pack" \
  -C "$(dirname "$VAULT_PATH")" \
  "$(basename "$VAULT_PATH")" 2>&1 | tail -3

SIZE=$(ls -lh "$BACKUP_PATH" | awk '{print $5}')
echo "✅ Backup created: $SIZE"

# Rotate: keep last 30 backups
COUNT=$(ls -1 "$BACKUP_ROOT"/vault-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [[ $COUNT -gt 30 ]]; then
  ls -1t "$BACKUP_ROOT"/vault-*.tar.gz | tail -n +31 | xargs rm -f
  REMOVED=$((COUNT - 30))
  echo "  Rotated: removed $REMOVED old backup(s)"
fi

echo ""
echo "To restore:"
echo "  tar -xzf $BACKUP_PATH -C ~/vaults/"
echo ""
echo "All backups:"
ls -lh "$BACKUP_ROOT"/vault-*.tar.gz 2>/dev/null | tail -5 | awk '{print "  " $9 "  " $5}'
