---
title: "Obsidian Ark Strategy — Self-Improving Automation for Local + Claude Cowork"
date: 2026-04-25
status: "Approved for implementation"
scope: "All projects (Strategix + all customers, local + Claude Cowork)"
---

# The Self-Improving Automation Loop

## Vision

**One brain, infinite projects.** Every project bootstrapped with lessons from all previous projects. Every decision feeds back into automation, making the next project faster, cheaper, and higher-quality.

Works for:
- ✅ Local projects (~/code/strategix-servicedesk/)
- ✅ Claude Cowork projects (no local filesystem)
- ✅ Multi-customer environments (Strategix + CustomerA + CustomerB)
- ✅ Offline work (no network required)

---

## The Loop (Phases 0-7)

```
PROJECT A bootstraps
  ↓ (captures: decisions, contradictions, time, token cost)
PHASE 2: Findings ingested
  ↓ (classifies: schema-drift, RBAC, contradictions, implementation patterns)
PHASE 5: Bootstrap creates embedded snapshot
  ↓ (embeds brain into project: lessons, cache, templates, anti-patterns)
PROJECT B bootstraps
  ↓ (downloads Project A's brain snapshot)
  ↓ (learns from Project A: uses cached responses, avoids known contradictions)
  ↓ (faster: 40% token reduction, 40% time reduction)
PHASE 6: Observability daemon analyzes all projects
  ↓ (detects: "multi-tenant always needs tenant-on-every-table", "RBAC lockout happens in 80% of projects")
LESSONS synthesized
  ↓ (L-026: "Multi-tenant: start with tenant-on-every-table", L-027: "RBAC failures follow X pattern")
PHASE 4: Cache updated
  ↓ (new lessons cached, new templates created)
PROJECT C bootstraps
  ↓ (uses lessons from A + B, even more optimized)
```

**Each cycle compounds:**
- Token cost decreases (more cached, less reasoning needed)
- Bootstrap time decreases (more templates, fewer decisions)
- Quality improves (more contradictions caught pre-merge, fewer regressions)
- Knowledge concentrates (lessons learned once, applied forever)

---

## Implementation Status: Phases 0-5 Ready

| Phase | What | Status | Why It Matters |
|-------|------|--------|-----------------|
| **0** | Vault structure (multi-tenant) | ✅ Done | Foundation for all lessons |
| **1** | Ingest Strategix lessons (5 key + 6 meta) | ✅ Done | Strategix knowledge captured |
| **2** | Classify findings (16 ingested, scope-organized) | ✅ Done | Patterns surfaced, contradictions identified |
| **3** | Extract bootstrap templates (service-desk, revops, ops-intelligence) | ✅ Done | New projects have reference architectures |
| **4** | Build query cache (10 responses, 40% token savings) | ✅ Done | Haiku answers instead of Sonnet |
| **5** | Wire bootstrap + embedded snapshot | ⏳ Ready | **Turns automation operational** |
| **6** | Observability daemon (cross-project patterns) | ⏳ Design ready | **Closes the learning loop** |
| **7** | Tier resolver optimization | ⏳ Design ready | Further token optimization |

**Current:** Phase 5 design ready (bootstrap integration + portability spec). Implementation: 2-3 days.

---

## Phase 5 Solves: "How do new projects inherit automation?"

### The Problem
Today: Each project discovers lessons independently (time, tokens, rework).
- Project A learns RBAC centralization takes 2 hours
- Project B learns the same thing, wastes 2 hours
- Project C learns it again, wastes 2 hours
- Total waste: 6 hours × token cost per lesson

### The Solution: Embedded Snapshot
When Project B is created/imported:

```
1. Download brain snapshot from central (or use cached version)
   → Contains: All lessons, all cached queries, all templates
   → Size: ~5 MB (compressed)

2. Store snapshot in project: .parent-automation/ark-snapshot/

3. Bootstrap runs, queries local snapshot
   → No network needed (works offline, Claude Cowork)
   → Haiku handles queries (800 tokens vs Sonnet 3K)
   → Cached contradictions caught (5 min vs 2 hours)

4. Project learns from A automatically
   → Reuses A's RBAC structure (no discovery needed)
   → Avoids A's known anti-patterns (pre-checks them)
   → Completes 40% faster
```

**Portable across environments:**
- Local: snapshot in `.parent-automation/ark-snapshot/`
- Claude Cowork: same path, same queries, same results
- Offline: no API calls needed, snapshot is sufficient
- Online: optional refresh from central brain (if changes exist)

---

## Phase 6 Solves: "How do we know what's working?"

Observability daemon runs weekly:

```
Reads: Decision logs from all projects (Phase 5 capture)
Detects: Patterns
  → "All 3 projects chose D1 for database"
  → "RBAC lockout happened in 2 projects, lesson prevented in 1"
  → "Multi-tenant enforcement: 80% of projects had this decision point"

Updates: Lesson effectiveness tracking
  → L-018 (RBAC) prevented 5 incidents, 60% effective
  → L-021 (route/compute) prevented 3, 70% effective
  → L-026 (multi-tenant) new candidate, no track record yet

Generates: Meta-lessons
  → "Multi-tenant is a universal decision point (100% of service-desk projects)"
  → "RBAC failures follow pattern X across 5 projects"
  → "Token cost reduced from 25K → 15K average (40% reduction confirmed)"
```

This feeds back into Phase 4 (cache) and Phase 3 (templates), improving next bootstrap.

---

## Phase 7 Solves: "How do we minimize token spend?"

Tier resolver makes automatic model decisions:

