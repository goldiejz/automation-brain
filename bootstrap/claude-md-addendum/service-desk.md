## Constraints

- **Runtime:** Cloudflare Workers (Vite plugin + Static Assets) or Pages, depending on deploy target.
- **Database:** D1 (SQLite) with Drizzle ORM. Tenant-scoped via `tenant_id` on every business table. Migrations authored with `drizzle-kit` and applied via `wrangler d1 migrations apply`.
- **Auth:** Centralized in `src/lib/auth.ts` (better-auth or equivalent). Role checks via `requireRole()`. Session cookie + CSRF on state-changing routes.
- **Tenancy:** Multi-tenant from day zero. Every query tenant-scoped through middleware; **never** trust URL- or body-supplied `tenant_id`.
- **Currency:** Money columns end in `_zar` or `_usd`. Duration columns end in `_minutes` or `_seconds`. Never unsuffixed.
- **Event surface:** Cloudflare Queues for internal event bus. Ticket/time-entry/timesheet mutations emit typed events.

## Architecture Conventions

- **Tenant on every business table.** Middleware-enforced; never trust user input.
- **RBAC centralised** in `src/lib/rbac.ts` — single source of truth for role arrays. Route guards use `requireRole(userRole, requiredRole)`.
- **Route / compute split.** API routes separate HTTP surface (`route.ts`) from business logic (`compute.ts`). Routes thin, compute testable.
- **Schema-first migrations** via Drizzle. SQL migrations generated, applied via `wrangler d1 migrations apply`. No direct D1 edits.
- **Audit columns** on every business table: `created_at`, `created_by`, `updated_at`, `updated_by`.
- **Soft delete** on tickets/timesheets/time-entries; hard delete forbidden.
- **Event emission on mutation** — typed events to Cloudflare Queues. Integrations subscribe; core logic does not depend on integration presence.
- **Customer portal is a distinct RBAC surface.** `/portal` routes always `requireRole('customer')` and tenant-scope against the customer's linked client. A staff user visiting `/portal` gets 403.
- **Signature sign-off is evidential.** Customer timesheet approval captures signature image + timestamp + IP + tenant/customer/timesheet IDs. Audit artifact, never deleted.
- **Zod at boundaries.** All inbound API payloads validated with Zod at the route boundary.

## RBAC Structure

See `src/lib/rbac.ts` — single source of truth.

Roles: `customer | staff | manager | admin`

All route guards use `requireRole(userRole, requiredRole)`. Never inline role arrays.

## Anti-Patterns

- **Inline role arrays** (`['admin', 'staff'].includes(...)`) — use `requireRole()`.
- **Trusting body-supplied `tenant_id`** — always from authenticated session. Cross-tenant leak otherwise.
- **Unsuffixed money columns** (`amount` instead of `amount_zar`).
- **Customer portal calling staff APIs.** `/portal` calls `/portal/*` only.
- **Hard-deleting signature sign-off artifacts** — evidential, retention rules apply.
- **Bypassing Drizzle migrations** — any schema change without a generated migration is drift.
- **Calling code-shipped "production-ready"** without staging verification and ALPHA gate closure.
- **Skipping `tasks/lessons.md`** — past lessons must apply.
- **Mutable facts in this file** — counts, deploy posture, shipped-feature checklists belong in `.planning/STATE.md`.
