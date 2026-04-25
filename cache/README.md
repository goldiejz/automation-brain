# Cache — Token Optimization Layer

Cached query responses and prompt libraries built from successful bootstrap and decision workflows. Enables Haiku to answer questions that previously required Sonnet or Opus.

## Structure

- **query-responses/** — Pre-computed answers to common bootstrap questions
  - `"How to scaffold a service-desk project".md` — Cached response with optimized prompt
  - `"How to scaffold a revops platform".md` — Cached response
  - `"Vault structure for MSP domain".md` — Cached response
  - Each entry includes: optimized prompt, cached response, tier recommendation, cost estimate, cache hit rate

- **prompt-library/** — Refined prompts for common tasks
  - `bootstrap-claude-md-section-[section-name].md` — Optimized prompts for each CLAUDE.md section
  - `contradiction-check-[pattern].md` — Efficient queries for detecting specific contradictions
  - `tier-selection-rules.md` — When Haiku vs Sonnet vs Opus (learned from all projects)

- **search-index.md** — Bidirectional links for fast navigation
  - Maps queries → cache entries
  - Maps lessons → relevant cached responses

## Cache Lifecycle

1. **Miss:** Query not in cache → Send to Sonnet/Opus
2. **Response:** Model generates answer
3. **Write:** Cache entry created with optimized prompt + response
4. **Reuse:** Next similar query → Haiku answers from cache
5. **Hit Rate Tracking:** Observe cache effectiveness

## Tier Selection (from cache)

**Haiku 4.5** (3x cost savings):
- Answering from cache (cached prompts known-good)
- Pre-filled templates and examples
- Lightweight agents with frequent invocation

**Sonnet 4.6** (standard tier):
- Cache misses (novel queries)
- Building new cached entries
- Multi-step bootstrap phases

**Opus 4.5** (deep reasoning):
- Complex architectural decisions
- Contradiction resolution across multiple projects
- Cross-customer meta-analysis

---

*Cache structure established 2026-04-25*