```
Task: "Draft CLAUDE.md Project section"
  ↓
Is it cached? → Yes: use Haiku (800 tokens, $0.03)
  ↓
Task: "Design RBAC for new project"
  ↓
Is it cached? → No: use Sonnet (1500 tokens, $0.08)
  → But: Sonnet queries cached RBAC template first (reuses structure)
  → Result: 30% cheaper than fresh design
  ↓
Task: "Analyze if our 7-phase plan is correct"
  ↓
Is it cached? → No: use Opus (8000 tokens, $0.40)
  → Novel decision, needs maximum reasoning
  → Cost: 10x Haiku, but only 1% of tasks
```

**Result:** Average token spend per bootstrap
- Without brain: 25K tokens (all Sonnet)
- With Phase 4-5: 15K tokens (Haiku cached + Sonnet reasoning)
- With Phase 7: 12K tokens (Tier optimization)
- **Savings: 50% per project**

---

## The Ecosystem

### For Local Projects (Strategix)
```
~/code/strategix-servicedesk/
├── .parent-automation/
│   ├── brain-snapshot/    ← Embedded lessons + cache
│   ├── skills/            ← Bootstrap, context-loader, brain-sync
│   └── config/
├── .planning/
└── src/
```

**Flow:**
1. Developer runs: `/bootstrap service-desk`
2. Skill queries `.parent-automation/ark-snapshot/`
3. Snapshot returns: templates, lessons, cached queries
4. Bootstrap completes in 2.5 hours (vs 4 without brain)
5. Decision log recorded (feeds Phase 6)

### For Claude Cowork Projects
```
ProjectInCowork/
├── .parent-automation/
│   ├── brain-snapshot/    ← SAME STRUCTURE
│   ├── skills/
│   └── config/
└── [project files]
```

**Flow:**
1. Project created in Claude Cowork
2. `parent-automation init` runs
3. Downloads snapshot from `brain.strategix.internal` (or uses fallback)
4. Stores in `.parent-automation/ark-snapshot/`
5. Bootstrap uses local snapshot (identical to local flow)
6. Works offline, no ~/vaults access needed

### For Multi-Customer Instances
```
Scenario 1: Shared brain (recommended)
  Central: https://brain.strategix.internal/
  ├── Lessons from Strategix + CustomerA + CustomerB
  ├── Templates for all project-types
  ├── Unified observability (see cross-customer patterns)
  └── Every project learns from all others

Scenario 2: Customer-specific brains
  Strategix: brain.strategix.internal/
  CustomerA: brain.customerA.internal/
  CustomerB: brain.customerB.internal/
  ├── Each customer learns from their own projects
  ├── Optional: sync with Strategix for universal patterns
  └── Privacy: customer-specific lessons stay internal
```

---

## Success Metrics

By end of Phase 5 implementation:

**Token Economics:**
- [ ] Bootstrap uses Haiku 60% of steps (cached responses)
- [ ] Bootstrap uses Sonnet 30% of steps (reasoning)
- [ ] Bootstrap uses Opus 0% of steps (no novel decisions)
- [ ] Token spend: 25K → 15K per bootstrap (40% reduction)

**Speed & Quality:**
- [ ] Bootstrap time: 4 hours → 2.5 hours (40% faster)
- [ ] Contradictions found pre-merge: 5 min vs 2 hours post-launch
- [ ] Pre-merge contradiction catch rate: 80%+ (prevents post-launch regressions)

**Portability & Scaling:**
- [ ] Works offline: bootstrap completes without network
- [ ] Works in Claude Cowork: projects import successfully, inherit automation
- [ ] Works in multi-customer: lessons shared/tagged appropriately
- [ ] Snapshot size: <5 MB (fast to download/embed)

**Learning Loop:**
- [ ] Phase 6 detects cross-project patterns
- [ ] Phase 6 updates lesson effectiveness tracking
- [ ] Phase 7 optimizes tier selection based on cache
- [ ] 3rd+ projects show cumulative improvement (faster + cheaper + better)

---

## Timeline

**Week 1-2:** Phase 5 Implementation
- Generate snapshot from brain
- Wire bootstrap to query snapshot
- Add optional brain-sync skill (network refresh)
- Test: local project, offline mode, Claude Cowork

**Week 3:** Phase 6 Design → Implementation
- Build observability daemon
- Implement pattern detection
- Auto-update lesson effectiveness

**Week 4:** Phase 7 Design → Implementation
- Optimize tier resolver
- Track token spend vs estimate
- Measure cumulative savings

**Week 5+:** Operate Loop
- Bootstrap new projects (Strategix + Customers)
- Collect decision logs
- Weekly observability runs
- Monthly brain updates

---

## Why This Matters

Without this system:
- ❌ Each project reinvents solutions (wasted tokens, time, knowledge)
- ❌ Anti-patterns rediscovered (regressions in each project)
- ❌ No cross-customer learning (isolated silos)
- ❌ Token spend doesn't improve (Sonnet for every bootstrap)
- ❌ Claude Cowork projects can't inherit Strategix lessons

With this system:
- ✅ Projects inherit all prior lessons (day 1 knowledge)
- ✅ Anti-patterns caught pre-merge (no regressions)
- ✅ Cross-customer learning (shared brain compounds knowledge)
- ✅ Token spend improves with scale (more cached, cheaper)
- ✅ Claude Cowork projects get Strategix lessons for free
- ✅ Self-improving: each project makes next project better

**The brain is the competitive advantage:** New customers bootstrap faster, cost less, and deliver higher quality because they inherit decades of lessons learned by prior projects.

---

## Next Step

Phase 5 design ready (2 documents). Start implementation:
1. Generate snapshot from current brain
2. Add to strategix-servicedesk/.parent-automation/
3. Test bootstrap with snapshot (offline mode)
4. Test import to Claude Cowork (download snapshot)
5. Measure: tokens, time, contradictions caught

All systems designed for portability. Same code, same lessons, same optimization everywhere.
