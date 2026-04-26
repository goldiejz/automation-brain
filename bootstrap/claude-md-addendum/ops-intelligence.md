## Constraints

- **Runtime:** Next.js App Router on Cloudflare Workers via `@opennextjs/cloudflare` (preferred) — strict `route.ts` / `compute.ts` split. Or vanilla Workers if no SSR is needed.
- **Database:** D1 (SQLite) for relational + KV for hot snapshots. Drizzle ORM for D1. Tenant-scoped via `tenant_id` on every business table.
- **Auth:** Auth.js v5 with D1 sessions, or Cloudflare Access + Azure AD for internal-only. Role checks via `requireRole()` from `src/lib/auth-guards.ts`.
- **Cron worker:** External-API pulls (HaloPSA, N-central, RMM, monitoring) run from a **separate** `cron-worker/` deployment with its own `wrangler.toml`. The dashboard Worker never makes outbound calls to third-party APIs at request time.
- **Tenancy:** Multi-tenant from day zero. Every query tenant-scoped via middleware; **never** trust body- or URL-supplied `tenant_id`.
- **Currency / Duration:** Money columns end in `_zar` or `_usd`. SLA / dwell / response duration columns end in `_minutes` or `_seconds`. Never unsuffixed.

## Architecture Conventions

- **Tenant on every business table.** Middleware-enforced.
- **RBAC centralised** in `src/lib/auth-guards.ts` (or `src/lib/rbac.ts`) — single source of truth. Route guards use `requireRole(userRole, requiredRole)`.
- **`route.ts` / `compute.ts` split.** Route files own HTTP / Next.js concerns only; compute files own business logic and are unit-tested.
- **KPI snapshot tables** are the dashboard's source of truth — `kpi_<source>_snapshots(tenant_id, captured_at, payload_json, source_version)`. Dashboard reads snapshots; never live-queries upstream APIs.
- **External-API pulls run in cron-worker only.** Dashboard reads snapshots; cron-worker writes them. This isolates rate limits, retries, and outbound credentials from the request path.
- **SLA windows are computed in compute layer** as pure functions over snapshot timestamps + policy config. No database triggers, no duplicated logic.
- **Schema-first migrations** via Drizzle. `wrangler d1 migrations apply strategix-<db-name> --remote` is required and may need manual run if CI token scope is incomplete.
- **Audit columns** on every business table: `created_at`, `created_by`, `updated_at`, `updated_by`.
- **Zod at boundaries.** All inbound API payloads validated.

## RBAC Structure

See `src/lib/auth-guards.ts` (or `src/lib/rbac.ts`) — single source of truth.

Roles: `viewer | analyst | manager | admin`

All route guards use `requireRole(userRole, requiredRole)`. Never inline role arrays.

## Anti-Patterns

- **Inline role arrays** (`['admin', 'analyst'].includes(...)`) — use `requireRole()`.
- **Trusting body-supplied `tenant_id`** — always from authenticated session.
- **Unsuffixed money / duration columns** — `_zar`/`_usd`/`_minutes`/`_seconds` are mandatory.
- **Ad-hoc external API pulls outside cron-worker.** Dashboard request paths must not call HaloPSA, N-central, or any third-party API directly. Outbound = cron-worker. Inbound = snapshot read.
- **Live-querying upstream APIs from a dashboard route** — guarantees rate-limit fan-out, latency spikes, and credential leakage into request scope.
- **Mixing `route.ts` and `compute.ts` concerns** — compute must remain pure and testable.
- **Hard-coded SLA thresholds** in compute — must come from policy config or a `sla_policies` table.
- **Bypassing Drizzle migrations** — schema drift in ops-intel = false alarms or missed ones.
- **Mutable facts in this file** — KPI counts, snapshot recency, alert backlog belong in `.planning/STATE.md`.
