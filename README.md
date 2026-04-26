# Obsidian Brain: Multi-Project Automation Learning System

Self-improving ark for the Strategix ecosystem (CRM, IOC, ServiceDesk). Ingests lessons from all projects, detects universal patterns, and accelerates new project bootstraps through cached knowledge and intelligent model selection.

## What This Is

A centralized knowledge vault that:
- **Learns from all projects** — Strategix + all customer projects contribute lessons
- **Detects universal patterns** — Cross-project insights (e.g., "RBAC lockout is 80% universal")
- **Accelerates bootstraps** — New projects query brain: "I'm building a service desk; what lessons apply?"
- **Optimizes token spend** — Cached prompts reduce costs from 25K → 12-13K per bootstrap (48-52% savings)
- **Routes intelligently** — Dynamic model selection (Haiku/Sonnet/Opus/Codex/Gemini) based on task characteristics
- **Self-improves weekly** — Phase 6 daemon analyzes patterns, updates lesson effectiveness, recalibrates model weights

## Structure

```
automation-brain/
├── 00-Index.md              ← Navigation hub and entry point
├── lessons/                 ← Ingested lessons from all projects (L-NNN format)
│   ├── strategix-L-001.md   (e.g., "RBAC lockout prevention")
│   ├── customerA-L-005.md   (e.g., "Schema drift detection")
│   └── universal-patterns.md (consolidated cross-project insights)
├── bootstrap/               ← Templates and decision support for new projects
│   ├── project-types/       (service-desk, revops, ops-intelligence templates)
│   ├── vault-structure/     (minimum-vault, domain-specific structures)
│   └── anti-patterns.md     (patterns that cause drift)
├── findings/                ← Audit findings indexed by scope
│   ├── schema-drift/
│   ├── rbac-lockout/
│   └── affordance-drift/
├── cache/                   ← Token optimization layer
│   ├── query-responses/     (cached answers to bootstrap questions)
│   ├── prompt-library/      (optimized prompts learned from all projects)
│   └── tier-selection-rules.md (model selection decision tree)
├── doctrine/                ← Universal standards and principles
├── observability/           ← Self-improvement tracking (weekly updates)
│   ├── lesson-effectiveness.md (which lessons prevent mistakes?)
│   ├── cross-customer-insights.md (patterns across all projects)
│   ├── token-spend-log.md   (cost tracking per project)
│   └── model-weight-adjustments.md (auto-updated model registry)
└── scripts/                 ← Utilities (snapshot generation, daemon runners)
```

## How It Works

### The Self-Improving Loop

```
Bootstrap Project A starts
        ↓
Project A completes → decision logged to .planning/bootstrap-decisions.jsonl
        ↓
Phase 6 daemon runs IMMEDIATELY (triggered by decision log write)
        → Reads decision logs from all projects
        → Detects universal patterns (if 2+ projects share pattern)
        → Updates lesson-effectiveness.md
        → Recalibrates model weights
        → Cache refreshed
        ↓
Bootstrap Project B starts (minutes/hours after Project A)
        → Queries brain: "lessons for this project type"
        → Uses improved cache (40% faster, cheaper)
        → Contributes new lessons
        ↓
Phase 6 runs again IMMEDIATELY (triggered by Project B's decision log)
        → Sees patterns from A + B
        → Surfaces universal doctrine
        → Model weights recalibrated based on actual cost/quality
        ↓
Bootstrap Project C starts
        → Inherits lessons from A + B
        → Even faster, even cheaper
        ↓
Loop compounds: Each project improves the next immediately, not in weeks
```

### Key Metrics Tracked

| Metric | Target | Tracked |
|--------|--------|---------|
| Token spend | 12-13K (down from 25K) | `observability/token-spend-log.md` |
| Cache hit rate | 70%+ | Phase 6 output |
| Model distribution | H:40% S:35% C:15% G:8% O:2% | `observability/model-weight-adjustments.md` |
| Lesson effectiveness | >80% prevent mistakes | `observability/lesson-effectiveness.md` |

## Deployment Status

**Live:** All 3 Strategix repos (servicedesk, crm, ioc)
- ✅ Snapshots deployed (offline-capable, portable)
- ✅ Bootstrap v2 integrated
- ✅ Decision logging ready
- ✅ Phase 6 observability daemon configured (Monday 9am)
- ✅ Phase 7 tier resolver ready
- ✅ Dynamic model registry ready (awaiting API keys)

See `DEPLOYMENT_STATUS.md` for live deployment details.

