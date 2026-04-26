---
project_type: revops
source_project: strategix-revops
template_version: 1.0
created: 2026-04-25
default_stack: vite-react-hono
default_deploy: cloudflare-workers
keywords: revops, rev ops, revenue operations, crm, quotes, quoting, pipeline, opportunity, opportunities, deal, deals, commission, commissions, billing, invoicing, margin, approval, approvals, sales pipeline, account management, contract, contracts, renewal, renewals
---

# RevOps (Commercial Operations) Project Bootstrap Template

**Example:** Strategix RevOps Platform (quotes, pipeline, margin, commission, billing)

## Project Section

**Structure:**
```
[Your Project Name] — [commercial operations domain]
[Role in platform programme]
```

**Template:**
```
Strategix RevOps Platform — the commercial half of the Strategix 
internal platform programme. Sibling system is `strategix-ioc` (operational half).
```

## Purpose Section

**Key elements:**
1. What spreadsheet-driven process does this replace?
2. What audit/policy enforcement does it add?
3. What key-person dependency does it reduce?

**Template:**
```
Replace spreadsheet-driven commercial operations with a governed, auditable 
platform that makes commercial work less dependent on [key person]. The job 
is not "be a CRM" — it's to be the source of truth for ordinary commercial 
workflow, with explicit rules and an audit trail.
```

**Core value statement:**
```
[Revenue stream] flows through one authoritative system with policy enforced 
at the platform layer rather than as memory or chat. Finance signs off without 
rebuilding outputs elsewhere.
```

## Scope Section

**Phase 1 typical scope:**
- Standard quote issuance
- Weighted pipeline
- Governed pricing (rate cards + discount curves)
- Margin approval workflow
- Commission calculation + backtest
- Account/client 360
- Billing/metering
- Finance reporting

**Structure:**
```
[Domain feature list]. Specific currently-shipped state lives in `.planning/STATE.md`.

Example for commercial ops:
- Standard quote issuance
- Weighted pipeline  
- Governed pricing (rate cards + commitment discount curves)
- Platform-routed margin approval
- Commission calculation + backtest
- Account/client 360 view
- Billing/metering integration
- Finance reporting
```

## Out of Scope Section

**RevOps typical deferrals:**
- Multi-currency (single currency by design)
- Multi-tenancy (single-tenant, internal)
- Public-facing customer portal
- Replacement for PSA/ticketing (different domain)
- Director-level deal exceptions (remain human-gated)

## Constraints Section

**Essential constraints for RevOps:**
1. Runtime: Cloudflare Pages (SPA) + Workers Functions
2. Auth: Azure AD SSO via Cloudflare Access
3. Database: D1 (SQLite)
4. Currency: Single currency by design (e.g., ZAR only)
5. Tenancy: Single-tenant, internal use only
6. No origin server, edge-only deployment

**Template:**
```
- **Auth:** Cloudflare Access (Azure AD SSO). JWT validation via `jose`. 
  No password auth in app.
- **Edge-only:** Cloudflare Pages (React SPA) + Workers Functions (Hono) + 
  D1 (SQLite). No origin server, no Node runtime in prod.
- **[Currency] throughout:** `_[currency]` suffix on financial columns.
- **D1 limits:** 100 bound parameters per query; no native BOOLEAN/DATETIME; 
  JSON stored as TEXT; FK target validation at CREATE TABLE time.
```

## Architecture Conventions Section

**Critical conventions:**
1. Schema-first (d1/schema.sql canonical)
2. Currency suffix (_zar, _usd, etc.)
3. UUID for domain rows, AUTOINCREMENT for logs
4. RBAC in middleware, never in routes
5. Field-level shaping (hide cost/margin from sales role)
6. Range validation at both layers (handler + schema CHECK constraint)
7. Audit every mutation (write to audit_log table)

**Template:**
```
- **Schema-first.** `d1/schema.sql` is canonical. Every change ships as 
  a numbered migration. Never edit prod D1 directly.
- **Currency suffix.** All financial columns end in `_[currency]`.
- **UUID + AUTOINCREMENT.** UUIDs for domain rows; AUTOINCREMENT for logs.
- **RBAC in middleware.** `requireRole()` from `functions/api/middleware/rbac.ts`. 
  Never inline role checks.
- **Field-level shaping.** `shapeQuoteForRole()` strips cost/margin fields. 
  `SELECT *` to a sales user is a bug.
- **Range validation at both layers.** Handler validation + schema CHECK constraint.
- **Audit every mutation.** Sensitive routes write to `audit_log`.
```

## Completion Language Section

**RevOps uses:**
- **code-closed:** Implementation + tests pass
- **alpha-testable:** Exposed to Alpha user group
- **alpha-proven:** Alpha user group runs real workflow without fallback to Excel/spreadsheets

**Template:**
```
Every change distinguishes three states:
- **code-closed**: Implementation + tests pass
- **alpha-testable**: Exposed to Alpha user group
- **alpha-proven**: Alpha user runs real workflow without fallback to manual process
```

## Key Local Anti-Patterns

To prevent:
1. Calling A3/A4/A5 "done" because code shipped (they're code-closed; Alpha proof is separate)
2. Saying "Excel is gone" before Alpha user group measured against side-channel use
3. Editing prod D1 directly (even schema-only changes need migration)
4. `INSERT INTO __new SELECT * FROM old` in table-recreate migrations (always list columns explicitly)
5. Hardcoding business policy (use DB-backed rule path instead)
6. Adding routes without RBAC middleware or audit on mutations
7. Running manual staging deploy from developer workstation (use CI job only)
8. Using vault docs as authoritative truth instead of `.planning/STATE.md`

## Vault Structure

**Canonical locations:**
- Code vault: `Strategix-MSP/strategix-revops` (renamed from strategix-crm 2026-04-18)
- Docs vault: `Strategix-MSP/strategix-revops-docs` (local: `~/vaults/strategix-crm/` by convention)

## Bootstrap Checklist for New RevOps Project

- [ ] **Repo created** with Pages-compatible config
- [ ] **CLAUDE.md** customized for your commercial domain
- [ ] **.planning/STATE.md** with empty counts
- [ ] **.planning/PROJECT.md** with durable purpose + scope
- [ ] **.planning/ROADMAP.md** with phase breakdown
- [ ] **AUTONOMY.md** with safe zones, blocked zones
- [ ] **tasks/lessons.md** starter
- [ ] **tasks/todo.md** starter  
- [ ] **d1/schema.sql** with canonical schema
- [ ] **functions/api/middleware/rbac.ts** with role constants
- [ ] **wrangler.toml** and **wrangler.staging.toml** configured
- [ ] **D1 database** created
- [ ] **Auth path** wired (Azure AD SSO via Cloudflare Access)
- [ ] **First route** (route → handler → compute) implemented
- [ ] **Tests** present (Vitest, 80%+ coverage)
- [ ] **CI job** in `.github/workflows/ci.yml` (security audit → typecheck → test → build)
- [ ] **Audit logging** on sensitive mutations

## When to Use This Template

✅ Building a commercial operations system (quotes, pipeline, margin, commission)
✅ Azure AD SSO required
✅ Single-currency, single-tenant
✅ Finance/sales workflows
✅ Need audit trail on all mutations

❌ Not for service desk (use service-desk-template)
❌ Not for operations intelligence (use ops-intelligence-template)
❌ Not for multi-tenant platforms (this is single-tenant by design)
❌ Not for public-facing portals
