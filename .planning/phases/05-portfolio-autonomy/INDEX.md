# Phase 05 — AOS: Portfolio Autonomy — Plan Index

This phase is split into 7 plans across 5 waves. Wave-1 builds the priority engine
foundation (`ark-portfolio-decide.sh`). Wave 2 fans out three independent extensions
(budget reader, CEO directive parser, audit/cool-down). Waves 3-5 wire and verify.

| Plan   | Title                                                                                | Wave | Depends on            | Files modified |
|--------|--------------------------------------------------------------------------------------|------|-----------------------|----------------|
| 05-01  | ark-portfolio-decide.sh — discovery + scoring + winner selection + self-test         | 1    | —                     | scripts/ark-portfolio-decide.sh |
| 05-02  | Per-customer monthly-budget reader; over-cap → DEFERRED_BUDGET                       | 2    | 05-01                 | scripts/ark-portfolio-decide.sh, scripts/lib/policy-config.sh (read-only) |
| 05-03  | CEO directive parser (programme.md `## Next Priority`) + override logic              | 2    | 05-01                 | scripts/ark-portfolio-decide.sh |
| 05-04  | Audit log: `_policy_log "portfolio"` + 24h backoff cool-down for DEFERRED projects   | 2    | 05-01                 | scripts/ark-portfolio-decide.sh |
| 05-05  | ark-deliver.sh no-args path + ark dispatcher routing                                 | 3    | 05-01..05-04          | scripts/ark-deliver.sh, scripts/ark |
| 05-06  | Tier 11 verify suite — synthetic 3-project / 2-customer fixture                      | 4    | 05-05                 | scripts/ark-verify.sh |
| 05-07  | STRUCTURE.md AOS Phase 5 contract; REQ-AOS-23..30; STATE.md + ROADMAP.md + SKILL.md  | 5    | 05-06                 | STRUCTURE.md (or vault equivalent), .planning/REQUIREMENTS.md, .planning/STATE.md, .planning/ROADMAP.md, SKILL.md (best-effort) |

## Wave structure

- **Wave 1:** 05-01 (priority engine — every other plan extends or consumes it)
- **Wave 2:** 05-02, 05-03, 05-04 (parallel — each touches a disjoint section of `ark-portfolio-decide.sh` via append-only function blocks; see file-conflict note)
- **Wave 3:** 05-05 (dispatcher + ark-deliver.sh no-args path; needs all engine extensions live)
- **Wave 4:** 05-06 (Tier 11 verify; needs full wiring)
- **Wave 5:** 05-07 (docs + requirement minting)

## Wave-2 file-conflict note

05-02, 05-03, 05-04 all extend `scripts/ark-portfolio-decide.sh`, but each owns a
disjoint named-function section delimited by sentinel comments laid down in 05-01:

```
# === SECTION: budget-reader (Plan 05-02) ===
# ... 05-02 owns this region ...
# === END SECTION: budget-reader ===

# === SECTION: ceo-directive (Plan 05-03) ===
# ... 05-03 owns this region ...
# === END SECTION: ceo-directive ===

# === SECTION: audit-and-cooldown (Plan 05-04) ===
# ... 05-04 owns this region ...
# === END SECTION: audit-and-cooldown ===
```

05-01 lays the empty sentinels in the file footer; 05-02/03/04 fill them in
parallel by inserting between `# === SECTION: X ===` and `# === END SECTION: X ===`.
No git merge conflict because the regions are disjoint.

## Requirements coverage

REQ-AOS-23..REQ-AOS-30 map 1:1 to the 8 Phase 5 acceptance criteria in CONTEXT.md.
IDs are minted in plan frontmatter; rows added to `.planning/REQUIREMENTS.md` by 05-07.

