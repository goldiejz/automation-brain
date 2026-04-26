# Phase 06.5 — CEO Dashboard — Plan Index

This phase is split into 7 plans across 5 waves. Two-tier delivery:
**Tier A** (Bash, ships first) gives immediate value. **Tier B** (Rust TUI) follows.
Phase 6.5 sits between Phase 6 (just shipped) and Phase 7 (Continuous Operation,
which will *consume* this dashboard to surface async progress).

| Plan    | Title                                                                                   | Wave | Depends on            | Tier | Files modified |
|---------|-----------------------------------------------------------------------------------------|------|-----------------------|------|----------------|
| 06.5-01 | scripts/ark-dashboard.sh — bash dashboard, all 7 sections, ANSI-colored, <2s            | 1    | —                     | A    | scripts/ark-dashboard.sh |
| 06.5-02 | scripts/ark dispatcher — `ark dashboard` subcommand + `--tui` routing                   | 2    | 06.5-01               | A/B  | scripts/ark |
| 06.5-03 | scripts/ark-dashboard/ — Rust TUI scaffold (Cargo.toml, src/main.rs, dependencies)      | 2    | 06.5-01               | B    | scripts/ark-dashboard/{Cargo.toml,src/main.rs,.gitignore} |
| 06.5-04 | Rust TUI sections 1-3 (portfolio grid, escalations panel, budget summary)               | 3    | 06.5-03               | B    | scripts/ark-dashboard/src/{sections,db,app}.rs |
| 06.5-05 | Rust TUI sections 4-7 + live-refresh loop + keybindings                                 | 4    | 06.5-04               | B    | scripts/ark-dashboard/src/{sections,app,events}.rs |
| 06.5-06 | Tier 13 verify suite — synthetic seeded vault, all 7 sections asserted                  | 5    | 06.5-01, 06.5-05      | A+B  | scripts/ark-verify.sh |
| 06.5-07 | Docs close: STRUCTURE.md, REQ-DASH-01..08, STATE.md, ROADMAP.md, SKILL.md               | 5    | 06.5-06               | —    | STRUCTURE.md, .planning/REQUIREMENTS.md, .planning/STATE.md, .planning/ROADMAP.md, SKILL.md |

## Wave structure

- **Wave 1:** 06.5-01 alone (Tier A — bash dashboard. Ships immediately, gives the user value before the Rust TUI lands. Standalone script — no upstream deps.)
- **Wave 2:** 06.5-02 + 06.5-03 in parallel (subcommand wiring touches `scripts/ark` only; Rust scaffold creates `scripts/ark-dashboard/` only — disjoint files.)
- **Wave 3:** 06.5-04 (Rust sections 1-3 — needs the scaffold + db module from 06.5-03.)
- **Wave 4:** 06.5-05 (Rust sections 4-7 + live refresh — depends on the section component pattern established in 06.5-04.)
- **Wave 5:** 06.5-06 (Tier 13 verify — needs both tiers wired) → 06.5-07 (docs close — needs Tier 13 passing).

## Delivery sequencing rationale

1. **Wave 1 ships value on day 1.** `ark dashboard` (bash) gives the CEO a colored 7-section report from real vault data the moment 06.5-01 lands. User can use this for the entire Tier B build period. This is the "quick win" requirement from CONTEXT.md.
2. **Wave 2 unblocks both tiers simultaneously.** Subcommand wiring (06.5-02) lets `ark dashboard` call the bash script today and `ark dashboard --tui` call the Rust binary the moment it builds. Rust scaffold (06.5-03) is a parallel track that doesn't touch any existing file.
3. **Waves 3-4 build the TUI sections in two passes** because the section component pattern needs to exist (06.5-04) before sections 4-7 can reuse it idiomatically (06.5-05). The 2s live-refresh loop is the last thing wired so partial-build states stay observable via static screenshots.
4. **Tier 13 verify (06.5-06)** asserts both tiers against a synthetic seeded vault, including the read-only md5 invariant and the no-regression sweep on Tiers 7-12. Comes after both tiers are functional so it tests the real surface, not stubs.
5. **Docs close (06.5-07)** mints REQ-DASH-01..08 and flips ROADMAP/STATE only after Tier 13 passes. No premature "complete" claims.

## Two-tier delivery contract (locked from CONTEXT.md)

- **Tier A — Bash:** `ark dashboard` (no flag) — pull-style, prints colored report, exits. Single file (`scripts/ark-dashboard.sh`). Bash 3 compat (macOS). Reuses ANSI palette from `ark-verify.sh`. Read-only over `policy.db` via `sqlite3` CLI; over `ESCALATIONS.md`/`policy-evolution.md`/`universal-patterns.md`/`anti-patterns.md`/`verification-reports/*.md`/`<project>/.planning/STATE.md` via `awk`/`grep`.
- **Tier B — Rust TUI:** `ark dashboard --tui` — interactive, 2s polling refresh, vim keybindings (j/k/q/r/Enter). `ratatui` + `rusqlite` + `crossterm`, no async runtime. Single binary at `scripts/ark-dashboard/target/release/ark-dashboard`.

## Read-only invariant (locked)

Dashboard is **strictly read-only** over `policy.db`, `ESCALATIONS.md`, and all vault files. The one exception (mark-resolved) routes through the existing single-writer path (`ark escalations --resolve <id>`); the dashboard never writes audit rows or vault state itself. Tier 13 asserts via real-vault md5 invariant on `policy.db`, `ESCALATIONS.md`, `universal-patterns.md`, `anti-patterns.md`.

## 7 sections (priority order, both tiers)

