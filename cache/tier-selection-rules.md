# Tier Selection Rules (Phase 7)

**Last updated:** 2026-04-25T15:52:10.350Z

## Decision Tree

```
Is there a cached response for this query?
  ├─ YES → Use HAIKU (800 tokens, ~$0.03)
  │   └─ Confidence: 100%
  │
  └─ NO → How many past examples of this task type exist?
      ├─ 3+ examples → Use SONNET with cached context (avg token * 0.7)
      │   └─ Confidence: 85%
      │
      ├─ 1-2 examples → Use SONNET (avg token from history)
      │   └─ Confidence: 70%
      │
      └─ 0 examples → Use OPUS for deep reasoning (8K tokens)
          └─ Confidence: 50%
```

## Model Economics

| Tier | Cost | Latency | Best For |
|------|------|---------|----------|
| **Haiku** | ~$0.03 | 2s | Cached responses, lightweight agents, pair programming |
| **Sonnet** | ~$0.08 | 5s | Main development work, reasoning, orchestration |
| **Opus** | ~$0.40 | 10s | Novel architectural decisions, deep research |

## Task Types and Historical Cost

Populated from Phase 6 observability daemon:

### Bootstrap Queries (typically cached)
- `01-project-section-draft`: Haiku 800 tokens (100% cache hit)
- `02-scope-definition`: Haiku 1200 tokens (100% cache hit)
- `03-architecture-conventions`: Haiku 1000 tokens (100% cache hit)

### Design Tasks (periodic cache miss)
- `contradiction-check`: Sonnet 1500 tokens (60% cache hit)
- `vault-structure-design`: Haiku 1100 tokens (80% cache hit)

### Novel Decisions
- `architectural-innovation`: Opus 8000 tokens (0% cache hit)
- `cross-customer-synthesis`: Opus 6000 tokens (0% cache hit)

## Cache Hit Rate by Month

- Month 1: 40% (cache warming up)
- Month 2: 65% (patterns emerging)
- Month 3+: 75%+ (brain mature)

**Target:** 70%+ cache hit rate after 3 months.

## Integration with Phase 5 Bootstrap

In `new-project-bootstrap-v2.ts`:

```typescript
// Step 2: Draft Project Section
const recommendation = resolveTier({
  taskId: '01-project-section-draft',
  taskType: 'bootstrap-section-draft',
  // ... profile data
});

if (recommendation.cacheHit) {
  const cached = await brain.queryCache('01-project-section-draft');
  console.log(`✅ Using ${recommendation.model}: ${recommendation.reason}`);
  return cached;
} else {
  const result = await generateWithModel(recommendation.model, prompt);
  updateTokenSpendLog(recommendation.taskId, recommendation.model, result.tokens);
  return result;
}
```

## Post-Bootstrap Analysis

Each bootstrap records:
1. Query ID (`01-project-section-draft`, etc.)
2. Model used (`haiku`, `sonnet`, `opus`)
3. Actual tokens consumed
4. Cache hit (yes/no)

Weekly observability roll-up (Phase 6) analyzes:
- Which queries have best cache hit rates
- Which task types need more past examples
- Which task types should move to cheaper tiers

This feeds back into tier selection for next month.
