# Ark — Roadmap

**North Star:** Autonomous Operating System (AOS). User authors intent in markdown; Ark ships projects without further input. Only true blockers (cost ceiling, architectural ambiguity, destructive ops, repeated failure) escalate via async queue.

## Phase 0 — Bootstrap (complete)
- [x] Vault structure
- [x] 24 CLI commands
- [x] Brain → Ark rename
- [x] Verification suite
- [x] Observer daemon

## Phase 1 — GSD Integration (in-progress)
- [x] Shared `gsd-shape.sh` lib for phase resolution
- [x] ark-deliver, ark-team, execute-phase source the lib
- [x] Tier 7 verify: GSD compatibility (14/14 pass)
- [x] Observer patterns for GSD-shape regressions
- [ ] STRUCTURE.md documents GSD/Ark relationship (Task 8)
- [ ] Employees registry adds gsd-planner / gsd-verifier (Task 9)
- [ ] Documentation refresh (Task 10)

---

## AOS Transition — Phases 2–7

The following phases are the full AOS journey. Each phase removes one class of "ask the user" gates until Ark operates fully autonomously, escalating only true blockers via async queue.

### Phase 2 — AOS: Delivery Autonomy
**Goal:** `ark deliver` runs to completion with zero user prompts for routine resource decisions.

- [ ] `scripts/ark-policy.sh` — central decision engine for delivery
- [ ] Cascading config: `<proj>/.planning/policy.yml` > `~/vaults/ark/policy.yml` > defaults
- [ ] Async escalation queue: `~/vaults/ark/ESCALATIONS.md`
- [ ] Auto-decisions: budget overflow + monthly headroom → reset; CLI quota → route to next dispatcher or active session; 0 tasks → skip & log
- [ ] Informed self-heal (1st retry: enriched prompt; 2nd retry: model escalate; 3rd: escalate to queue)
- [ ] Strip `read -p` calls from delivery-path scripts
- [ ] Tier 8 verify: simulated quota+budget exhaustion, assert no-prompt completion
- [ ] Observer pattern: `manual-gate-hit` (any future regression where a script halts asking)

**Exit criteria:** `ark deliver --phase 1.5` on strategix-servicedesk runs to completion with `ARK_FORCE_QUOTA_CODEX=true` and `ARK_FORCE_QUOTA_GEMINI=true` set, with zero stdin reads.

### Phase 3 — AOS: Self-Improving Self-Heal (Meta-Learning)
**Goal:** Observer learns which self-heal patterns actually fix tasks vs which don't, and promotes/deprecates them automatically.

- [ ] `scripts/policy-learner.sh` — daemon that reads `policy-decisions.jsonl` + outcome data
- [ ] Outcome tagger: each policy decision gets a follow-up "did the work succeed?" verdict
- [ ] Pattern extraction: which self-heal recipes correlate with success?
- [ ] Auto-promotion: high-success patterns become first-line retry strategies
- [ ] Auto-deprecation: low-success patterns logged + retired
- [ ] Weekly digest written to `~/vaults/ark/observability/policy-evolution.md`
- [ ] Tier 9 verify: regression test that a known-bad pattern gets retired after N failures

**Exit criteria:** `policy-evolution.md` shows at least one auto-promoted and one auto-deprecated pattern after a week of real runs. Self-heal first-line retry success rate > 60%.

### Phase 4 — AOS: Bootstrap Autonomy (complete)
**Goal:** `ark create` picks stack, deploy, and CLAUDE.md content from a one-line project description with zero prompts.