| Req         | Statement | Covered by |
|-------------|-----------|------------|
| REQ-AOS-23  | scripts/ark-portfolio-decide.sh exists; sourceable; self-test passes | 05-01 |
| REQ-AOS-24  | `ark deliver` (no args) picks highest-priority project; zero prompts | 05-05 |
| REQ-AOS-25  | Decision audit-logged via `_policy_log "portfolio" "SELECTED" ...` with full priority breakdown | 05-04, 05-05 |
| REQ-AOS-26  | Per-customer monthly budget caps honored; over-cap customers DEFERRED | 05-02 |
| REQ-AOS-27  | CEO directive override: explicit priority in programme.md beats heuristic | 05-03 |
| REQ-AOS-28  | Existing `ark deliver --phase N` (single project, current dir) unchanged (backward compat) | 05-05, 05-06 |
| REQ-AOS-29  | Tier 11 verify: synthetic 3-project / 2-customer fixture with varying priority signals | 05-06 |
| REQ-AOS-30  | Existing Tier 1–10 still pass (no regression) | 05-06 |

## Phase 2/3/4 lessons honored (avoid regression)

- **Single audit writer:** Portfolio class entries go through `_policy_log` from `ark-policy.sh`. No inline INSERTs. Mirrors Phase 2 NEW-B-2 + Phase 3 single-writer rule.
- **Bash 3 compat (macOS):** No `declare -A`, no `${var,,}`. Use `tr` for case folds, awk for parsing.
- **Isolated test vaults:** Tier 11 follows NEW-W-1 — `mktemp -d` for vault + portfolio root; never touch real `~/code/` or real `~/vaults/ark/`. Real DB md5 captured before/after; assertion that md5 unchanged.
- **No `read -p` in delivery-path:** 05-05 strips/avoids any prompt in the no-args branch; 05-06 includes a regression check.
- **Atomic file writes:** Any cool-down state files (if cached) written via `tmp + mv`.
- **Phase-4 GitHub-incident lesson:** Tier 11 fixture MUST NOT touch real `~/code/`, real `~/vaults/ark/customers/`, or invoke `gh repo create`. Use `mktemp -d` portfolio roots; set `ARK_PORTFOLIO_ROOT=$TMP_PORTFOLIO`, `ARK_HOME=$TMP_VAULT`. Real-vault-write attempt is a test failure.

## Locked decisions from CONTEXT.md (verbatim — do not revisit)

- **D-PORTFOLIO-SCOPE:** Project = directory containing `.planning/STATE.md`. Discovery walks `${ARK_PORTFOLIO_ROOT:-~/code}` to depth 3.
- **D-CUSTOMER-ATTR:** Customer read from `<project>/.planning/policy.yml::bootstrap.customer`; missing → `scratch` bucket (deprioritized but eligible).
- **D-PRIORITY-FORMULA:** `priority = stuckness * 3 + falling_health * 2 + (monthly_headroom > 20 ? 1 : 0) + ceo_priority * 5`. Pure heuristic; no ML.
- **D-DEFER-BUDGET:** Customer ≥ 80% of monthly cap → all their projects DEFERRED_BUDGET. Cross-customer cap = `(monthly_cap_total - already_used) / num_active_customers`.
- **D-DEFER-COOLDOWN:** Project DEFERRED in last 24h for same reason → skipped (no re-pick spam). Read from `class:portfolio decision:DEFERRED_*` audit history.
- **D-DEFER-HEALTHY:** Healthy projects (no stuckness, no falling health, headroom > 20) with no CEO priority → `DEFERRED_HEALTHY` (no work needed).
- **D-CEO-OVERRIDE:** Regex extract `## Next Priority\s*\n.*?(\w[\w-]+)` from `~/vaults/StrategixMSPDocs/programme.md`. Match → `ceo_priority=1` for that project; else 0. Fallback to heuristic if directive missing.
- **D-DECISION-CLASSES:** `class=portfolio` audit decisions: `SELECTED | DEFERRED_BUDGET | DEFERRED_HEALTHY | NO_CANDIDATE_AVAILABLE`.
- **D-COMPAT:** `ark deliver --phase N` from inside a project unchanged. Phase 5 ONLY adds the no-args branch.
- **D-TIE-BREAK:** Tied priority → most-recently-touched project wins (file mtime of `.planning/STATE.md`).
