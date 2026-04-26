---
project_type: ops-intelligence
source_project: strategix-ioc
template_version: 1.0
created: 2026-04-25
default_stack: nextjs-on-workers
default_deploy: cloudflare-workers
keywords: ops intelligence, ops dashboard, msp dashboard, monitoring, monitoring dashboard, observability, n-central, halopsa, kpi, kpis, sla dashboard, technician workload, incident dashboard, client health, operations dashboard, executive dashboard, status board, network monitoring
---

# Operations Intelligence (OpsInt / IOC) Project Bootstrap Template

**Example:** Strategix IOC (Intelligence Operations Center — signal correlation, advisories, operator workflows)

## Project Section

**Structure:**
```
[Your Project Name] — [operational intelligence role]
[Destination aspiration; note current stage honestly]
```

**Template:**
```
Strategix IOC (Intelligence Operations Center) — the operational half 
of the Strategix internal platform programme. Sibling system is `strategix-revops` 
(commercial half).

Today the job is to [current objective]. [Future destination]; current language 
must stay honest about what is shipped vs what is positioned.
```

## Purpose Section

**Key elements:**
1. What operator pain does this solve? (missed alerts, bad triage, slow recognition)
2. What's the core value? (signal correlation, early warning, classification)
3. What dependency on key operators does it reduce?

**Template:**
```
Operational intelligence platform evolving toward [destination] — not yet there. 
Today the job is to [current objectives]. The originating pain is [specific 
operator workflow gap].

Core value: [Know about problem before client does / Reduce MTTR / etc.] 
through correlated cross-source signals, not through one operator's instinct.
```

## Scope Section

**Phase 1 typical scope:**
- Cross-source event ingestion + live correlation (2-3 connectors)
- Advisory AI batch analysis (nightly, not real-time)
- Weekly relevance tuning from operator feedback
- Runtime rule enable/disable + per-rule confidence tuning (RBAC-enforced)
- Wall/desktop/mobile consumption surface
- Operator ack/dismiss + audit log

**Structure:**
```
[Current-stage feature list]. Specific counts (connectors, rules, tables) 
live in `.planning/STATE.md`.

Example:
- Cross-source event ingestion + correlation (HaloPSA + N-central live)
- Advisory AI batch analysis (nightly Claude run)
- Weekly relevance tuning from operator feedback
- Runtime rule enable/disable + confidence tuning (RBAC-enforced)
- Wall/desktop/mobile consumption surface
```

## Out of Scope Section

**OpsInt typical deferrals:**
- Autonomous AIOps (no closed-loop write-back, no self-healing)
- Predictive SLA breach detection (no ground-truth reconciliation)
- Runtime editing of rule logic (requires code deploy)
- Promotion of lessons into rules without deploy
- Client-facing portal or multi-tenant operator separation
- Replacement for vendor consoles (aggregates and correlates)

**Honest language rules:**
- Never use "AIOps" for current stage (say "advisory analysis" instead)
- Never claim "99.9% intelligence accuracy" (mixes prediction + signal-action rates)
- Don't expand connectors before improving signal quality on current ones

## Constraints Section

**Essential constraints:**
1. Runtime: Next.js on Cloudflare Workers via `@opennextjs/cloudflare`
2. Auth: Hybrid (Credentials + bcrypt with D1 sessions + Cloudflare Access SSO)
3. Database: D1 with Drizzle, KV for caching
4. Wall-clock limit: ~30s per request (keep retry budgets ≤ 5s/attempt)
5. Cron worker: Separate deployment for long-running tasks
6. Connector pattern: Non-CF-proxied URLs with Host header override
7. D1 migrations: Manual apply (CI token scope incomplete)

**Template:**
```
- **Auth:** Hybrid Auth.js (Credentials + bcrypt) with D1-backed sessions, 
  plus Cloudflare Access SSO. JWT verification via `jose`.
- **Platform:** Next.js 16 on Cloudflare Workers via `@opennextjs/cloudflare`, 
  D1, KV.
- **HaloPSA host header:** `servicedesk.strategix.co.za` is CF-proxied — 
  requests must target `HALO_API_URL` with `Host` header set to tenant URL.
- **D1 migrations:** Applied manually via `npx wrangler d1 migrations apply 
  [db-name] --remote` (CI token scope incomplete; see deploy.yml fallback).
- **Worker wall-clock:** ~30s limit — keep retry budgets ≤ 5s per attempt; 
  cron handles longer outages.
```

## Architecture Conventions Section

**Critical conventions:**
1. Compute/route split (route.ts for HTTP, compute.ts for logic)
2. RBAC centralized (auth-guards.ts, never inline role arrays)
3. Event emission (ConnectorEvent → event-pipeline.ts)
4. Connector pattern (non-CF-proxied URL + Host header)
5. Cron worker separate deployment
6. Drizzle owns schema + queries
7. No lint blocking (typecheck + test + build are gates)

