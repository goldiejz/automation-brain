# Stack & Deployment Decoupling

The brain templates are organized in three independent layers:

```
PROJECT TYPE  →  what the project DOES
STACK         →  what TOOLS it uses
DEPLOYMENT    →  where it RUNS
```

These are independent dimensions. A `service-desk` can run on Cloudflare, AWS, Vercel, or self-hosted Docker. The brain composes the right template by stacking these layers.

## Project Types (domain logic)

| Type | Purpose | Conventions |
|------|---------|-------------|
| `service-desk` | ITIL ticketing | RBAC, tenant scoping, audit columns |
| `revops` | Sales/commission/billing | Currency suffix, approval flows |
| `ops-intelligence` | Dashboards/observability | Aggregation, time-series patterns |
| `marketplace` | Multi-sided platform | Tenancy, payments, escrow |
| `internal-tool` | Single-tenant business app | Lean, no multi-tenancy |
| `cli-tool` | Command-line utility | Args, config, no server |
| `library` | Reusable package | API design, no runtime |
| `static-site` | Marketing/docs | SSG, no backend |
| `custom` | Unclassified | Minimal scaffold |

## Stacks (technical choices)

| Stack ID | Frontend | Backend | DB |
|----------|----------|---------|-----|
| `vite-react-hono` | React 19 + Vite | Hono | D1/Postgres/SQLite |
| `nextjs` | Next.js 16 (App Router) | Next.js API | Postgres |
| `nextjs-on-workers` | Next.js | Cloudflare Workers | D1 |
| `astro` | Astro | Astro endpoints | any |
| `tanstack-start` | TanStack | TanStack | any |
| `express-node` | none / spa | Express | Postgres/Mongo |
| `fastapi` | none / spa | FastAPI | Postgres |
| `django` | Django templates | Django | Postgres |
| `rails` | Rails views | Rails | Postgres |
| `go-stdlib` | none | net/http | Postgres |
| `rust-axum` | none | Axum | Postgres |
| `swift-vapor` | none | Vapor | Postgres |
| `static-html` | plain HTML/CSS/JS | none | none |
| `node-cli` | none | Node CLI | none |

## Deployments (where it runs)

| Deploy ID | Target | Cost | Best For |
|-----------|--------|------|----------|
| `cloudflare-workers` | CF Workers + D1 | low | edge, multi-tenant, low-latency |
| `cloudflare-pages` | CF Pages | low | SPAs, static + functions |
| `vercel` | Vercel | low | Next.js, edge functions |
| `netlify` | Netlify | low | Jamstack |
| `aws-lambda` | AWS Lambda + RDS | mid | enterprise, AWS-locked |
| `aws-ecs` | AWS ECS Fargate | mid | container apps |
| `gcp-run` | Cloud Run | low-mid | container apps, GCP-locked |
| `azure-app` | Azure App Service | mid | Microsoft stack |
| `fly` | Fly.io | low | global edge containers |
| `railway` | Railway | low | simple Node/Python |
| `render` | Render | low | simple SaaS |
| `github-pages` | GH Pages | free | static sites |
| `docker-self-hosted` | Self-hosted | varies | full control |
| `kubernetes` | k8s cluster | high | enterprise scale |
| `none` | No deployment | - | libraries, CLIs |

## Composition Examples

```bash
# Strategix service desk on Cloudflare
ark create acme-sd \
  --type service-desk \
  --stack vite-react-hono \
  --deploy cloudflare-workers

# Same project type but on AWS
ark create acme-sd \
  --type service-desk \
  --stack express-node \
  --deploy aws-ecs

# A simple internal tool
ark create timesheet-tool \
  --type internal-tool \
  --stack nextjs \
  --deploy vercel

# A CLI library — no deployment
ark create my-cli \
  --type cli-tool \
  --stack node-cli \
  --deploy none

# Importing existing — brain detects and proposes
ark align /path/to/existing-project
# → Detects: package.json with Next.js 16
# → Proposes: --type internal-tool --stack nextjs --deploy vercel
# → Asks: confirm or override?
```

## How brain selects defaults

When `--stack` or `--deploy` is omitted:

1. **Detect from package.json/Cargo.toml/etc.** if files exist
2. **Apply lessons** — what does the brain know works for this type?
3. **Ask the user** if ambiguous (CLI prompts, or in Claude Code via skill)
4. **Default to least-locked-in option** if nothing else applies (e.g., `docker-self-hosted` over `aws-lambda`)

## Migration path

Existing projects (Strategix repos) are NOT changed. They remain Cloudflare-targeted via their existing wrangler.toml.

New projects choose their stack/deploy independently of project-type. The brain's cached templates apply convention-level guidance regardless of stack:
- RBAC centralization works in any framework
- Currency suffix discipline works in any DB
- Tenant scoping works in any auth layer
- Route/compute split works in any router

## Adding a new stack or deployment

```bash
# Add Rust + Axum stack
mkdir -p ~/vaults/ark/templates/stacks/rust-axum
# Add files: Cargo.toml.tmpl, src/main.rs.tmpl, README.md (purpose + conventions)
# Ark create will pick it up by name automatically.

# Add Hetzner Cloud deployment
mkdir -p ~/vaults/ark/templates/deployments/hetzner
# Add files: deploy.sh.tmpl, server-setup.md, README.md
# Reference in STACKS.md.
```

The vault automatically learns successful combinations via Phase 6 — if 3 projects use `nextjs + vercel`, it becomes the suggested default for that type.
