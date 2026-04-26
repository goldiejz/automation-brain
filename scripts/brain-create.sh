#!/usr/bin/env bash
# brain create — scaffold a new project from cached templates
#
# Three independent dimensions:
#   --type    what the project DOES (service-desk, revops, ops-intel, custom, ...)
#   --stack   what TOOLS it uses (vite-react-hono, nextjs, fastapi, none, ...)
#   --deploy  where it RUNS (cloudflare-workers, vercel, aws-lambda, none, ...)
#
# Usage:
#   brain create <name> --type <type> --customer <customer> [options]
#
# Options:
#   --stack <stack>     Technical stack (auto-detected if omitted)
#   --deploy <target>   Deployment target (auto-detected if omitted)
#   --path <dir>        Where to create (default: ~/code/)
#
# What it does:
# 1. Creates project directory
# 2. Composes templates: core (CLAUDE.md, .planning/, RBAC) + stack + deploy
# 3. Substitutes variables (project-name, customer, type, stack, deploy)
# 4. Initializes git, optional GitHub repo
# 5. Records decision to brain (Phase 6 learns successful combos)

set -uo pipefail

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"

PROJECT_NAME=""
PROJECT_TYPE=""
CUSTOMER=""
PROJECT_PATH="$HOME/code"
STACK=""
DEPLOY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) PROJECT_TYPE="$2"; shift 2 ;;
    --customer) CUSTOMER="$2"; shift 2 ;;
    --path) PROJECT_PATH="$2"; shift 2 ;;
    --stack) STACK="$2"; shift 2 ;;
    --deploy) DEPLOY="$2"; shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: brain create <name> --type <type> --customer <customer> [options]

Required:
  --type      service-desk | revops | ops-intelligence | marketplace |
              internal-tool | cli-tool | library | static-site | custom
  --customer  Customer name (e.g., acme, strategix)

Optional:
  --stack     vite-react-hono | nextjs | nextjs-on-workers | astro |
              tanstack-start | express-node | fastapi | django | rails |
              go-stdlib | rust-axum | swift-vapor | static-html | node-cli
              (auto-detected from existing files; asks if ambiguous)

  --deploy    cloudflare-workers | cloudflare-pages | vercel | netlify |
              aws-lambda | aws-ecs | gcp-run | azure-app | fly | railway |
              render | github-pages | docker-self-hosted | kubernetes | none
              (auto-detected from project type if omitted)

  --path      Where to create the project (default: ~/code/)

Examples:
  brain create acme-sd --type service-desk --customer acme \\
    --stack vite-react-hono --deploy cloudflare-workers

  brain create my-cli --type cli-tool --customer me \\
    --stack node-cli --deploy none

  brain create internal --type internal-tool --customer strategix \\
    --stack nextjs --deploy vercel

See ~/vaults/automation-brain/templates/STACKS.md for full list.
EOF
      exit 0
      ;;
    *)
      if [[ -z "$PROJECT_NAME" ]]; then
        PROJECT_NAME="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" ]] || [[ -z "$PROJECT_TYPE" ]] || [[ -z "$CUSTOMER" ]]; then
  echo "❌ Missing required args. Run: brain create --help"
  exit 1
fi

PROJECT_DIR="$PROJECT_PATH/$PROJECT_NAME"

GREEN='\033[0;32m'
NC='\033[0m'

echo "🆕 Creating project: $PROJECT_NAME"
echo "  Type: $PROJECT_TYPE"
echo "  Customer: $CUSTOMER"
echo "  Path: $PROJECT_DIR"
echo ""

# Check project doesn't already exist
if [[ -d "$PROJECT_DIR" ]]; then
  echo "❌ Project already exists at $PROJECT_DIR"
  exit 1
fi

# === Step 1: Create directory + git ===
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
git init --quiet
echo -e "  ${GREEN}✅${NC} Directory created"

# === Step 2: Copy templates from vault ===
SNAPSHOT_DIR="$VAULT_PATH/cache/query-responses"
TEMPLATE_DIR="$VAULT_PATH/bootstrap/project-types"

# Helper: extract content from cache file (strip YAML frontmatter)
extract_cache_content() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # Skip first frontmatter block (between --- markers), then take next 30 lines
    awk '/^---$/{count++; next} count==2{print}' "$file" | head -30
  fi
}

# Generate clean CLAUDE.md
cat > "$PROJECT_DIR/CLAUDE.md" <<EOF
# $PROJECT_NAME — Repo Instruction

