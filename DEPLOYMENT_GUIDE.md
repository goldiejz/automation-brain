# Deployment Guide: Obsidian Ark + Dynamic Model Registry

**Status:** Ready for immediate deployment  
**Timeline:** 2-3 days full integration  
**Risk Level:** Low (all changes are additive, no breaking changes)

---

## Pre-Deployment Checklist

- [ ] All environment variables configured (see `.env.example` below)
- [ ] Snapshot tested offline
- [ ] Phase 6 daemon test run successful
- [ ] Model registry API keys validated
- [ ] Cron job permissions verified

---

## Part 1: Environment Setup (30 min)

### Create `.env.example` in ark root:

```bash
# Anthropic (Claude) API key
ANTHROPIC_API_KEY=sk-ant-...

# Codex API key (if using Codex)
CODEX_API_KEY=...

# Google (Gemini) API key
GOOGLE_API_KEY=...

# Optional: Central brain API
BRAIN_API_URL=https://brain.strategix.internal/api/query
BRAIN_API_KEY=...
```

### Deploy to servers:

```bash
# All 3 Strategix repos
for repo in servicedesk crm ioc; do
  cp .env.example ~/code/strategix-${repo}/.parent-automation/.env
  # Fill in actual keys
  vi ~/code/strategix-${repo}/.parent-automation/.env
done

# Set permissions (read-only for daemon)
chmod 400 ~/.parent-automation/.env
```

---

## Part 2: Generate Snapshots (1 hour)

### For each Strategix repo:

```bash
cd ~/code/strategix-servicedesk/.parent-automation
bash scripts/generate-snapshot.sh \
  . \
  service-desk \
  strategix

# Verify snapshot
du -sh brain-snapshot/
find brain-snapshot -type f | wc -l  # Should be 59 files (46 lessons + 10 cache + 3 templates)
```

### Test bootstrap offline mode:

```bash
cd ~/code/strategix-servicedesk/.parent-automation
npx ts-node new-project-bootstrap-v2.ts --offline
# Should complete without network calls
```

### Repeat for crm and ioc:

```bash
# Update project-type in generate-snapshot.sh
bash scripts/generate-snapshot.sh . revops strategix
bash scripts/generate-snapshot.sh . ops-intelligence strategix
```

---

## Part 3: Setup Phase 6 Daemon (1 hour)

### Create `.planning/bootstrap-decisions.jsonl` in each repo:

```bash
for repo in servicedesk crm ioc; do
  touch ~/code/strategix-${repo}/.planning/bootstrap-decisions.jsonl
done
```

### Create Phase 6 cron job:

```bash
# As root or with sudo:
cat > /etc/cron.d/phase-6-observability << 'EOF'
# Run Phase 6 observability daemon every Monday at 9am
0 9 * * 1 cd /Users/jongoldberg/vaults/ark && \
  npx ts-node observability/phase-6-daemon.ts >> logs/phase-6.log 2>&1

# Run model registry update as part of Phase 6
0 9 * * 1 cd /Users/jongoldberg/vaults/ark && \
  npx ts-node observability/phase-6-daemon-extended.ts >> logs/phase-6-models.log 2>&1
EOF

chmod 644 /etc/cron.d/phase-6-observability
systemctl reload cron  # or: launchctl unload/load on macOS
```

### Create log directory:

```bash
mkdir -p ~/vaults/ark/logs
chmod 755 ~/vaults/ark/logs
```

### Manual test run:

```bash
cd ~/vaults/ark
npx ts-node observability/phase-6-daemon.ts
npx ts-node observability/phase-6-daemon-extended.ts
```

---

## Part 4: Wire Phase 7 Tier Resolver (1 hour)

### In `new-project-bootstrap-v2.ts`, replace hardcoded MODEL_PROFILES:

```typescript
// BEFORE (hardcoded)
const tier = task.cached ? 'haiku' : 'sonnet';

// AFTER (dynamic)
import { DynamicModelRegistry } from './query-brain';

const registry = new DynamicModelRegistry();
const recommendation = await registry.resolveTask(taskCharacteristics);
const tier = recommendation.model;
```

### Update `query-brain.ts` to import registry:

```typescript
export { DynamicModelRegistry } from '../observability/phase-7-model-registry';
```

### Test tier resolver:

```bash
cd ~/vaults/ark
npx ts-node observability/phase-7-multi-model-resolver.ts
# Should output model recommendations for 5 demo tasks
```

---

## Part 5: First Customer Onboarding (1 day)

### Prepare for Customer A (example):

```bash
# Create new repo structure
mkdir -p ~/code/customerA-servicedesk/{.parent-automation,.planning,src}

# Copy brain snapshot
cp -r ~/code/strategix-servicedesk/.parent-automation/brain-snapshot \
  ~/code/customerA-servicedesk/.parent-automation/

# Create bootstrap decision log
touch ~/code/customerA-servicedesk/.planning/bootstrap-decisions.jsonl

# Initialize query-brain and bootstrap
cp ~/code/strategix-servicedesk/.parent-automation/query-brain.ts \
   ~/code/customerA-servicedesk/.parent-automation/
cp ~/code/strategix-servicedesk/.parent-automation/new-project-bootstrap-v2.ts \
   ~/code/customerA-servicedesk/.parent-automation/
```

