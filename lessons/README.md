# Lessons — Cross-Project Knowledge Base

All captured lessons from Strategix and customer projects, tagged by source and scope.

## Structure

- **[source]-L-NNN.md** — Individual lesson (e.g., `strategix-L-018.md`, `customerA-L-005.md`)
  - Contains rule, trigger pattern, cost analysis, evidence, effectiveness tracking
  - Tagged with `universal: true/false` and `applies_to_domains: [...]`
  - Cross-references to related lessons and meta-patterns

- **universal-patterns.md** — Synthesized lessons applying across all projects
  - RBAC Lockout (affects 80% of projects)
  - Shell Rebuild Affordance Drift (costs 3-5 days per project)
  - Schema Migration Coordination (cross-repo dependency tracking)

- **by-customer/** — Lessons organized by customer/project
  - `strategix/` — Strategix-specific lessons (L-001...L-023)
  - `customerA/` — Placeholder for future customer A
  - `customerB/` — Placeholder for future customer B

- **meta-lessons.md** — Cross-customer insights
  - "RBAC lockout is 80% universal; here's the consolidated lesson"
  - "Projects applying L-018 complete Phase 2 40% faster"
  - "Shell rebuild cost varies by stack: Cloudflare Workers vs Pages differs"

## Contributing

When you discover a lesson:
1. Create `[source]-L-NNN.md` with full frontmatter
2. Add backlinks to [[universal-patterns]] or [[meta-lessons]]
3. Tag with `origin_project`, `customer_affected`, `applies_to_domains`
4. Link to observability tracking: how many times violated, how many prevented

## Querying

- **By domain:** Search [[lessons/by-customer/strategix/]] for service-desk, revops, etc.
- **By scope:** Grep for "RBAC", "schema", "affordance", "shell"
- **By severity:** Filter on `severity: CRITICAL` or `severity: HIGH`
- **By effectiveness:** Check [[observability/lesson-effectiveness]] to see which lessons reduce mistakes

---

*Structure established 2026-04-25*
