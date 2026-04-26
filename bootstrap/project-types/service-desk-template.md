---
project_type: service-desk
source_project: strategix-servicedesk
template_version: 1.0
created: 2026-04-25
default_stack: vite-react-hono
default_deploy: cloudflare-workers
keywords: service desk, helpdesk, help desk, ticket, tickets, ticketing, sla, slas, itil, incident, incidents, problem management, change management, msp, managed service, customer support, technician, engineer workload, timesheet, sign-off, helpdesk platform
---

# Service Desk Project Bootstrap Template

**Example:** Strategix Service Desk (ITIL-aligned group service desk + observed-time timesheets)

## Project Section

**Structure:**
```
[Your Project Name] — [one-sentence role in the platform programme]
[Relationship to sibling systems]
```

**Template:**
```
Strategix Service Desk — the group-wide service desk + timesheet platform. 
Third platform in the Strategix internal platform programme alongside 
`strategix-revops` (commercial half) and `strategix-ioc` (operational half).
```

## Purpose Section

**Key elements:**
1. What pain does this solve? (observed-time, honest timesheets, etc.)
2. What's the core value? (time capture, customer sign-off, billing accuracy)
3. What department/role dependency are you reducing?

**Template:**
```
Replace the segmented service desk estate with one group-wide, ITIL-aligned 
service desk that produces accurate, customer-approved timesheets with minimal 
engineer overhead. The originating pain is that timesheet reporting is 
retrospective and memory-driven; this platform inverts that by making time 
capture structured, observable, and customer-signed-off.
```

## Scope Section

**Required structure:**
- One-sentence current scope summary
- Explicit ticket type list (e.g., "Incident only in Phase 1")
- Hierarchy statement (if applicable): "Client → Project → Ticket"
- Feature list per category
- Reference to `.planning/STATE.md` for live counts

**Phase 1 typical scope:**
- One ticket type (Incident)
- Status lifecycle + SLA timers
- Projects as first-class (Client → Project → Ticket)
- Structured time capture (timer + manual + activity dwell)
- Weekly timesheets with customer sign-off
- Role-default dashboards (Engineer, Manager)
- Report export (CSV + PDF)
- Customer portal (self-serve submission + status + approval)
- Multi-tenant isolation (2+ seed tenants)
- Webhook-out admin surface (integration proof)

## Out of Scope Section

**Phase 1 explicitly defers:**
- Azure AD SSO / M365 integration (Phase 2)
- Calendar-driven time proposal (Phase 2)
- Email-to-ticket ingestion (Phase 1.5)
- ITIL types beyond Incident (Phase 2: Service Request, Change, Problem)
- CMDB, asset management, knowledge base (Phase 2+)
- Real integrations to sibling systems (Phase 3)
- Report builder, scheduled reports (Phase 1.5)
- Widget library, drag-drop dashboards (Phase 2)
- Production operational posture (Phase 2+)
- Multi-tenant custom domains (Phase 2)

**Template for deferral:**
```
- [Feature]. Deferred to [Phase]. [Reason if non-obvious].
- ...
```

## Constraints Section

**Essential constraints:**
1. Runtime substrate (Cloudflare Workers, D1, Framework)
2. Auth mechanism (better-auth, Cloudflare Access, etc.)
3. Tenancy model (multi-tenant from day zero or single-tenant)
4. Currency handling (ZAR, USD, multi-currency?)
5. API rate limits / wall-clock limits (~30s for Workers)
6. Frontend framework (React 19 + Vite + shadcn/ui)
7. Event surface (Cloudflare Queues, webhook-out)

**Template:**
```
- **Runtime:** Cloudflare Workers via Hono + Vite. Wall-clock limit ~30s.
- **Database:** D1 (SQLite) with Drizzle ORM. One D1 database, tenant-scoped.
- **Auth:** [Mechanism] with session cookie; CSRF on state-changing routes.
- **Tenancy:** Multi-tenant from day zero. Middleware-enforced scoping.
- **Currency:** ZAR primary, USD secondary. Suffixed columns (_zar, _usd).
- **Frontend:** React 19 + Vite + Tailwind v4 + shadcn/ui.
- **Event surface:** Cloudflare Queues for internal event bus.
```

## Architecture Conventions Section

**Critical conventions (no exceptions):**
1. Tenant on every table (multi-tenant enforcement)
2. RBAC centralized (src/lib/rbac.ts, never inline role arrays)
3. Route/compute split (route.ts for HTTP, compute.ts for logic)
4. Schema-first migrations (Drizzle-driven, numbered)
5. Currency suffix on financial columns
6. Audit columns or audit logs on mutations
7. Event emission on state changes
8. Feature-folder organization (src/features/<feature>/)
9. Zod validation at boundaries
10. Soft-delete on mutable tables (deleted_at, not hard delete)