### Run bootstrap:

```bash
cd ~/code/customerA-servicedesk/.parent-automation
npx ts-node new-project-bootstrap-v2.ts \
  --project-type service-desk \
  --customer customerA \
  --project-name "Customer A Service Desk"
```

### Verify decision log was recorded:

```bash
head -1 ~/.planning/bootstrap-decisions.jsonl
# Should have: timestamp, decisions, contradictions, lessons, tokens
```

### Run Phase 6 observability:

```bash
cd ~/vaults/ark
npx ts-node observability/phase-6-daemon.ts
# Should analyze Strategix + Customer A bootstraps
# Should detect: "ServiceDesk is universal decision (100% of projects)"
```

---

## Part 6: Monitor & Iterate (Ongoing)

### Weekly checklist:

- [ ] Phase 6 daemon ran successfully (check logs)
- [ ] Model registry updated (check model-weight-adjustments.md)
- [ ] Lesson effectiveness updated (check lesson-effectiveness.md)
- [ ] Token spend log updated (check token-spend-log.md)
- [ ] Any new patterns detected? (check cross-customer-insights.md)

### Monthly review:

- Verify cache hit rate (target: 70%+)
- Verify model distribution (target: Haiku 40%, Sonnet 35%, Codex 15%, Gemini 8%, Opus 2%)
- Check token spend per bootstrap (target: 12-13K)
- Review lesson effectiveness (any lessons <40% effective?)
- Update tier-selection-rules.md if needed

### If model releases happen:

- Phase 6 daemon auto-detects and updates registry
- Tier resolver automatically uses new models
- No manual intervention needed (unless strategic shift in model strategy)

---

## Deployment Order (Minimum Viable)

If time is limited, deploy in this order (each step is independent):

1. **Day 1:** Part 1 (env setup) + Part 2 (snapshots) → Ark becomes functional
2. **Day 2:** Part 3 (Phase 6 cron) → Self-improving loop starts
3. **Day 3:** Part 4 (Phase 7 resolver) → Dynamic model selection active
4. **Ongoing:** Part 5 (customer onboarding) → Ark compound improves

**Minimum to "live":** Parts 1-2 only. Snapshots work, bootstrap v2 works, loop just hasn't started yet.

---

## Rollback Plan

If anything breaks:

```bash
# Disable Phase 6 cron (kills all observability, but brain still works)
rm /etc/cron.d/phase-6-observability

# Disable Phase 7 dynamic models (falls back to hardcoded tier resolver)
# In new-project-bootstrap-v2.ts: revert to hardcoded MODEL_PROFILES

# Snapshots are read-only, no rollback needed
```

**Zero-downtime rollback:** All changes are additive. Just disable the daemon, don't delete anything.

---

## Success Criteria

✅ **Deployment is successful when:**

- [ ] Bootstrap v2 completes offline (no network calls)
- [ ] Phase 6 daemon runs weekly without errors
- [ ] Model registry updates weekly
- [ ] First customer project inherits Strategix brain
- [ ] Lesson effectiveness tracked for 2+ weeks
- [ ] Token spend averages 12-15K per bootstrap

✅ **Self-improving loop is working when:**

- [ ] Phase 6 detects cross-project patterns
- [ ] Lesson effectiveness increases (more lessons >80%)
- [ ] Cache hit rate improves (target: 70%+)
- [ ] New customers bootstrap 40% faster

---

## Support & Troubleshooting

### Bootstrap fails with "Snapshot not found"

```bash
# Verify snapshot exists
ls -la .parent-automation/ark-snapshot/SNAPSHOT-MANIFEST.json
```

### Phase 6 daemon doesn't run

```bash
# Check cron logs
log stream --predicate 'process == "cron"'  # macOS
journalctl -u cron  # Linux
```

### Model registry API fails

```bash
# Verify API keys
echo $ANTHROPIC_API_KEY
echo $GOOGLE_API_KEY

# Test API connectivity
curl -H "Authorization: Bearer $ANTHROPIC_API_KEY" \
  https://api.anthropic.com/v1/models
```

### Decision log not recorded

```bash
# Check permissions on .planning/
ls -la .planning/bootstrap-decisions.jsonl
# Should be writable by deployment user
```

---

## Next Steps After Deployment

1. **Monitor:** First week of Phase 6 daemon runs, observe patterns
2. **Iterate:** Adjust model weights based on actual cost/quality data
3. **Expand:** Onboard 2-3 customer projects
4. **Scale:** Once loop is stable, onboard all future customers
5. **Optimize:** Phase 7 weights will self-adjust based on Phase 6 learnings

---

**Ready to deploy!** All code is tested, documented, and committed.  
**Questions?** Check IMPLEMENTATION_COMPLETE.md for architecture overview.
