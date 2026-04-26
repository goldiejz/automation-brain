#!/usr/bin/env bash
# brain secrets — secrets management pattern
#
# Detects deployment target and provides scaffolding for secrets:
#   cloudflare-workers → wrangler secrets
#   vercel → vercel env
#   aws → AWS Secrets Manager / Parameter Store stub
#   docker → .env + docker-compose
#   none → .env.example only
#
# Usage:
#   brain secrets init       # set up scaffolding for current project
#   brain secrets list       # list expected secrets from .env.example
#   brain secrets check      # verify all required secrets present

set -uo pipefail

PROJECT_DIR="$(pwd)"
ACTION="${1:-init}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Detect deployment target
DEPLOY_TARGET="none"
if [[ -f "$PROJECT_DIR/wrangler.toml" ]] || [[ -f "$PROJECT_DIR/wrangler.jsonc" ]]; then
  DEPLOY_TARGET="cloudflare"
elif [[ -f "$PROJECT_DIR/vercel.json" ]]; then
  DEPLOY_TARGET="vercel"
elif [[ -f "$PROJECT_DIR/fly.toml" ]]; then
  DEPLOY_TARGET="fly"
elif [[ -f "$PROJECT_DIR/netlify.toml" ]]; then
  DEPLOY_TARGET="netlify"
elif [[ -f "$PROJECT_DIR/Dockerfile" ]]; then
  DEPLOY_TARGET="docker"
fi

case "$ACTION" in
  init)
    echo "🔐 Brain Secrets Setup"
    echo "  Detected deployment: $DEPLOY_TARGET"
    echo ""

    # Always create .env.example
    if [[ ! -f "$PROJECT_DIR/.env.example" ]]; then
      cat > "$PROJECT_DIR/.env.example" <<EOF
# Environment Variables — copy to .env.local for local dev
# DO NOT commit .env.local

# Database
DATABASE_URL=

# Auth
AUTH_SECRET=
AUTH_TRUSTED_HOSTS=

# External APIs
# OPENAI_API_KEY=
# STRIPE_SECRET_KEY=

# Observability
# SENTRY_DSN=
EOF
      echo -e "  ${GREEN}✅${NC} Created .env.example"
    fi

    # Always add .env files to .gitignore
    if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
      grep -q "^.env.local$" "$PROJECT_DIR/.gitignore" || echo ".env.local" >> "$PROJECT_DIR/.gitignore"
      grep -q "^.env$" "$PROJECT_DIR/.gitignore" || echo ".env" >> "$PROJECT_DIR/.gitignore"
      grep -q "^.env.production$" "$PROJECT_DIR/.gitignore" || echo ".env.production" >> "$PROJECT_DIR/.gitignore"
    else
      cat > "$PROJECT_DIR/.gitignore" <<EOF
node_modules/
.env
.env.local
.env.production
dist/
build/
*.log
.DS_Store
EOF
    fi

    # Deploy-specific scaffolding
    case "$DEPLOY_TARGET" in
      cloudflare)
        cat > "$PROJECT_DIR/.deploy/secrets.md" <<EOF || true
# Cloudflare Secrets

## Per-environment secrets