1. **Portfolio grid** — projects × current phase × last activity × health (green/yellow/red) — discovers projects via `${ARK_PORTFOLIO_ROOT:-~/code}` walk-depth-3 looking for `.planning/STATE.md` (mirrors Phase 5 D-PORTFOLIO-SCOPE).
2. **Escalations panel** — counts of pending blockers by 4 true-blocker classes; list view with IDs.
3. **Budget summary** — per-customer monthly burn, headroom percent, ESCALATE_MONTHLY_CAP risk (reads `<project>/.planning/budget.json`; reuses `_portfolio_budget_headroom` semantics).
4. **Recent decisions stream** — last 50 rows from `policy.db` filterable by class.
5. **Learning watch** — patterns approaching promotion (≥3 customers, <60% similarity); recent promotions from `policy-evolution.md` + `universal-patterns.md`.
6. **Drift detector** — STATE.md vs disk reality (catches drift class 06-03 surfaced — 60s tolerance window, surfaces as INFO not RED).
7. **Tier health** — last verify report parsed from `~/vaults/ark/observability/verification-reports/*.md`.

## Requirements coverage

REQ-DASH-01..REQ-DASH-08 map 1:1 to the 8 acceptance criteria in CONTEXT.md.
IDs are minted in plan frontmatter; rows added to `.planning/REQUIREMENTS.md` by 06.5-07.

| Req         | Statement | Covered by |
|-------------|-----------|------------|
| REQ-DASH-01 | `scripts/ark-dashboard.sh` exists; `ark dashboard` invokes it | 06.5-01, 06.5-02 |
| REQ-DASH-02 | All 7 sections render with real data from this vault | 06.5-01, 06.5-04, 06.5-05 |
| REQ-DASH-03 | Read-only: real `policy.db` md5 unchanged before/after run | 06.5-01, 06.5-06 |
| REQ-DASH-04 | Bash version runs in <2s on a populated vault (61+ rows) | 06.5-01, 06.5-06 |
| REQ-DASH-05 | Rust TUI builds via `cd scripts/ark-dashboard && cargo build --release` | 06.5-03, 06.5-05 |
| REQ-DASH-06 | Rust TUI launches via `ark dashboard --tui` and refreshes live (2s poll) | 06.5-02, 06.5-05 |
| REQ-DASH-07 | Tier 13 verify: synthetic vault → assert each section's pass criterion | 06.5-06 |
| REQ-DASH-08 | Existing Tier 1-12 still pass (no regression) | 06.5-06 |

## Phase 2/3/4/5/6 lessons honored (avoid regression)

- **Single audit writer:** Dashboard READS only — never calls `_policy_log`. Mirrors Phase 2 NEW-B-2 + Phase 3 single-writer rule. The mark-resolved exception routes through existing `ark escalations --resolve` (single-writer path).
- **Bash 3 compat (macOS):** No `declare -A`, no `${var,,}`. Use `tr` for case folds, `awk` for parsing.
- **Real-vault md5 invariant:** Tier 13 captures `md5 policy.db ESCALATIONS.md universal-patterns.md anti-patterns.md` before + after every dashboard invocation; assertion that md5 unchanged. Mirrors Phase 5 NEW-W-1 + Phase 6 06-05.
- **No `read -p` in delivery-path:** Dashboard scripts contain zero `read -p`. Tier 13 includes a regression check (`grep -nE '^[^#]*read -p' scripts/ark-dashboard.sh` MUST be empty).
- **Phase-4 GitHub-incident lesson:** Tier 13 fixture MUST NOT touch real `~/code/`, real `~/vaults/ark/`, or invoke any `gh` command. Use `mktemp -d` portfolio + vault roots; set `ARK_PORTFOLIO_ROOT=$TMP_PORTFOLIO`, `ARK_HOME=$TMP_VAULT`. Real-vault-write attempt is a test failure.
- **Atomic writes:** Dashboard writes nothing. (Read-only invariant satisfies this trivially.)
- **Indexed queries:** All Bash + Rust SQL queries use indexes added in Phase 2.5 (`idx_decisions_ts`, `idx_decisions_class`, `idx_decisions_outcome`, `idx_decisions_pattern`).

## Locked decisions from CONTEXT.md (verbatim — do not revisit)

- **D-DASH-TIER-A-FIRST:** Bash version ships before Rust TUI. Phase exit gate requires both, but Tier A delivers user value on Wave 1.
- **D-DASH-READONLY:** Dashboard never writes to `policy.db`, `ESCALATIONS.md`, or any vault file. Mark-resolved actions invoke existing `ark escalations --resolve <id>` (single-writer path).
- **D-DASH-INVOCATION:** `ark dashboard` (no flag) → Tier A bash. `ark dashboard --tui` → Tier B Rust binary.
- **D-DASH-RUST-DEPS:** `ratatui` + `rusqlite` + `crossterm` only. No async runtime. No `serde_derive` beyond what's literally needed for `rusqlite::Row` mapping.
- **D-DASH-RUST-BUILD:** `cd scripts/ark-dashboard && cargo build --release`. Output binary path: `scripts/ark-dashboard/target/release/ark-dashboard`. Dispatcher invokes it directly (no install step).
- **D-DASH-REFRESH:** Rust TUI polls `policy.db` every 2s using a non-blocking `crossterm::event::poll(2s)` loop. WAL mode handles read-during-write natively.
- **D-DASH-DRIFT-TOLERANCE:** Drift detector treats STATE.md vs disk diffs within 60s as INFO (not RED) — STATE.md hand-edits during active phases trip false-positive otherwise.
- **D-DASH-DEGRADE:** Color-friendly terminal degradation: if `tput colors` < 8, fall back to no-ANSI plain output. No 256-color hard requirement.
- **D-DASH-OUT-OF-SCOPE:** Web dashboard, push notifications, multi-machine sync, historical trend charting, employees plugin UI — all explicitly Phase 8 candidates. Do NOT add to v1.