## Getting Started

### For Developers
1. **Clone this vault:**
   ```bash
   git clone https://github.com/strategix/ark.git ~/vaults/ark
   ```

2. **Open in Obsidian:**
   - Open Obsidian → "Open vault folder" → select `automation-brain`
   - Start at `00-Index.md` for navigation

3. **View lessons:**
   - Browse `lessons/` to see captured patterns from all projects
   - Click cross-references to navigate the knowledge graph

4. **Check observability:**
   - `observability/cross-customer-insights.md` — Latest patterns
   - `observability/lesson-effectiveness.md` — Which lessons work
   - `observability/token-spend-log.md` — Cost tracking

### For New Project Bootstraps
1. **Copy snapshot to your project:**
   ```bash
   cp -r ~/.parent-automation/brain-snapshot /path/to/your-project/.parent-automation/
   ```

2. **Run bootstrap v2:**
   ```bash
   cd /path/to/your-project/.parent-automation
   npx ts-node new-project-bootstrap-v2.ts \
     --project-type [service-desk|revops|ops-intelligence] \
     --customer [your-customer-name] \
     --project-name "Your Project"
   ```

3. **Decision logged automatically** → Phase 6 runs immediately + weekly audit

## Integration with Projects

Each Strategix project has:
- `.parent-automation/ark-snapshot/` — Embedded copy for offline/Cowork use
- `.planning/bootstrap-decisions.jsonl` — Decision log fed to Phase 6
- `query-brain.ts` — Interface to snapshot
- `new-project-bootstrap-v2.ts` — 12-step bootstrap with brain integration

## Observability: Dual-Mode Phase 6

### Event-Triggered (Immediate)
Runs instantly when bootstrap logs a decision:
- Detects patterns across decision logs
- Updates `lesson-effectiveness.md`
- Recalibrates model weights
- Refreshes cache
- Next project benefits immediately

### Cron-Based (Weekly Safety Audit)
**Phase 6 Observability Daemon** (Monday 9am):
- Audits all decision logs were processed
- Reconciles state if event-triggered runs failed
- Calculates lesson effectiveness (prevented/violated ratio)
- Generates comprehensive `cross-customer-insights.md`
- Archives weekly metrics

**Phase 6-Extended** (Monday 9am):
- Fetches latest Claude, Codex, Gemini models
- Recalculates decision weights based on new capabilities
- Updates `model-weight-adjustments.md`
- Zero manual intervention needed

**Result:** Immediate improvements + weekly audit trail for resilience

## Command Reference

### View vault structure
```bash
cd ~/vaults/ark
find . -type f -name "*.md" | head -20
```

### Check latest insights
```bash
cat ~/vaults/ark/observability/cross-customer-insights.md
cat ~/vaults/ark/observability/lesson-effectiveness.md
```

### Monitor Phase 6 runs
```bash
tail -f ~/vaults/ark/logs/phase-6.log
tail -f ~/vaults/ark/logs/phase-6-models.log
```

### Check decision logs from projects
```bash
cat ~/code/strategix-servicedesk/.planning/bootstrap-decisions.jsonl
cat ~/code/strategix-crm/.planning/bootstrap-decisions.jsonl
cat ~/code/strategix-ioc/.planning/bootstrap-decisions.jsonl
```

## Architecture & Design

See `DEPLOYMENT_GUIDE.md` for full deployment instructions.
See `IMPLEMENTATION_COMPLETE.md` for architecture overview and phase breakdown.
See `STRATEGY.md` for design decisions and future roadmap.

## Contributing

When you discover a lesson:
1. It's automatically ingested into this vault by the observability daemon
2. Lessons are tagged by origin project (strategix-L-018, customerA-L-005)
3. Cross-project patterns bubble up to `universal-patterns.md`
4. Next bootstrap benefits from all prior lessons

## Support & Troubleshooting

### Phase 6 daemon didn't run
```bash
log stream --predicate 'process == "cron"'  # macOS
journalctl -u cron  # Linux
```

### Model registry API failed
API keys may be missing. See `DEPLOYMENT_GUIDE.md` Part 1 (environment setup).

### Snapshot not found in project
```bash
# Restore from vault
cp ~/vaults/ark/cache/query-responses/* \
   ~/code/[project]/.parent-automation/ark-snapshot/cache/
```

---

**Status:** ✅ Operational across all 3 Strategix projects
**Last update:** 2026-04-25
**Next Phase 6 run:** Monday 2026-04-28 at 9:00 AM GMT+2
