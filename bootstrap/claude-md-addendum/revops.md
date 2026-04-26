## Constraints

- **Runtime:** Cloudflare Pages (SPA) + Hono API on Workers/Pages Functions, or full Workers — pick at scaffold and stick with it.
- **Database:** D1 (SQLite) with Drizzle ORM. Tenant-scoped via `tenant_id` on every business table. Migrations authored with `drizzle-kit` and applied via `wrangler d1 migrations apply`.
- **Auth:** Centralized in `src/lib/auth.ts` (or Cloudflare Access + Azure AD JWT for internal-only deployments). Role checks via `requireRole()`.
- **Tenancy:** Multi-tenant from day zero. Every query tenant-scoped through middleware; **never** trust URL- or body-supplied `tenant_id`.
- **Currency:** Money columns end in `_zar` or `_usd`. **Load-bearing for revops** — quotes, deals, commission, invoicing all break silently otherwise. Margin calculations always operate in a single, named currency at a time.
- **Approval flow:** Margin gates and discount thresholds enforced server-side via approval workflow tables; UI cannot bypass.

## Architecture Conventions

- **Tenant on every business table.** Middleware-enforced; never trust user input.
- **RBAC centralised** in `src/lib/rbac.ts` — single source of truth. Route guards use `requireRole(userRole, requiredRole)`.
- **Quote / Pipeline / Deal / Commission / Billing tables** are the operational core. Each carries `tenant_id`, audit columns, and emits typed events on state transitions.
- **Approval workflow** is a first-class table — `approvals(deal_id, requested_by, approver_role, state, decided_at)`. Discount above threshold or margin below floor blocks deal closure until approved.
- **Commission rules** live in code-versioned config or a dedicated `commission_rules` table — never inline magic numbers in compute.
- **Margin gates** evaluated in compute layer (`src/features/deal/compute.ts`) — pure function, unit-tested, never duplicated client-side as authority.
- **Schema-first migrations** via Drizzle. No direct D1 edits.
- **Audit columns** on every business table: `created_at`, `created_by`, `updated_at`, `updated_by`. Hard-delete forbidden on `deals`, `quotes`, `commission_runs`, `invoices`.
- **Event emission on mutation** — quote-created, deal-stage-changed, approval-decided, commission-calculated, invoice-issued.
- **Zod at boundaries.** All inbound API payloads validated at the route boundary.

## RBAC Structure

See `src/lib/rbac.ts` — single source of truth.

Roles: `customer | sales | manager | admin`

All route guards use `requireRole(userRole, requiredRole)`. Never inline role arrays.

## Anti-Patterns

- **Inline role arrays** (`['admin', 'sales'].includes(...)`) — use `requireRole()`.
- **Trusting body-supplied `tenant_id`** — always from authenticated session.
- **Unsuffixed money columns** — `amount` is forbidden; must be `amount_zar` or `amount_usd`. Mixing currencies in one column is silent corruption.
- **Cross-currency arithmetic without an explicit FX-conversion step** — every arithmetic operation must be on a single named currency.
- **Client-side margin gates as authority** — UI may show, but compute layer decides. UI bypass = lost margin.
- **Hard-coded commission percentages** in compute — must come from `commission_rules` or versioned config.
- **Skipping the approval table** for "small" discounts. If thresholds are configurable, all discount paths route through approval; no exceptions.
- **Bypassing Drizzle migrations** — schema drift in revops = revenue defects.
- **Mutable facts in this file** — pipeline counts, deal counts, commission run history belong in `.planning/STATE.md`.
