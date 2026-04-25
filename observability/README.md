# Observability — Self-Improvement Tracking

Metrics, health signals, and meta-patterns tracked across all projects to improve the automation system itself.

## Structure

- **lesson-effectiveness.md** — Which lessons actually prevent mistakes?
  - L-018 (RBAC lockout): 4 prevented incidents, 1 violation → 80% effective
  - L-020 (affordance audit): 2 prevented incidents, 3 violations → 40% effective, needs refresh
  - Tracks: violations since capture, prevented incidents estimate, false positives, customer adoption

- **agent-health.md** — Agent performance and trigger accuracy
  - Observer agent: Detects findings accurately 95% of the time, false positives 5%
  - Improver agent: Delivers actionable fixes 90% of the time
  - Validator agent: Type/test coverage checks 99% accurate
  - Tracks: accuracy by agent, over-triggering, under-detection, cost per invocation

- **bootstrap-quality-metrics.md** — Bootstrap success rates and cycle time
  - Strategix servicedesk: 6 days to P1 shipped, 14 lessons captured
  - Strategix crm: 5 days to P1 shipped, 10 lessons captured
  - Strategix ioc: 8 days to P1 shipped, 12 lessons captured
  - Future: Strategix vs CustomerA vs CustomerB comparison (is bootstrap faster with brain?)

- **token-spend-log.md** — Cost tracking by query type and model tier
  - Cache hits (Haiku): ~2K tokens/query, 10 queries/day → $X
  - Cache misses (Sonnet): ~10K tokens/query, 2 queries/day → $X
  - Architectural decisions (Opus): ~30K tokens/query, 1/week → $X
  - Tracks: cost trends, which queries are most expensive, cache hit rate ROI

- **cross-customer-insights.md** — Meta-patterns across all customers
  - "Projects with L-018 applied on bootstrap complete Phase 2 40% faster"
  - "RBAC lockout affects 80% of projects; here's the universal solution"
  - "Shell rebuild costs: Cloudflare Workers $X, Pages $Y (Pages cheaper)"
  - "Contradiction detection in bootstrap reduced rework by 25%"

## Observability Daemon

**`/brain-sync` command** (weekly, runs Thursday 2PM UTC):
1. Reads findings/ from all three Strategix repos
2. Reads tasks/lessons.md from all three repos
3. Detects patterns: "RBAC lockout finding occurred 2x this week"
4. Updates lesson-effectiveness.md (is L-018 reducing RBAC findings?)
5. Updates agent-health.md (accuracy, false positives)
6. Writes weekly summary to summary-by-date.md
7. Commits changes to brain vault

## Querying Observability

- **"Is L-018 working?"** → Check [[lesson-effectiveness#L-018-RBAC-Lockout]]
- **"Which agents are reliable?"** → Check [[agent-health]]
- **"What patterns span all customers?"** → Check [[cross-customer-insights]]
- **"Are we getting faster at bootstrap?"** → Check [[bootstrap-quality-metrics]]
- **"What's the token spend trend?"** → Check [[token-spend-log]]

---

*Observability structure established 2026-04-25*
