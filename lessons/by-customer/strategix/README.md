# Strategix Lessons

Lessons captured from Strategix projects (strategix-crm, strategix-ioc, strategix-servicedesk).

## Strategix Project Map

| Project | Type | Lessons | Phase | Status |
|---------|------|---------|-------|--------|
| strategix-crm | RevOps platform | L-001...L-009 | P1 | Shipped |
| strategix-ioc | Ops intelligence | L-010...L-016 | P1 | Shipped |
| strategix-servicedesk | Service desk | L-017...L-023 | P1 | Shipped |

## Navigation

- **RBAC & Auth:** [[strategix-L-018]] — Centralized RBAC, inline role arrays forbidden
- **Schema & Migration:** [[strategix-L-021]], [[strategix-L-022]] — Column suffixes, migration coordination
- **Shell & Affordance:** [[strategix-L-020]], [[strategix-L-023]] — Rebuild costs, consistency
- **Testing & Coverage:** [[strategix-L-005]], [[strategix-L-015]] — 80%+ coverage, TDD discipline
- **Truth & Contradiction:** [[strategix-L-012]], [[strategix-L-013]] — STATE.md primacy, doc/code drift

## Lesson Status

**Applied across all three projects:** 23 lessons captured
**Effective (preventing violations):** 19/23 (83%)
**Pending review:** 4/23 (need effectiveness re-assessment after 6 weeks)

## Cross-Customer Application

- L-018 (RBAC): Expected to apply universally (flagged `universal: true`)
- L-020 (affordance): May vary by stack (Cloudflare Workers vs Pages)
- L-021 (column suffixes): Should apply universally
- L-023 (timesheet auditing): Service-desk specific, not universal

---

*Strategix lesson collection established 2026-04-25*