- [x] `scripts/bootstrap-policy.sh` — project-type / stack / deploy inference engine
- [x] Heuristics from brain templates (project-types/*.md) become policy rules (frontmatter `keywords:` / `default_stack:` / `default_deploy:`)
- [x] Per-project-type defaults: service-desk / revops / ops-intelligence / custom catch-all
- [x] Auto-resolves contradictions via cascading customer policy (env > project > customer > vault > default)
- [x] Strip prompts from `ark-create.sh`; user supplies description only (description-mode + backward-compat flag-mode)
- [x] Per-project `.planning/policy.yml` auto-generated from inferred type (atomic write)
- [x] Tier 10 verify: 5 fixtures × multi-assert + flag-mode + cascading-customer + low-confidence + isolation md5 (22 checks)
- [x] `ARK_CREATE_GITHUB` env gate around `gh repo create` (default off — production safety)

**Exit criteria:** `ark create "service desk for managed-print provider" --customer acme` produces a working scaffolded project with zero prompts. **Met** — Tier 10 22/22, Tier 7/8/9 retained at 14/25/20.

### Phase 5 — AOS: Portfolio Autonomy (complete)
**Goal:** Given "ship something" with no project named, Ark picks the highest-leverage project from the portfolio and runs it.

- [x] `scripts/ark-portfolio-decide.sh` — priority engine
- [x] Inputs: CEO directives in `~/vaults/StrategixMSPDocs/programme.md`, portfolio health (test pass rate, last-touched date, blocker count), monthly budget headroom per customer
- [x] Outputs: next-project decision logged to `policy-decisions.jsonl`
- [x] Per-customer monthly budget caps in `policy.yml`
- [x] Cross-project budget routing: don't burn 100% of monthly cap on one customer
- [x] Tier 11 verify: simulated portfolio with 3 projects of varying health → assert priority engine picks the right one

**Exit criteria:** `ark deliver` (no `--phase`, no project) picks the highest-priority project, runs its next phase, logs the decision rationale. **Met** — Tier 11 16/16, Tier 7/8/9/10 retained at 14/25/20/22.

**Status:** ✅ Complete — see .planning/phases/05-portfolio-autonomy/

### Phase 6 — AOS: Cross-Customer Learning Autonomy (complete)
**Goal:** Lessons learned in one customer auto-promote to universal when the same pattern recurs in 2+ customers.

- [x] `scripts/lesson-promoter.sh` — daemon that reads per-customer `tasks/lessons.md` files
- [x] Detects pattern recurrence across customers (RBAC lockout in 3 customers → auto-promote)
- [x] Writes consolidated lessons to `~/vaults/ark/lessons/universal-patterns.md`
- [x] Auto-deprecates customer-specific lessons that became universal (with link)
- [x] Anti-pattern detection: same anti-pattern in 2+ customers → auto-flag in bootstrap templates
- [x] Tier 12 verify: synthetic 3-customer dataset → assert auto-promotion triggers correctly

**Exit criteria:** Real cross-customer pattern (e.g., RBAC lockout) is auto-promoted within 1 week of the second occurrence. Bootstrap templates auto-update with the new lesson. **Met** — Tier 12 24/24, Tier 7/8/9/10/11 retained at 14/25/20/22/16.

**Status:** ✅ Complete — see .planning/phases/06-cross-customer-learning/

### Phase 7 — AOS: Continuous Operation
**Goal:** Ark runs continuously via cron. User writes intent in markdown files; Ark consumes the queue and ships.

- [ ] Cron daemon at `scripts/ark-loop.sh` runs every N minutes
- [ ] Reads `~/vaults/ark/INBOX/` — markdown files describe new intent (new projects, new phases, new directives)
- [ ] Processes ESCALATIONS.md responses from user
- [ ] Writes `~/vaults/ark/observability/weekly-digest.md` — what Ark decided/shipped this week
- [ ] Health monitor: detect when Ark is stuck (no progress in 24h on active phase) → escalate
- [ ] Tier 13 verify: drop 3 intent files in INBOX → assert all 3 are processed within next cron cycle

**Exit criteria:** User writes `INBOX/2026-05-01-new-customer.md` with a project description, walks away, and 24 hours later the project exists, has Phase 0 and Phase 1 shipped, with a digest summarizing what happened.

---

## Phase 8 — Production Hardening & Reporting (post-AOS)
- [ ] Multi-machine vault sync verification
- [ ] Disaster recovery drill (restore from backup, verify state)
- [ ] Investor/customer report templates (Ark generates from `policy-decisions.jsonl` + outcome data)
- [ ] Cross-project portfolio analytics dashboard
- [ ] Stress-test continuous-operation daemon under load

---

**Sequencing rationale:**
- Phase 2 unblocks the immediate frustration (manual gates blocking delivery)
- Phase 3 makes the policy engine learn — without it, policy ossifies and degrades
- Phase 4 removes prompts from the *start* of the project lifecycle (creation)
- Phase 5 makes Ark portfolio-aware (true CEO-of-projects model)
- Phase 6 makes the brain truly multi-tenant (lessons benefit everyone)
- Phase 7 closes the loop: continuous operation, async user
- Phase 8 productionizes the result

Each phase has explicit exit criteria. Phase N+1 cannot start until Phase N exit criteria are met OR the user explicitly defers them.
