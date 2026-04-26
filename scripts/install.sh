#!/usr/bin/env bash
# brain install — set up brain on a new machine
#
# Usage: bash install.sh [--vault-path /path/to/vault]
#
# What it does:
# 1. Clones vault from GitHub if not present
# 2. Installs Node deps (ts-node, @types/node)
# 3. Symlinks brain CLI to ~/.local/bin/
# 4. Symlinks hooks to ~/.claude/hooks/
# 5. Registers hooks in ~/.claude/settings.json
# 6. Installs brain skill at ~/.claude/skills/brain/
# 7. Runs brain doctor to verify

set -euo pipefail

REPO_URL="${BRAIN_REPO_URL:-https://github.com/goldiejz/automation-brain.git}"
VAULT_PATH="${1:-$HOME/vaults/automation-brain}"
[[ "${1:-}" == "--vault-path" ]] && VAULT_PATH="$2"

GREEN='\033[0;32m'
NC='\033[0m'

echo "🧠 Installing Brain at: $VAULT_PATH"
echo ""

# Step 1: Clone or update vault
if [[ -d "$VAULT_PATH/.git" ]]; then
  echo "Step 1: Vault exists, pulling latest..."
  git -C "$VAULT_PATH" pull origin main --quiet
else
  echo "Step 1: Cloning vault..."
  mkdir -p "$(dirname "$VAULT_PATH")"
  git clone "$REPO_URL" "$VAULT_PATH" --quiet
fi
echo -e "  ${GREEN}✅${NC} Vault ready"

# Step 2: Install Node deps
echo ""
echo "Step 2: Installing Node dependencies..."
cd "$VAULT_PATH"
if [[ ! -d node_modules ]]; then
  npm install --silent 2>&1 | tail -3
fi
echo -e "  ${GREEN}✅${NC} Dependencies installed"

# Step 3: Make scripts executable
echo ""
echo "Step 3: Making scripts executable..."
chmod +x "$VAULT_PATH/scripts/"*.sh 2>/dev/null || true
chmod +x "$VAULT_PATH/scripts/brain" 2>/dev/null || true
chmod +x "$VAULT_PATH/hooks/"*.sh 2>/dev/null || true
echo -e "  ${GREEN}✅${NC} Scripts executable"

# Step 4: Symlink brain CLI to ~/.local/bin/
echo ""
echo "Step 4: Installing 'brain' command..."
mkdir -p "$HOME/.local/bin"
ln -sf "$VAULT_PATH/scripts/brain" "$HOME/.local/bin/brain"
echo -e "  ${GREEN}✅${NC} brain → ~/.local/bin/brain"

# Detect shell and add to PATH if needed
SHELL_RC=""
case "$SHELL" in
  */zsh) SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
esac
if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
  if ! grep -q '$HOME/.local/bin' "$SHELL_RC"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo "  Added ~/.local/bin to PATH in $SHELL_RC (open new shell to use)"
  fi
fi

# Step 5: Symlink hooks
echo ""
echo "Step 5: Installing hooks..."
mkdir -p "$HOME/.claude/hooks"
for hook in "$VAULT_PATH/hooks/"*.sh; do
  [[ -f "$hook" ]] || continue
  hook_name=$(basename "$hook")
  ln -sf "$hook" "$HOME/.claude/hooks/$hook_name"
  echo -e "  ${GREEN}✅${NC} $hook_name → ~/.claude/hooks/"
done

# Step 6: Register hooks in settings.json
echo ""
echo "Step 6: Registering hooks in ~/.claude/settings.json..."
python3 <<PYEOF
import json
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"
if not settings_path.exists():
    settings = {"env": {}, "permissions": {"allow": []}, "hooks": {}}
else:
    settings = json.loads(settings_path.read_text())

settings.setdefault("hooks", {})

# SessionStart
ss = settings["hooks"].setdefault("SessionStart", [])
if not any("brain-session-start.sh" in str(h.get("command","")) for e in ss for h in e.get("hooks",[])):
    ss.append({"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/brain-session-start.sh","timeout":5}]})
    print("  Registered: SessionStart")

# Stop hooks
stop = settings["hooks"].setdefault("Stop", [])
for hook_name in ["brain-session-end.sh", "brain-extract-learnings.sh", "brain-error-monitor.sh"]:
    if not any(hook_name in str(h.get("command","")) for e in stop for h in e.get("hooks",[])):
        stop.append({"matcher":"","hooks":[{"type":"command","command":f"bash ~/.claude/hooks/{hook_name}","timeout":5}]})
        print(f"  Registered: Stop ({hook_name})")

settings_path.parent.mkdir(parents=True, exist_ok=True)
settings_path.write_text(json.dumps(settings, indent=2))
PYEOF

# Step 7: Install skill
echo ""
echo "Step 7: Installing brain skill..."
mkdir -p "$HOME/.claude/skills/brain"
if [[ -f "$HOME/.claude/skills/brain/SKILL.md" ]] || [[ -L "$HOME/.claude/skills/brain/SKILL.md" ]]; then
  rm -f "$HOME/.claude/skills/brain/SKILL.md"
fi
# Copy SKILL.md from vault if it exists, otherwise leave for manual install
if [[ -f "$VAULT_PATH/templates/skill/SKILL.md" ]]; then
  cp "$VAULT_PATH/templates/skill/SKILL.md" "$HOME/.claude/skills/brain/SKILL.md"
  echo -e "  ${GREEN}✅${NC} Skill installed"
fi

# Step 8: Run doctor
echo ""
echo "Step 8: Running brain doctor..."
echo ""
bash "$VAULT_PATH/scripts/brain-doctor.sh" || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ INSTALL COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Try it now:"
echo "  cd ~/code/your-project"
echo "  brain status     # Check current state"
echo "  brain init       # Initialize new project"
echo "  brain align      # Standardize imported project"
echo ""
echo "Restart your shell or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
