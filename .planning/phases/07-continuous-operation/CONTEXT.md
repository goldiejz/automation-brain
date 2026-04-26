# Phase 7 — AOS: Continuous Operation — Context

## Why this phase exists

Phases 2–6.5 made every individual AOS decision autonomous: delivery dispatch, self-healing, bootstrap, portfolio routing, cross-customer learning, dashboard visibility. But each invocation still requires you to *trigger* `ark deliver` or `ark dashboard`.

Phase 7 closes that loop: a cron daemon reads `~/vaults/ark/INBOX/` markdown intent files, processes them, and runs `ark deliver` / `ark create` autonomously. You author intent in markdown, walk away, return to find Ark has shipped projects (or escalated true blockers via `ESCALATIONS.md`).

This is the final AOS phase from the original roadmap.

## Position in AOS roadmap

Phase 7 of the 6-phase journey (Phase 6.5 was inserted; original ROADMAP had Phase 7 as the closer). After this:
- **Phase 8** — Production hardening + reporting (per original ROADMAP). Not part of AOS itself; productionizes the result. Independent of Phase 7.

Phase 7 needs everything Phases 2-6.5 built:
- Policy engine (Phase 2) for dispatch decisions
- Self-improving learner (Phase 3) for outcome tagging across continuous runs
- Bootstrap autonomy (Phase 4) so new INBOX projects auto-scaffold
- Portfolio autonomy (Phase 5) so the daemon picks the next project to ship
- Cross-customer learning (Phase 6) so insights propagate
- Dashboard (Phase 6.5) so you can see what the daemon's doing without re-engaging

## Architectural decisions (autonomous defaults — no grilling)

### 1. Daemon mechanism — launchd (macOS-native)
- macOS launchd plist at `~/Library/LaunchAgents/com.ark.continuous.plist`
- Runs every N minutes (default 15) — configurable via `policy.yml::continuous.tick_interval_min`
- User-level agent (not system daemon) — runs only when user logged in
- Survives reboots (loaded on login)
- Logs to `~/vaults/ark/observability/continuous-operation.log`

### 2. INBOX format — markdown files with frontmatter
```yaml
---
intent: new-project | new-phase | resume | promote-lessons
customer: acme         # optional; defaults to scratch
priority: high|medium|low  # optional; portfolio decide-engine respects
---
# One-line description

(Optional body with more context, references, links)
```

Filename convention: `YYYY-MM-DD-short-slug.md`

### 3. Processing model — read, process, archive
- Daemon scans `~/vaults/ark/INBOX/*.md` on each tick
- For each file:
  - Parse frontmatter
  - Dispatch based on `intent`:
    - `new-project` → invoke `ark create "$description" --customer "$customer"`
    - `new-phase` → invoke `ark deliver --phase $N` (project resolved from frontmatter or path)
    - `resume` → run `ark deliver` (let portfolio engine pick)
    - `promote-lessons` → run `ark promote-lessons`
  - On success → move file to `~/vaults/ark/INBOX/processed/<date>/`
  - On failure → escalate via existing escalation queue + leave file in INBOX with `.failed` extension

### 4. Health monitor — detect stuck phases
- After each tick, scan all projects in portfolio for "stuck phase" signal:
  - Active phase with no STATE.md modification in >24h AND no recent commits
  - Phase with verification report failures going up consistently
- Stuck phases → `_policy_log "continuous" "STUCK_PHASE_DETECTED" ...` + escalate via ESCALATIONS.md
- 3 consecutive ticks (default 45min) of stuck → escalation fires once (idempotent dedupe)

### 5. Weekly digest
- Cron-triggered separate launchd job (Sunday 9am)
- Aggregates the week's `policy-decisions.jsonl` into `~/vaults/ark/observability/weekly-digest-YYYY-WW.md`
- Sections: projects shipped · phases completed · escalations resolved · learner promotions · budget burn · dashboard URL
- Optional: mail/Slack push if configured (out of scope for v1)