**Template:**
```
- **Tenant on every table.** Every query is tenant-scoped via middleware.
- **RBAC centralised.** All roles in `src/lib/rbac.ts`. Route guards via `requireRole()`.
- **Route/compute split.** HTTP surface in `route.ts`; logic in `compute.ts`.
- **Schema-first migrations.** Drizzle definitions own source of truth.
- **Currency suffix.** All financial columns end `_zar` or `_usd`.
- **Audit columns on mutations.** `created_at`, `created_by`, `updated_at`, `updated_by`.
- **Event emission on mutations.** Every ticket/time/timesheet change emits event.
- **Feature-folder org.** `src/features/<feature>/` contains routes, compute, UI.
- **Zod at boundaries.** All inbound payloads validated; outbound events typed.
- **Soft-delete.** No hard deletes on `tickets`, `time_entries`, `timesheets`.
```

## Completion Language Section

**Service Desk uses:**
- **code-landed:** Merged to main, tests pass
- **staging-deployed:** Running on staging Worker with seed data
- **pitch-verified:** Demo executes end-to-end without errors

**Template:**
```
Every change states which stage it achieves:
- **code-landed**: Implementation + tests pass
- **staging-deployed**: Exposed to demo/staging environment
- **pitch-verified**: Demo arc runs without errors
- **operationally-ready**: Not in Phase 1; explicitly out of scope
```

## Key Local Anti-Patterns

To prevent:
1. Claiming "production-ready" when you mean "pitch-ready"
2. Trusting body-supplied `tenant_id` (use authenticated session)
3. Inline role arrays in routes (use requireRole() from centralized RBAC)
4. Customer portal calling staff APIs (use portal-safe endpoints)
5. Signature artifacts being deletable (audit-only, never soft-delete)
6. Bundling unrelated cleanup into feature changes
7. Using vault docs as truth instead of `.planning/STATE.md`
8. Bypasssing Drizzle migrations for schema changes

## Vault Structure

**Canonical locations:**
- Code vault: `Strategix-MSP/strategix-servicedesk` (local: `~/code/strategix-servicedesk/`)
- Docs vault: `Strategix-MSP/strategix-servicedesk-docs` (local: `~/vaults/strategix-servicedesk/`)

**Planning docs required:**
- `.planning/STATE.md` — live state (table counts, route counts, test counts, features shipped)
- `.planning/PROJECT.md` — durable purpose and scope
- `.planning/ROADMAP.md` — phase sequencing
- `.planning/ALPHA.md` — pitch-ready gate definition
- `.planning/REQUIREMENTS.md` — mandatory requirements with evidence
- `tasks/lessons.md` — captured corrections
- `tasks/todo.md` — active backlog
- `AUTONOMY.md` — Hermes execution contract

## Bootstrap Checklist for New Service Desk Project

- [ ] **Repo created** with standard `.gitignore`, `package.json`, `tsconfig.json`
- [ ] **CLAUDE.md** from this template, customized for your domain
- [ ] **.planning/STATE.md** with empty counts (will populate as you build)
- [ ] **.planning/PROJECT.md** with durable purpose
- [ ] **.planning/ROADMAP.md** with phase breakdown
- [ ] **AUTONOMY.md** with safe zones, blocked zones, completion language
- [ ] **tasks/lessons.md** starter (header only)
- [ ] **tasks/todo.md** starter (header only)
- [ ] **src/db/schema.ts** with tenant-first table design
- [ ] **src/lib/rbac.ts** with role constants (no inline arrays in routes)
- [ ] **src/features/** folder structure (one per main feature)
- [ ] **D1 database** created + first migration committed
- [ ] **Auth mechanism** wired (better-auth for this template)
- [ ] **Cloudflare Queues** event bus configured
- [ ] **First route** implemented (route.ts + compute.ts split)
- [ ] **Tests** present (80%+ coverage of compute layer)
- [ ] **Docs vault** created (optional but recommended)

## When to Use This Template

✅ Building a service desk platform (tickets + timesheets + multi-tenant)
✅ Deploying to Cloudflare (Workers + D1)
✅ Need ITIL alignment (incidents, service requests, problems)
✅ Customer-facing portal required
✅ Observed-time capture needed

❌ Not for CRM/RevOps (use revops-template instead)
❌ Not for operations intelligence (use ops-intelligence-template instead)
❌ Not for origin-server runtime (Workers-only constraint)