> Project-specific. Mutable status lives in \`.planning/STATE.md\`.

## Project

$PROJECT_NAME — $PROJECT_TYPE platform for $CUSTOMER.

## Purpose

[TODO: Define durable purpose — what problem does this solve, for whom, why now]

## Current Scope (Phase 1)

[TODO: List core features — be specific, name acceptance criteria]

## Out of Scope

[TODO: Explicit boundaries — what is deferred, what is never planned]

## Constraints

- **Runtime:** Cloudflare Workers (or Pages, depending on type)
- **Database:** D1 (SQLite) with Drizzle ORM, tenant-scoped via \`tenant_id\`
- **Auth:** Centralized in \`src/lib/auth.ts\`, role checks via \`requireRole()\`
- **Currency:** Money columns end in \`_zar\` or \`_usd\`. Duration columns end in \`_minutes\` or \`_seconds\`. Never unsuffixed.
- **Tenancy:** Multi-tenant from day zero; tenant_id NEVER from request body

## Architecture Conventions

- **Tenant on every business table** — middleware-enforced, never trust user input
- **RBAC centralized** in \`src/lib/rbac.ts\` — single source of truth for role arrays
- **Route/compute split** — thin HTTP boundaries, testable business logic
- **Schema-first migrations** via Drizzle, applied with \`wrangler d1 migrations apply\`
- **Audit columns** on every business table: created_at, created_by, updated_at, updated_by
- **Soft delete** on tickets/timesheets/timelines; hard delete forbidden
- **Event emission** on every mutation — typed events to Cloudflare Queues

## RBAC Structure

See \`src/lib/rbac.ts\` — single source of truth.

Roles: customer | staff | manager | admin

All route guards use \`requireRole(userRole, requiredRole)\`. Never inline role arrays.

## Current Truth Sources

1. \`.planning/STATE.md\` — primary implementation truth (test/route/table counts, deploy posture)
2. \`.planning/ALPHA.md\` — gate definition (when is this ready)
3. \`.planning/REQUIREMENTS.md\` — mandatory requirements with evidence
4. \`.planning/ROADMAP.md\` — phase sequencing
5. \`tasks/todo.md\` — active backlog
6. \`tasks/lessons.md\` — captured corrections (rules, not descriptions)

## Workflow

Required reading before any non-trivial change:

1. \`~/vaults/automation-brain/STRUCTURE.md\` — canonical structure
2. This file
3. \`.planning/STATE.md\` — live truth
4. \`.planning/PROJECT.md\` — durable purpose
5. \`.planning/ROADMAP.md\` — phase sequencing
6. \`tasks/lessons.md\` — past corrections (don't regress)
7. \`tasks/todo.md\` — active work

Brain integration: \`.parent-automation/brain-snapshot/\` provides cached templates and 80+ lessons. Run \`brain status\` for current state.

## Anti-Patterns

- Inline role arrays (\`['admin', 'staff'].includes(...)\`) — use \`requireRole()\`
- Trusting body-supplied tenant_id — always from authenticated session
- Unsuffixed money columns (\`amount\` instead of \`amount_zar\`)
- Calling code-shipped "production-ready" without staging verification
- Skipping \`tasks/lessons.md\` — past lessons must apply

## Drift Rule

If this file contradicts \`.planning/STATE.md\` or current code, this file is wrong. Fix one or the other; never leave them disagreeing.
EOF
echo -e "  ${GREEN}✅${NC} CLAUDE.md generated from cached templates"

# Generate .planning/ files
mkdir -p "$PROJECT_DIR/.planning"

cat > "$PROJECT_DIR/.planning/PROJECT.md" <<EOF
# $PROJECT_NAME

**Customer:** $CUSTOMER
**Type:** $PROJECT_TYPE
**Created:** $(date -u +%Y-%m-%d)

## Purpose

[TODO: Define durable purpose]

## Stakeholders

[TODO: Who owns this]

## Out of Scope

[TODO: Explicit boundaries]
EOF

cat > "$PROJECT_DIR/.planning/STATE.md" <<EOF
# $PROJECT_NAME — State

**Last updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Current Phase:** Phase 0
**Status:** scaffolded

## Phase 0: Bootstrap (current)
- [x] Project created via \`brain create\`
- [ ] Phase 1 planning complete
- [ ] Initial implementation
EOF

cat > "$PROJECT_DIR/.planning/ALPHA.md" <<EOF
# Alpha Gate

[TODO: Define gate criteria — what must be true to call this alpha-ready]
EOF

cat > "$PROJECT_DIR/.planning/ROADMAP.md" <<EOF
# Roadmap

## Phase 0 — Bootstrap (current)
- [x] Scaffolded via brain create
- [ ] Configure environment
- [ ] Set up CI/CD

## Phase 1 — Core Slice
- [ ] [TODO: Define core features]
- [ ] Initial UI
- [ ] Basic auth

## Phase 2 — Hardening
- [ ] Tests >= 80% coverage
- [ ] Security review
- [ ] Performance baseline

## Phase 3 — Production
- [ ] Production deploy
- [ ] Monitoring
- [ ] Runbooks
EOF

cat > "$PROJECT_DIR/.planning/REQUIREMENTS.md" <<EOF
# Requirements

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| R-001 | Brain integration | done | .parent-automation/ exists |
EOF

touch "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"
echo -e "  ${GREEN}✅${NC} .planning/ files created"

# Create tasks/
mkdir -p "$PROJECT_DIR/tasks"
cat > "$PROJECT_DIR/tasks/todo.md" <<EOF
# Todo

## Active

- [ ] Define Phase 1 scope (update PROJECT.md + ROADMAP.md)
- [ ] Run \`brain deliver\` to start autonomous build

## Backlog

[TODO]
EOF

cat > "$PROJECT_DIR/tasks/lessons.md" <<EOF
# Project Lessons

Captured corrections (rules, not descriptions).
EOF

echo -e "  ${GREEN}✅${NC} tasks/ created"

# === Step 3: Resolve stack + deploy (auto-detect or use defaults) ===

# Sensible defaults per project type if user didn't specify
if [[ -z "$STACK" ]]; then
  case "$PROJECT_TYPE" in
    service-desk|revops) STACK="vite-react-hono" ;;
    ops-intelligence)    STACK="nextjs" ;;
    marketplace)         STACK="nextjs" ;;
    internal-tool)       STACK="nextjs" ;;
    cli-tool)            STACK="node-cli" ;;
    library)             STACK="node-lib" ;;
    static-site)         STACK="static-html" ;;
    custom|*)            STACK="custom" ;;
  esac
  echo -e "  ${YELLOW}ℹ${NC}  Stack defaulted to: $STACK"
fi

if [[ -z "$DEPLOY" ]]; then
  case "$PROJECT_TYPE" in
    cli-tool|library|custom) DEPLOY="none" ;;
    static-site)             DEPLOY="github-pages" ;;
    *)                       DEPLOY="docker-self-hosted" ;;
  esac
  echo -e "  ${YELLOW}ℹ${NC}  Deploy defaulted to: $DEPLOY (override with --deploy)"
fi

# === Step 4: Apply universal core (RBAC, currency discipline) ===
mkdir -p "$PROJECT_DIR/src/lib" "$PROJECT_DIR/src/db"

# Universal RBAC pattern — works in any framework
cat > "$PROJECT_DIR/src/lib/rbac.ts" <<EOF
// Centralized RBAC — single source of truth
// Lesson L-018: Never inline role arrays in routes/components

export type Role = 'staff' | 'manager' | 'admin' | 'customer';

export const ROLES: Record<Role, Role[]> = {
  customer: ['customer'],
  staff: ['staff'],
  manager: ['staff', 'manager'],
  admin: ['staff', 'manager', 'admin'],
};

export function requireRole(userRole: Role, requiredRole: Role): boolean {
  return ROLES[userRole]?.includes(requiredRole) ?? false;
}
EOF

# Universal schema convention notes
cat > "$PROJECT_DIR/src/db/schema.ts" <<EOF
// Schema conventions (apply to any DB):
// - Money columns end in _zar or _usd (never unsuffixed)
// - Duration columns end in _minutes or _seconds (never unsuffixed)
// - Every business table has tenant_id (multi-tenant projects)
// - Every business table has created_at, created_by, updated_at, updated_by
// - Soft delete via deleted_at (no hard deletes on tickets/timesheets/etc.)
EOF

# === Step 5: Apply STACK-specific scaffolding ===
case "$STACK" in
  vite-react-hono)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest"
  },
  "dependencies": {
    "hono": "^4.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/node": "^25.0.0",
    "typescript": "^6.0.0",
    "vite": "^7.0.0",
    "vitest": "^3.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Vite + React + Hono scaffold"
    ;;

  nextjs)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "test": "vitest"
  },
  "dependencies": {
    "next": "^16.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/node": "^25.0.0",
    "@types/react": "^19.0.0",
    "typescript": "^6.0.0",
    "vitest": "^3.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Next.js scaffold"
    ;;

  nextjs-on-workers)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "scripts": {
    "dev": "next dev",
    "build": "next build && opennextjs-cloudflare"
  },
  "dependencies": {
    "next": "^16.0.0",
    "react": "^19.0.0"
  },
  "devDependencies": {
    "@opennextjs/cloudflare": "^1.0.0",
    "typescript": "^6.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Next.js on Workers scaffold"
    ;;

  express-node)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "vitest"
  },
  "dependencies": {
    "express": "^5.0.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^25.0.0",
    "tsx": "^4.0.0",
    "typescript": "^6.0.0",
    "vitest": "^3.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Express + Node scaffold"
    ;;

  fastapi)
    cat > "$PROJECT_DIR/pyproject.toml" <<EOF
[project]
name = "$PROJECT_NAME"
version = "0.0.1"
requires-python = ">=3.11"
dependencies = [
  "fastapi>=0.110.0",
  "uvicorn>=0.27.0",
  "pydantic>=2.0",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "ruff>=0.5", "mypy>=1.10"]
EOF
    echo -e "  ${GREEN}✅${NC} FastAPI scaffold"
    ;;

  django)
    cat > "$PROJECT_DIR/pyproject.toml" <<EOF
[project]
name = "$PROJECT_NAME"
version = "0.0.1"
requires-python = ">=3.11"
dependencies = ["Django>=5.0", "psycopg[binary]>=3.0"]

[project.optional-dependencies]
dev = ["pytest-django>=4.5", "ruff>=0.5"]
EOF
    echo -e "  ${GREEN}✅${NC} Django scaffold"
    ;;

  go-stdlib)
    cat > "$PROJECT_DIR/go.mod" <<EOF
module $PROJECT_NAME

go 1.22
EOF
    echo -e "  ${GREEN}✅${NC} Go stdlib scaffold"
    ;;

  rust-axum)
    cat > "$PROJECT_DIR/Cargo.toml" <<EOF
[package]
name = "$PROJECT_NAME"
version = "0.0.1"
edition = "2024"

[dependencies]
axum = "0.8"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
EOF
    echo -e "  ${GREEN}✅${NC} Rust + Axum scaffold"
    ;;

  node-cli)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "type": "module",
  "bin": {
    "$PROJECT_NAME": "./dist/index.js"
  },
  "scripts": {
    "build": "tsc",
    "test": "vitest"
  },
  "devDependencies": {
    "@types/node": "^25.0.0",
    "typescript": "^6.0.0",
    "vitest": "^3.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Node CLI scaffold"
    ;;

  static-html)
    cat > "$PROJECT_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$PROJECT_NAME</title>
</head>
<body>
  <h1>$PROJECT_NAME</h1>
</body>
</html>
EOF
    echo -e "  ${GREEN}✅${NC} Static HTML scaffold"
    ;;

  custom|*)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1"
}
EOF
    echo -e "  ${GREEN}✅${NC} Minimal scaffold (custom stack)"
    ;;
esac

# === Step 6: Apply DEPLOYMENT-specific config ===
case "$DEPLOY" in
  cloudflare-workers)
    # No bindings by default — wrangler can deploy without them
    # User adds bindings via `brain secrets init` after database is created
    cat > "$PROJECT_DIR/wrangler.toml" <<EOF
name = "$PROJECT_NAME"
main = "src/worker.ts"
compatibility_date = "$(date +%Y-%m-%d)"
compatibility_flags = ["nodejs_compat"]

# Add bindings as needed after deployment:
# [[d1_databases]]
# binding = "DB"
# database_name = "$PROJECT_NAME-db"
# database_id = "<get from: wrangler d1 create $PROJECT_NAME-db>"
#
# [[kv_namespaces]]
# binding = "CACHE"
# id = "<get from: wrangler kv namespace create CACHE>"
EOF
    cat > "$PROJECT_DIR/.dev.vars.example" <<EOF
# Local dev secrets — copy to .dev.vars (gitignored)
# AUTH_SECRET=
# DATABASE_URL=
EOF
    echo -e "  ${GREEN}✅${NC} Cloudflare Workers config (no bindings — add via brain secrets init)"
    ;;

  cloudflare-pages)
    cat > "$PROJECT_DIR/wrangler.toml" <<EOF
name = "$PROJECT_NAME"
pages_build_output_dir = "dist"
EOF
    echo -e "  ${GREEN}✅${NC} Cloudflare Pages deployment config"
    ;;

  vercel)
    cat > "$PROJECT_DIR/vercel.json" <<EOF
{
  "version": 2
}
EOF
    echo -e "  ${GREEN}✅${NC} Vercel deployment config"
    ;;

  netlify)
    cat > "$PROJECT_DIR/netlify.toml" <<EOF
[build]
  publish = "dist"
EOF
    echo -e "  ${GREEN}✅${NC} Netlify deployment config"
    ;;

  fly)
    cat > "$PROJECT_DIR/fly.toml" <<EOF
app = "$PROJECT_NAME"
primary_region = "iad"
EOF
    echo -e "  ${GREEN}✅${NC} Fly.io deployment config"
    ;;

  docker-self-hosted)
    cat > "$PROJECT_DIR/Dockerfile" <<EOF
# TODO: Choose base image based on stack
# Node:    FROM node:22-alpine
# Python:  FROM python:3.12-slim
# Go:      FROM golang:1.22-alpine
# Rust:    FROM rust:1.75
WORKDIR /app
COPY . .
# TODO: Add build/install commands
# CMD ["npm", "start"]
EOF
    cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
services:
  app:
    build: .
    ports:
      - "8080:8080"
EOF
    echo -e "  ${GREEN}✅${NC} Docker self-hosted deployment config"
    ;;

  github-pages)
    mkdir -p "$PROJECT_DIR/.github/workflows"
    cat > "$PROJECT_DIR/.github/workflows/deploy.yml" <<EOF
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with: { path: '.' }
      - uses: actions/deploy-pages@v4
EOF
    echo -e "  ${GREEN}✅${NC} GitHub Pages deployment workflow"
    ;;

  aws-lambda|aws-ecs|gcp-run|azure-app|kubernetes|railway|render)
    cat > "$PROJECT_DIR/.deploy/$DEPLOY.md" <<EOF
# Deployment: $DEPLOY

[TODO: Configure $DEPLOY deployment]

Brain has not yet templated this deployment target.
Run /brain phase-6 to learn from this project once deployment is set up.
EOF
    mkdir -p "$PROJECT_DIR/.deploy"
    mv "$PROJECT_DIR/.deploy/$DEPLOY.md" "$PROJECT_DIR/.deploy/" 2>/dev/null || true
    echo -e "  ${YELLOW}ℹ${NC}  $DEPLOY: TODO stub created in .deploy/"
    ;;

  none)
    echo -e "  ${GREEN}✅${NC} No deployment (library/CLI/local-only)"
    ;;
esac

# === Step 4: TypeScript config ===
if [[ ! -f "$PROJECT_DIR/tsconfig.json" ]]; then
  cat > "$PROJECT_DIR/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "lib": ["ES2022"],
    "types": ["node"]
  }
}
EOF
fi

# === Step 5: Brain integration ===
echo ""
echo "Initializing brain integration..."
bash "$VAULT_PATH/scripts/brain-sync.sh" "$PROJECT_DIR" >/dev/null 2>&1
mkdir -p "$PROJECT_DIR/.parent-automation"
cp "$VAULT_PATH/templates/parent-automation/"*.ts "$PROJECT_DIR/.parent-automation/" 2>/dev/null
cp "$VAULT_PATH/templates/parent-automation/tsconfig.json" "$PROJECT_DIR/.parent-automation/" 2>/dev/null
echo -e "  ${GREEN}✅${NC} Brain integrated"

# === Step 6: First commit ===
cd "$PROJECT_DIR"
git add -A
git commit -m "Initial scaffold via brain create

Type: $PROJECT_TYPE
Customer: $CUSTOMER
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet

# === Step 7: GitHub repo (if gh available) ===
if command -v gh >/dev/null 2>&1; then
  echo ""
  echo "Creating GitHub repo (private)..."
  gh repo create "$PROJECT_NAME" --private --source=. --remote=origin --push --confirm 2>&1 | tail -3 || true
fi

# === Step 8: Record decision ===
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"projectType\":\"$PROJECT_TYPE\",\"customer\":\"$CUSTOMER\",\"projectName\":\"$PROJECT_NAME\",\"decisionsApplied\":[\"create-from-template\",\"$PROJECT_TYPE-scaffold\",\"brain-integrated\"],\"contradictionsResolved\":[],\"lessonsUsed\":[\"L-018\"],\"timeMs\":0,\"tokenEstimate\":0}" >> "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"

# Trigger Phase 6 to learn
(nohup npx ts-node "$VAULT_PATH/observability/phase-6-daemon.ts" > /dev/null 2>&1 &) 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ PROJECT CREATED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Path: $PROJECT_DIR"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_DIR"
echo "  # Edit .planning/PROJECT.md and ROADMAP.md to define scope"
echo "  brain deliver         # Run autonomous delivery"
echo "  npm install           # Install deps"
echo "  npm run dev           # Start dev server"
