# Findings — Cross-Project Audit Results

Findings ingested from all projects' tasks/gemini-audits/findings/ and signal bundles, classified by scope and synthesized for cross-project patterns.

## Structure

- **by-customer/** — Findings organized by customer
  - `strategix/` — Findings from all three Strategix projects
  - `customerA/` — Placeholder for future customer A
  - `customerB/` — Placeholder for future customer B

- **[scope]/** — Findings classified by issue type
  - `schema-drift/` — Schema/migration problems (D-001, D-002, etc.)
  - `rbac-lockout/` — Role-based access control violations (relates to L-018)
  - `affordance-drift/` — Shell rebuild / interface consistency (relates to L-020)
  - `contradiction/` — Doc/code misalignment
  - `test-coverage/` — Missing or insufficient test coverage

- **summary-by-date.md** — Weekly synthesis across all customers
  - "Week of 2026-04-21: 3 RBAC findings, 2 schema drifts, 1 affordance issue → recommendations"
  - "Trends: RBAC violations declining (L-018 uptake working), affordance drift increasing (need L-020 refresh)"

## Finding Lifecycle

1. **Generated:** Agent audit produces finding (per-repo tasks/gemini-audits/findings/)
2. **Indexed:** Finding is ingested into brain (async, weekly)
3. **Classified:** Assigned scope (schema, RBAC, affordance, etc.)
4. **Cross-referenced:** Linked to relevant L-NNN entries
5. **Tracked:** Update lesson-effectiveness.md (is L-018 reducing RBAC findings?)
6. **Synthesized:** Weekly summary identifies patterns, trends, meta-recommendations

## Querying

- **By customer:** Navigate `by-customer/[strategix|customerA|customerB]/`
- **By scope:** Check `schema-drift/`, `rbac-lockout/`, etc.
- **By trend:** Read `summary-by-date.md` for weekly insights
- **By lesson impact:** See [[observability/lesson-effectiveness]] to check if L-018 is actually preventing RBAC issues

---

*Structure established 2026-04-25*
