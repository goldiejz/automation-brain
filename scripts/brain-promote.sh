#!/usr/bin/env bash
# brain promote — gated production deployment
#
# Usage:
#   brain promote --to staging              # autonomous
#   brain promote --to production --confirm # human-confirmed
#   brain promote --to production --dry-run # show what would deploy
#
# Production NEVER deploys without --confirm flag.
# Staging deploys are autonomous.

set -uo pipefail

PROJECT_DIR="$(pwd)"
TARGET=""
CONFIRMED=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) TARGET="$2"; shift 2 ;;
    --confirm) CONFIRMED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) shift ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "❌ --to <staging|production> required"; exit 1; }

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🚀 Brain Promote"
echo "  Project: $(basename "$PROJECT_DIR")"
echo "  Target: $TARGET"

# Production gate
if [[ "$TARGET" == "production" ]] && [[ "$CONFIRMED" != "true" ]]; then
  echo ""
  echo -e "${RED}🛑 PRODUCTION DEPLOY BLOCKED${NC}"
  echo ""
  echo "Production deployments require explicit confirmation."
  echo "This is a CEO-level decision and cannot be autonomous."
  echo ""
  echo "Pre-flight checklist before promoting to production:"
  echo "  [ ] All tests passing in staging"
  echo "  [ ] Security audit clean (.planning/phase-N/team/security-audit.md)"
  echo "  [ ] PM signed off the latest phase"
  echo "  [ ] Database migration plan reviewed"
  echo "  [ ] Rollback plan documented"
  echo "  [ ] Customer/stakeholders notified"
  echo ""
  echo "When ready, run:"
  echo "  brain promote --to production --confirm"
  echo ""
  exit 1
fi

# Detect deployment system
DEPLOY_CMD=""
if [[ -f "$PROJECT_DIR/wrangler.toml" ]] || [[ -f "$PROJECT_DIR/wrangler.jsonc" ]]; then
  if [[ "$TARGET" == "production" ]]; then
    DEPLOY_CMD="npx wrangler deploy"
  else
    DEPLOY_CMD="npx wrangler deploy --env staging"
  fi
elif [[ -f "$PROJECT_DIR/vercel.json" ]]; then
  if [[ "$TARGET" == "production" ]]; then
    DEPLOY_CMD="npx vercel --prod"
  else
    DEPLOY_CMD="npx vercel"
  fi
elif [[ -f "$PROJECT_DIR/fly.toml" ]]; then
  DEPLOY_CMD="fly deploy"
elif grep -q '"deploy"' "$PROJECT_DIR/package.json" 2>/dev/null; then
  DEPLOY_CMD="npm run deploy"
elif [[ -f "$PROJECT_DIR/Dockerfile" ]]; then
  echo -e "${YELLOW}⚠️  Docker self-hosted: configure your own deploy${NC}"
  DEPLOY_CMD="docker build -t $(basename "$PROJECT_DIR") . && docker push ..."
else
  echo -e "${RED}❌ No deployment config detected${NC}"
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "DRY RUN — would execute:"
  echo "  $DEPLOY_CMD"
  exit 0
fi

# Production-specific safety: require all tests pass
if [[ "$TARGET" == "production" ]]; then
  echo ""
  echo "Pre-deploy checks for production:"
  cd "$PROJECT_DIR"

  if grep -q '"test"' package.json 2>/dev/null; then
    echo "  Running tests..."
    if ! npm test 2>&1 | tail -5; then
      echo -e "${RED}❌ Tests failing — aborting production deploy${NC}"
      exit 1
    fi
  fi

  echo -e "  ${GREEN}✅${NC} Tests pass"

  # Verify last phase signed off by team
  LAST_REPORT=$(ls -t "$PROJECT_DIR/.planning/phase-"*-ceo-report.md 2>/dev/null | head -1)
  if [[ -n "$LAST_REPORT" ]]; then
    if grep -q "DELIVERED" "$LAST_REPORT"; then
      echo -e "  ${GREEN}✅${NC} Last phase signed off"
    else
      echo -e "${RED}❌ Last phase not signed off — aborting${NC}"
      exit 1
    fi
  fi
fi

# Execute deploy
echo ""
echo "Deploying to $TARGET..."
cd "$PROJECT_DIR"
eval "$DEPLOY_CMD"
DEPLOY_STATUS=$?

# Log promotion
LOG_PATH="$PROJECT_DIR/.planning/promotions.jsonl"
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"target\":\"$TARGET\",\"command\":\"$DEPLOY_CMD\",\"status\":$DEPLOY_STATUS,\"confirmed_by\":\"${USER:-unknown}\"}" >> "$LOG_PATH"

if [[ $DEPLOY_STATUS -eq 0 ]]; then
  echo ""
  echo -e "${GREEN}✅ Deployed to $TARGET${NC}"

  # Update STATE.md
  if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
    if [[ "$TARGET" == "production" ]]; then
      sed -i.bak "s/^\*\*Deploy posture:\*\*.*/\*\*Deploy posture:\*\* production-deployed/" "$PROJECT_DIR/.planning/STATE.md" 2>/dev/null
    else
      sed -i.bak "s/^\*\*Deploy posture:\*\*.*/\*\*Deploy posture:\*\* staging-deployed/" "$PROJECT_DIR/.planning/STATE.md" 2>/dev/null
    fi
    rm -f "$PROJECT_DIR/.planning/STATE.md.bak"
  fi

  exit 0
else
  echo -e "${RED}❌ Deploy failed${NC}"
  exit 1
fi