### 6. Safety rails (the "I'm not watching" lessons learned)
- **Hard daily token cap:** `policy.yml::continuous.daily_token_cap` (default 50K). When exceeded, daemon SUSPENDS until next day. Logged via `_policy_log "continuous" "DAILY_CAP_HIT" ...`
- **Run-state lock:** `~/vaults/ark/.continuous.lock` (mkdir-style) prevents two ticks from overlapping
- **Bypass kill-switch:** `~/vaults/ark/PAUSE` file → daemon skips all ticks; user creates this to halt without uninstalling
- **Auto-pause on N consecutive failures:** if 3 ticks in a row escalate, auto-create PAUSE file + escalate to user

## Acceptance criteria (Phase 7 exit)

1. `scripts/ark-continuous.sh` exists; sourceable; self-test passes
2. INBOX intent file (`~/vaults/ark/INBOX/sample-new-customer.md`) is processed on next tick → moved to `processed/<date>/`
3. launchd plist at `~/Library/LaunchAgents/com.ark.continuous.plist` is installable via `ark continuous install`
4. `ark continuous status` shows last tick, next tick, recent decisions, daily token used
5. `ark continuous pause` creates PAUSE file; `ark continuous resume` removes it
6. Health monitor detects synthetic stuck phase + escalates after 3 ticks
7. Weekly digest generates `~/vaults/ark/observability/weekly-digest-2026-WW.md` with all sections populated
8. Tier 14 verify: synthetic INBOX with 3 intent files → assert all processed correctly
9. Existing Tier 1–13 still pass

## Constraints

- macOS launchd (Linux/cron support deferred — single-laptop scope)
- Bash 3 compat (macOS)
- Single-writer audit log preserved
- All decisions audit-logged via `_policy_log "continuous" ...`
- No new `read -p` in any continuous-operation script
- mkdir-locks for cross-process safety (no flock — macOS doesn't ship it natively)
- Atomic INBOX file moves (move-after-process; never partial-state)
- Daily token cap is the hard ceiling — even with monthly headroom, daemon stops at daily cap

## Out of scope

- Linux cron variants (Phase 8 if user goes Linux)
- Slack/email push notifications (Phase 8 — for v1, ESCALATIONS.md is the queue)
- Multi-machine coordination (single-laptop)
- Real-time / event-driven processing (15-min cron is the cadence)
- Self-modifying daemon code (the daemon doesn't promote its own patterns to itself; that's Phase 3's job for delivery patterns, not for continuous operation)

## Risks

1. **Runaway daemon burns through budget** — mitigated by daily token cap + auto-pause on 3 consecutive escalations
2. **INBOX intent malformed** — file moved to `processed/<date>/.malformed/` with reason logged; not silently dropped
3. **Daemon overlaps with manual `ark deliver`** — mitigated by mkdir-lock; manual takes precedence (daemon defers to next tick)
4. **launchd plist gets out of sync with script changes** — `ark continuous install` is idempotent; `ark continuous reinstall` regenerates from current script

## Success signal (the "intent → ship" demo)

```bash
# 1. Drop an intent file
cat > ~/vaults/ark/INBOX/2026-05-01-acme-helpdesk.md <<EOF
---
intent: new-project
customer: acme-corp
priority: high
---
# Service desk for acme-corp with email-to-ticket and SLA tracking
EOF

# 2. Walk away. Within 24h:
#    - Daemon ticks, parses intent, calls `ark create "service desk..." --customer acme-corp`
#    - Project scaffolds with bootstrap-policy inference (Phase 4)
#    - Phase 0 + 1 plans + executes via portfolio dispatch (Phase 5)
#    - Lessons cluster, promote (Phase 6)
#    - Dashboard updates live (Phase 6.5)
#    - Daemon archives INBOX file → processed/2026-05-01/

# 3. Return. ark dashboard --web shows: 1 new project, Phase 1 shipped, weekly digest queued.
#    INBOX is empty (or has only un-acted-on items).
```

If THAT works, Ark is fully autonomous. Phase 7 closes AOS.