**Template:**
```
- **Compute/route split.** API routes separate `route.ts` (HTTP surface) 
  from `compute.ts` (business logic).
- **RBAC.** All role constants in `src/lib/auth-guards.ts`. Never define 
  local role arrays.
- **Event emission.** Connectors emit `ConnectorEvent` to 
  `onEventsReceived()` in `src/services/event-pipeline.ts`.
- **Connector pattern.** Fetch via non-CF-proxied URL; override `Host` 
  to tenant URL.
- **Cron worker.** Separate deployment in `cron-worker/`. Deploy with 
  `cd cron-worker && npx wrangler deploy`.
- **Drizzle.** Owns schema + queries. `drizzle-kit` for migrations.
- **No lint blocking.** Lint is advisory; typecheck + test + build are gate.
```

## Completion Language Section

**OpsInt uses four honest stages:**
- **technical foundation:** Code lands, tests pass, runs in prod
- **workflow adoption:** Operators use it as primary surface
- **operational improvement:** Pre/post metrics show real change on target incident classes
- **destination-stage aspiration:** Reserve for future (avoid AIOps language in Phase 1)

**Template:**
```
Every change distinguishes four stages:
- **technical foundation**: Code lands, tests pass, runs in production
- **workflow adoption**: Operators use it as primary surface (not fallback)
- **operational improvement**: Pre/post metrics show real change on target incidents
- **destination-stage aspiration**: Future only; honest about current stage
```

## Key Local Anti-Patterns

To prevent:
1. Calling current capability "AIOps" or claiming closed-loop autonomy (say "advisory analysis")
2. Using "99.9% intelligence accuracy" anywhere
3. Expanding connectors before improving signal quality on live connectors
4. Adding routes without `requireRole` and without `withAudit`
5. Defining role arrays inline in routes
6. Treating Drizzle migrations as optional
7. Not updating in-app changelog (`src/lib/changelog.ts`) for operator-visible changes
8. Using vault docs as authoritative truth

## Vault Structure

**Canonical locations:**
- Code vault: `Strategix-MSP/strategix-ioc` (local: `~/code/strategix-ioc/`)
- Docs vault: `Strategix-MSP/strategix-ioc-docs` (local: `~/vaults/strategix-ioc/`)

## Bootstrap Checklist for New OpsInt Project

- [ ] **Repo created** with Next.js worker config
- [ ] **CLAUDE.md** customized for your ops domain
- [ ] **.planning/STATE.md** with empty counts
- [ ] **.planning/PROJECT.md** with durable purpose + honest stage language
- [ ] **.planning/ROADMAP.md** with phase breakdown
- [ ] **AUTONOMY.md** with safe zones, blocked zones
- [ ] **tasks/lessons.md** starter
- [ ] **tasks/todo.md** starter
- [ ] **src/db/schema.ts** with connector events + rules tables
- [ ] **src/lib/auth-guards.ts** with role constants (no inline arrays)
- [ ] **src/services/event-pipeline.ts** wired
- [ ] **src/lib/changelog.ts** wired (for operator-visible changes)
- [ ] **cron-worker/** subproject created
- [ ] **Connectors** (2-3 initial sources) implemented
- [ ] **Rules engine** (eval + signal lifecycle) wired
- [ ] **Operator surface** (ack/dismiss + audit) wired
- [ ] **Tests** present (Vitest, 80%+ coverage on signal path)
- [ ] **D1 database** created
- [ ] **Auth path** wired (Credentials + D1 sessions + Cloudflare Access)
- [ ] **KV cache** configured for rule metadata
- [ ] **CI** in `.github/workflows/` (typecheck → test → build)

## When to Use This Template

✅ Building an operations intelligence platform (signal aggregation, correlation, advisories)
✅ Operator-facing (internal ops team)
✅ Multiple data sources (connectors)
✅ Need audit trail on every ack/dismiss
✅ Batch analysis or lightweight real-time evaluation

❌ Not for service desk (use service-desk-template)
❌ Not for commercial ops (use revops-template)
❌ Not claiming "AIOps" or closed-loop autonomy in Phase 1
❌ Not for customer-facing insights (internal use)

## Honest Positioning Rules

**Do use this language:**
- "Advisory analysis" (current stage: manual operator review of AI suggestions)
- "Signal correlation" (aggregating events from multiple sources)
- "Operator decision support" (we recommend; operator decides)

**Don't use this language in Phase 1:**
- "AIOps" (reserved for closed-loop automation; we're not there)
- "Autonomous remediation" (we don't write back to source systems)
- "99.9% detection accuracy" (imprecise, mixes prediction + action success)
- "Predictive SLA breach" (no ground-truth reconciliation yet)
