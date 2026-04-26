---
phase: "5-Portability"
title: "Phase 5 Portability Specification — Brain Works for Local & Claude Cowork"
date: 2026-04-25
status: "Design (ready to implement)"
audience: ["Local projects", "Claude Cowork projects", "Multi-customer instances"]
---

# Phase 5 Portability: Brain as Service

## Problem

Phase 5 design assumes local file reads (`~/vaults/ark/`). This breaks for:
- Claude Cowork projects (no local ~/vaults)
- Multi-customer instances (multiple brains vs one shared brain)
- Offline/disconnected work (can't query remote brain)
- Scaling (one brain serving 20+ customer projects)

**Solution:** Brain queries via API + fallback to embedded cache.

---

## Architecture: Two-Tier Brain Access

### Tier 1: Embedded Cache (always available)

When new-project-bootstrap runs, it carries a **snapshot of the brain** with it:
- Copy brain state into project repo during import/creation
- Location: `.parent-automation/brain-snapshot/` (per-project)
- Contents: Cached queries, lessons, templates, anti-patterns relevant to project-type
- Size: ~5 MB (compressed lessons + cache, no large findings)

```
ProjectA/
├── .parent-automation/
│   ├── brain-snapshot/
│   │   ├── lessons/
│   │   │   ├── L-018-RBAC.md
│   │   │   ├── L-021-Route-Compute.md
│   │   │   └── ...
│   │   ├── cache/
│   │   │   ├── 01-project-section.md
│   │   │   ├── 02-scope-definition.md
│   │   │   └── ...
│   │   ├── templates/
│   │   │   ├── service-desk-template.md
│   │   │   └── ...
│   │   └── SNAPSHOT-MANIFEST.json
│   │       └── (version, date, hash for coherence check)
```

**Bootstrap uses Tier 1:**
- Haiku queries local snapshot → fast, offline-safe, no API call
- Cost: 0 network calls, 100% local file reads
- Fallback: If snapshot outdated, can pull fresh from Tier 2

### Tier 2: Central Brain API (optional, for updates)

Optional central brain instance (could be in Strategix vault, could be on Anthropic servers, could be customer-hosted).

```
Endpoint: https://brain.strategix.internal/api/query
POST /api/query
{
  "query_id": "01-project-section-draft",
  "project_type": "service-desk",
  "customer": "strategix",
  "version": "2026-04-25"
}
→ Returns: {
  "cached_response": "...",
  "version": "2026-04-25",
  "timestamp": "2026-04-25T14:30Z",
  "related_lessons": ["L-018", "L-021"],
  "cache_hit_count": 12
}
```

**Use Tier 2:**
- When snapshot is stale (> 1 week)
- When project wants to feed decision back to brain
- When team explicitly requests "check for new lessons"
- When starting new customer account (download initial brain state)

---

## Implementation: Embedded Cache First

### Step 1: Generate Brain Snapshot

Before Phase 5 wiring, generate `.parent-automation/brain-snapshot/`:

```bash
# In ~/vaults/ark/
npm run generate-snapshot \
  --output ~/code/strategix-servicedesk/.parent-automation/brain-snapshot/ \
  --project-type service-desk \
  --customer strategix \
  --compress gzip
```

Snapshot includes:
- All project-type-relevant lessons (service-desk lessons + universal lessons)
- All cache entries (10 queries + any project-specific customizations)
- All templates (project-types/, vault-structure/, anti-patterns.md)
- SNAPSHOT-MANIFEST.json (version, hash, lessons-included, cache-hits)

### Step 2: Bootstrap Uses Local Snapshot

new-project-bootstrap v2 queries local snapshot:

```typescript
// new-project-bootstrap/query-brain.ts
async function queryBrain(queryId: string, context: any) {
  // Try local snapshot first (always available)
  const snapshot = await readSnapshot('.parent-automation/brain-snapshot/');
  const cached = snapshot.get(queryId);
  
  if (cached && snapshot.isValid()) {
    // Local snapshot is fresh, use it
    return cached;
  }
  
  // Snapshot stale? Try to refresh from central brain
  if (hasNetworkAccess() && process.env.BRAIN_API_URL) {
    try {
      const fresh = await fetchFromBrainAPI(queryId, context);
      await updateSnapshot(fresh);
      return fresh;
    } catch (err) {
      // Network failed, fall back to local (possibly stale)
      console.warn('Brain API unavailable; using stale snapshot');
      return cached;
    }
  }
  
  // No network, no API URL, use local
  return cached;
}
```

**Result:**
- ✅ Works offline (no network needed)
- ✅ Works in Claude Cowork (no ~/vaults access needed)
- ✅ Graceful degradation (stale is better than nothing)
- ✅ Optional refresh when network available

### Step 3: Per-Project Customization

Some projects (Customer A) may customize lessons/cache locally:

```
ProjectA/.parent-automation/brain-snapshot/
├── lessons/
│   ├── L-018-RBAC.md               (inherited from central brain)
│   ├── customerA-L-001-Custom.md   (local, project-specific)
│   └── ...
├── cache/
│   ├── 01-project-section.md       (inherited)
│   ├── customerA-01-project-section.md (overrides inherited)
│   └── ...
└── SNAPSHOT-MANIFEST.json
    └── overrides: ["customerA-01-project-section"]
```

**Priority:**
1. Local overrides (if CustomerA-L-001 exists, use it over L-018)
2. Inherited from snapshot (if not overridden, use snapshot version)
3. Network (if snapshot stale and network available, fetch fresh)

---

## Portability: Claude Cowork Integration

### When New Project Created in Claude Cowork

```
User creates project in Claude Cowork
  ↓
parent-automation initializes project
  ↓
[NEW] Download brain snapshot
  POST https://brain.strategix.internal/api/snapshot
    → Returns: Latest brain state (lessons, cache, templates)
    → Saves to project/.parent-automation/brain-snapshot/
  ↓
new-project-bootstrap v2 runs
  → Queries local snapshot (fast, no network overhead)
  → Uses same flow as local projects
  ↓
[Optional] Feed decisions back to brain
  POST https://brain.strategix.internal/api/decisions
    → Sends: {project_type, customer, decisions_made, contradictions_resolved}
    → Updates central observability for Phase 6
```

### When Project Imported to Claude Cowork

```
User has local Strategix project, imports to Claude Cowork
  ↓
parent-automation detects import
  ↓
[NEW] Ensure brain snapshot exists
  if not present:
    → Download snapshot (as above)
  else:
    → Keep existing snapshot (preserve local customizations)
  ↓
Project continues with inherited automation
```

### Multi-Tenant Brain Scenario

Option A: **One shared brain for all customers**
```
Central: https://brain.strategix.internal/ (Strategix owns)
├── Lessons from all customers (strategix + customerA + customerB)
├── Cross-customer patterns visible
└── Meta-insights available to all

Snapshot includes:
  - Universal lessons (apply to all)
  - Customer-tagged lessons (apply to that customer)
  - Project-type templates (apply to that type)
```

Option B: **Customer-specific brain instances** (optional)
```
Each customer hosts their own brain:
  - CustomerA: brain.customerA.internal/
  - CustomerB: brain.customerB.internal/
  - Strategix: brain.strategix.internal/

Cross-project learning:
  - Within customer: full access to all lessons
  - Across customers: optional sync (with permission)
  - Strategix brain acts as "meta-brain" (universal patterns, best practices)
```

---

## File Structure: Phase 5 Ready

### For local projects (~/code/strategix-servicedesk/):

```
strategix-servicedesk/
├── .parent-automation/
│   ├── brain-snapshot/         ← LOCAL BRAIN (always available)
│   │   ├── lessons/
│   │   ├── cache/
│   │   ├── templates/
│   │   └── SNAPSHOT-MANIFEST.json
│   ├── skills/
│   │   ├── new-project-bootstrap/ (queries local snapshot)
│   │   ├── project-context-loader/ (loads snapshot on init)
│   │   └── brain-sync/ (NEW: updates snapshot from API)
│   └── config/
│       └── brain.config.json (optional API URL, refresh interval)
```

### For Claude Cowork projects:

```
ProjectInCowork/
├── .parent-automation/
│   ├── brain-snapshot/         ← SAME STRUCTURE
│   ├── skills/
│   └── config/
└── [all other project files]
```

**No differences.** Same automation, same lessons, same bootstrap flow.

---

## Phase 5 Implementation Steps

### Implementation Order:

1. **Week 1: Embed Snapshot**
   - Generate initial snapshot from brain (Strategix-only)
   - Add to strategix-servicedesk/.parent-automation/brain-snapshot/
   - Test: bootstrap runs using local snapshot

2. **Week 2: Brain Sync Skill (NEW)**
   - Create `/brain-sync` command to refresh snapshot
   - Implement API client for central brain
   - Add optional BRAIN_API_URL config

3. **Week 3: Bootstrap Integration**
   - Wire new-project-bootstrap to use local snapshot
   - Test with offline mode (no network)
   - Test with API refresh (network available)

4. **Week 4: Claude Cowork Readiness**
   - Test project creation in Claude Cowork
   - Verify snapshot auto-downloads on import
   - Verify offline fallback works

5. **Week 5: Multi-Tenant Support**
   - Design customer-specific lesson tagging
   - Implement snapshot filtering (universal vs customer-specific)
   - Document multi-tenant options

---

## Success Criteria

- [ ] Local projects use embedded snapshot (no network calls)
- [ ] Claude Cowork projects download snapshot on import
- [ ] Bootstrap works identically in both environments
- [ ] Snapshot version tracked (can detect stale/updates)
- [ ] Optional central brain API available (not required)
- [ ] Graceful degradation: stale snapshot > nothing
- [ ] Projects can override/customize lessons locally
- [ ] Cross-customer patterns visible (if shared brain)
- [ ] Token spend reduced 40% (same as Phase 4)
- [ ] Time-to-bootstrap reduced 40% (same as Phase 4)

---

## Related Documents

- **phase5-bootstrap-integration-design.md** — Detailed bootstrap wiring
- **cache/MEMORY.md** — Query response index (snapshot content)
- **lessons/\*.md** — Source lessons for snapshot
- **doctrine/bootstrap-standard.md** — Standard bootstrap checklist (works for local + Cowork)

---

## Why This Matters

Without portability:
- ❌ Claude Cowork projects can't inherit lessons
- ❌ Each project reinvents solutions
- ❌ No cross-customer learning
- ❌ Token savings don't scale

With portability:
- ✅ Any project (local or Cowork) inherits all lessons from day 1
- ✅ Self-improving automation compounds across customers
- ✅ First Cowork project costs 40% less (uses Strategix lessons)
- ✅ Brain grows smarter as more projects are built
- ✅ Quality maintained across all projects (same anti-patterns caught)