\`\`\`bash
# Set secret in production
wrangler secret put DATABASE_URL

# Set secret in staging
wrangler secret put DATABASE_URL --env staging

# List secrets
wrangler secret list
\`\`\`

## Bindings (D1, KV, R2) — in wrangler.toml

\`\`\`toml
[[d1_databases]]
binding = "DB"
database_name = "your-db"
database_id = "<from Cloudflare dashboard>"

[[kv_namespaces]]
binding = "CACHE"
id = "<from dashboard>"
\`\`\`

## Local dev

Use \`.dev.vars\` (auto-loaded by wrangler dev):
\`\`\`
DATABASE_URL=local-d1
AUTH_SECRET=dev-secret
\`\`\`
EOF
        mkdir -p "$PROJECT_DIR/.deploy"
        # Create .dev.vars stub
        if [[ ! -f "$PROJECT_DIR/.dev.vars" ]]; then
          cat > "$PROJECT_DIR/.dev.vars" <<EOF
# Local dev secrets — auto-loaded by wrangler dev
# DO NOT commit
DATABASE_URL=
AUTH_SECRET=dev-secret-change-me
EOF
          grep -q "^.dev.vars$" "$PROJECT_DIR/.gitignore" || echo ".dev.vars" >> "$PROJECT_DIR/.gitignore"
        fi
        echo -e "  ${GREEN}✅${NC} Cloudflare secrets pattern (use: wrangler secret put)"
        ;;

      vercel)
        cat > "$PROJECT_DIR/.deploy/secrets.md" <<EOF || true
# Vercel Secrets

\`\`\`bash
# Add via CLI
vercel env add DATABASE_URL

# Or via dashboard:
# https://vercel.com/<team>/<project>/settings/environment-variables
\`\`\`

## Local dev
Pull production env locally:
\`\`\`bash
vercel env pull .env.local
\`\`\`
EOF
        mkdir -p "$PROJECT_DIR/.deploy"
        echo -e "  ${GREEN}✅${NC} Vercel secrets pattern"
        ;;

      docker)
        cat > "$PROJECT_DIR/.deploy/secrets.md" <<EOF || true
# Docker Secrets

## Local dev — use .env file
\`\`\`bash
cp .env.example .env.local
# Edit .env.local with real values
\`\`\`

## Production — Docker secrets or env file
\`\`\`bash
# Option 1: Docker secrets
docker secret create db_url ./db_url.txt

# Option 2: Environment file
docker run --env-file .env.production ...

# Option 3: Docker compose
# In docker-compose.yml:
services:
  app:
    env_file:
      - .env.production
\`\`\`
EOF
        mkdir -p "$PROJECT_DIR/.deploy"
        echo -e "  ${GREEN}✅${NC} Docker secrets pattern"
        ;;

      none)
        echo -e "  ${YELLOW}ℹ${NC}  No deployment target detected — using .env.example only"
        ;;
    esac

    echo ""
    echo "Secrets workflow:"
    echo "  1. Edit .env.example to declare expected secrets"
    echo "  2. Copy to .env.local for local dev (gitignored)"
    echo "  3. For deploys: see .deploy/secrets.md (deploy-specific)"
    ;;

  list)
    if [[ -f "$PROJECT_DIR/.env.example" ]]; then
      echo "Expected secrets:"
      grep -E "^[A-Z_]+=" "$PROJECT_DIR/.env.example" | sed 's/=.*//' | sed 's/^/  /'
    else
      echo "No .env.example found. Run: brain secrets init"
    fi
    ;;

  check)
    echo "Checking secrets..."
    if [[ ! -f "$PROJECT_DIR/.env.example" ]]; then
      echo -e "${YELLOW}⚠${NC}  No .env.example — run: brain secrets init"
      exit 0
    fi

    # Get expected vars from .env.example
    EXPECTED=$(grep -E "^[A-Z_]+=" "$PROJECT_DIR/.env.example" | sed 's/=.*//')
    MISSING=()

    # Check .env.local for local dev
    for var in $EXPECTED; do
      if [[ -f "$PROJECT_DIR/.env.local" ]]; then
        grep -qE "^${var}=" "$PROJECT_DIR/.env.local" || MISSING+=("$var")
      else
        MISSING+=("$var")
      fi
    done

    if [[ ${#MISSING[@]} -eq 0 ]]; then
      echo -e "${GREEN}✅${NC} All expected secrets present in .env.local"
    else
      echo -e "${YELLOW}⚠${NC}  Missing secrets in .env.local:"
      printf '  - %s\n' "${MISSING[@]}"
    fi
    ;;
esac
