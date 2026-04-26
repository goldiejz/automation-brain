# Phase 6 — AOS: Cross-Customer Learning Autonomy — Context

## Why this phase exists

Phase 3 made delivery self-improving WITHIN a project. Phase 4/5 made bootstrap and portfolio decisions autonomous PER project / customer.

Phase 6 is the meta-tenant: **patterns that recur across customers should auto-promote to universal**. If RBAC lockout (L-018) hit Strategix, then Customer A, then Customer B — Ark should auto-detect that and promote it to a universal lesson, surfaced to every future bootstrap.

Without Phase 6, every customer rediscovers the same lessons. Token cost compounds. Phase 0 of every new customer project repeats mistakes already paid for.

## Position in AOS roadmap

Phase 6 of the 6-phase journey. After this:
- Phase 7: Continuous operation (cron-driven INBOX consumption)

Phase 6 is the layer that makes Phase 7 truly portfolio-aware: when the cron daemon onboards a new customer, it should benefit from cross-customer patterns automatically.

## Architectural decisions (autonomous defaults)

### 1. Lesson scope — Customer's `tasks/lessons.md` files
- Discovers lessons by walking `~/code/*/tasks/lessons.md` (or `$ARK_PORTFOLIO_ROOT/*/tasks/lessons.md`)
- Each customer project has its own `tasks/lessons.md` per project-standard.md convention
- Lesson IDs are L-NNN per customer (Strategix L-018 ≠ Customer A L-018 unless same content)

### 2. Pattern detection — Heuristic similarity
- For each lesson, extract: title (first heading), severity, scope tags, rule body
- Compare titles + rule bodies across customers using simple string overlap (Jaccard or token overlap)
- A pattern is a cluster of ≥2 lessons across ≥2 customers with ≥60% similarity
- No ML/embeddings — keyword overlap and token Jaccard only

### 3. Promotion threshold — ≥2 customers + ≥60% similarity
- A pattern is auto-promoted when:
  - At least 2 distinct customers have a matching lesson (similarity ≥60%)
  - Combined occurrence count ≥3 (e.g., 1 in customer A + 2 in customer B)
- On promotion: write to `~/vaults/ark/lessons/universal-patterns.md` with citations to source lessons
- Audit: `_policy_log "lesson_promote" "PROMOTED" ...` with the source customer/lesson IDs as context

### 4. Anti-pattern detection — same logic, opposite valence
- Lessons tagged "anti-pattern: don't X" → promotion target is `~/vaults/ark/bootstrap/anti-patterns.md`
- Bootstrap policy (Phase 4) reads anti-patterns.md when generating CLAUDE.md → universal anti-patterns automatically appear in new project scaffolds

### 5. Run cadence — Triggered post-phase + manual
- After every `ark deliver` phase completion (re-using Phase 3's post-phase trigger), the lesson promoter runs
- Manual: `ark promote-lessons [--full | --since DATE]`
- Daemon-friendly: idempotent, file-locked, doesn't conflict with active deliveries

### 6. Audit log discipline (Phase 2 contract)
- All lesson promotions logged via `_policy_log "lesson_promote" "<DECISION>" ...`
- Decisions: `PROMOTED`, `DEPRECATED`, `MEDIOCRE_KEPT_PER_CUSTOMER`
- Phase 7's continuous daemon reads this for cross-customer trend reports

## Acceptance criteria (Phase 6 exit)

1. `scripts/lesson-promoter.sh` exists; sourceable; self-test passes
2. `scripts/lib/lesson-similarity.sh` exposes `lesson_similarity <a-md> <b-md>` returning 0..100 percent
3. Walking `$ARK_PORTFOLIO_ROOT/*/tasks/lessons.md` produces a candidate set
4. Patterns with ≥2 customers + ≥60% similarity → auto-promoted to `~/vaults/ark/lessons/universal-patterns.md`
5. Anti-patterns auto-promoted to `~/vaults/ark/bootstrap/anti-patterns.md`
6. Every promotion audit-logged via `_policy_log "lesson_promote" "PROMOTED" ...`
7. `ark promote-lessons` subcommand exists (manual run, --full or --since)
8. Tier 12 verify: synthetic 3-customer fixture with known similar/dissimilar lessons → asserts correct promotion
9. Existing Tier 1–11 still pass

## Constraints

- Bash 3 compat (macOS)
- Single writer for audit log (`_policy_log` only)
- No new `read -p` in delivery-path scripts
- Similarity is heuristic (Jaccard tokens or normalized substring overlap) — no ML deps
- Universal lessons file is git-tracked in vault repo; every promotion = git commit (auditable)
- Promotion is additive — never deletes per-customer lessons
- Idempotent: re-running over same data = no duplicate promotions

## Out of scope

- ML embeddings / semantic similarity (heuristic only)
- Multi-language lesson translation
- Customer-specific lesson redaction (assume lessons are non-sensitive; user's responsibility to redact PII before adding to tasks/lessons.md)
- Lesson deprecation across customers (Phase 6 only PROMOTES; per-customer lessons stay)
- Cross-customer ARGUE / DISAGREEMENT detection (different customers may have CONTRADICTING lessons; Phase 6 surfaces but doesn't resolve)

## Risks

1. **Bad similarity matches promote spurious lessons** — mitigated by 60% threshold + ≥2 distinct customers + manual review queue. Promotions go to a "pending" file initially; auto-promote only after Phase 3-style outcome confirmation.

2. **PII leakage from customer lessons** — universal-patterns.md is in vault git, potentially synced/backed-up. Mitigated by: lessons are user-curated documents (not auto-extracted) — user has already reviewed before adding to tasks/lessons.md. Phase 6 just clusters; doesn't extract new content.

3. **Conflicting lessons across customers** — surfaced as DEPRECATED entries (cluster found, but lessons disagree on the rule). Logged for manual review; not auto-promoted.
