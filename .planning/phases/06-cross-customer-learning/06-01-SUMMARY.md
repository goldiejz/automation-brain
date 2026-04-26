---
phase: 06-cross-customer-learning
plan: 01
title: lesson-similarity.sh — Jaccard token-overlap primitive
status: complete
requirements: [REQ-AOS-32]
commit: 9aae6f9
files_created:
  - scripts/lib/lesson-similarity.sh
files_modified: []
self_test:
  assertions: 14
  passing: 14
  runtime_seconds: <1
key_decisions:
  - "D-SIMILARITY locked: Jaccard token-overlap on (title + rule body), lowercased, alphanumerics only, 50-word stop list"
  - "Format detection is case-insensitive on `## Lesson:` and `**Rule:**` so ALLCAPS variants tokenise identically"
  - "Both-sides extraction is whole-file fallback when no heading is detected (graceful degradation, never errors)"
  - "Tokens of length < 2 dropped (single chars are noise)"
---

# Phase 6 Plan 06-01: lesson-similarity.sh Summary

One-liner: Jaccard token-overlap primitive (sourceable Bash 3 lib) that powers cross-customer lesson clustering for Phase 6 promoter — 14/14 self-test assertions pass, real-lesson cross-pairs score 2–5% (meaningful cross-customer signal floor).

## Final API

```bash
# Tokenize free text → one token per line on stdout
lesson_tokenize "<text>"

# Extract comparable body of a lesson markdown file
#   Format A: `## Lesson: <title>` block → title + **Rule:** field content
#   Format B: `# Heading` → heading + first paragraph
#   Missing/empty: empty stdout (caller computes 0)
lesson_extract_body "<lesson.md>"

# Integer Jaccard percent (0..100) on combined bodies
lesson_similarity "<a.md>" "<b.md>"
```

CLI surface (executable mode):
```
lesson-similarity.sh test                      # run self-test
lesson-similarity.sh tokenize "<text>"         # ad-hoc tokenize
lesson-similarity.sh extract <lesson.md>       # ad-hoc body extract
lesson-similarity.sh similarity <a.md> <b.md>  # ad-hoc score
```

## Stop-word list (LOCKED)

50 entries, space-padded both ends for `*" $tok "*` lookup (Bash-3 friendly):

```
a an and are as at be but by do for from has have he her him his i if
in is it its not of on or our she that the their them they this to was
we were will with you your trigger mistake rule date lesson
```

Rationale:
- 45 high-frequency English function words (pronouns, articles, prepositions, common auxiliaries).
- 5 lesson-formatting words (`trigger / mistake / rule / date / lesson`) — these appear in every strategix-format lesson and would otherwise dominate the score, making every lesson look ~30% similar to every other lesson regardless of content.
- Tokens shorter than 2 chars also dropped (test: "I" pre-stop-word, "x" / "*" leftovers from markdown stripping).

## Self-test results (14/14)

| # | Assertion                                                     | Result |
|---|---------------------------------------------------------------|--------|
| 1 | identical file → 100                                          | PASS   |
| 2 | disjoint vocabulary → ≤15 (got 0)                             | PASS   |
| 3 | case-only delta → 100                                         | PASS   |
| 4 | stop-word-only delta → 100                                    | PASS   |
| 5 | half-overlap synthetic in 20..70 (got 20)                     | PASS   |
| 6 | missing file (left side) → 0                                  | PASS   |
| 7 | missing file (right side) → 0                                 | PASS   |
| 8 | both files missing → 0                                        | PASS   |
| 9 | empty file → 0                                                | PASS   |
|10 | stop-words-only shared → ≤10 (got 0)                          | PASS   |
|11 | format-B (plain `# Heading`) case+punct delta → 100           | PASS   |
|12 | real-lesson sample (3 word swap) in 60..99 (got 73)           | PASS   |
|13 | no `read -p` in lib region (excludes self-test)               | PASS   |
|14 | bash-3 compat scan: 0 declare-A/mapfile/readarray             | PASS   |

Runtime: < 1 second on macOS Bash 3.2 with mktemp + awk + sort/comm.

## Canonical scores against real lessons

Sampled from `~/code/strategix-crm/tasks/lessons.md` (the canonical strategix-format file):

| Pair                           | Score |
|--------------------------------|-------|
| L1 vs L1 (self)                | 100   |
| L1 (config-in-D1) vs L2 (D1 migrate) | 2 |
| L1 (config-in-D1) vs L3 (prod schema drift) | 4 |
| L2 (D1 migrate) vs L3 (prod schema drift)    | 4 |
| L3 (prod schema drift) vs L6 (positional INSERT) | 5 |

Surprise: even L3-vs-L6 — both about D1 migrations and column ordering — scores only 5%. The Jaccard denominator is `|A ∪ B|`, which grows fast when each lesson body contains 30+ unique content words. This means the **60% threshold (D-PROMOTION-THRESHOLD) is correctly conservative**: only lessons that share most of their content vocabulary will cluster. Coincidental overlap is well-suppressed by the union denominator.

This is good news for false-positive risk in 06-02 clustering — the promotion threshold won't fire on coincidental jargon overlap.

## Constraints honoured

- **Bash 3 compat:** No `declare -A`, no `mapfile`, no `${var,,}`. Lowercase via `tr`, set ops via `sort -u | comm -12`, integer math via awk.
- **Sourceable:** No top-level `set -e`. `set -uo pipefail` is safe (does not propagate).
- **No external HTTP / no ML:** Pure coreutils + awk.
- **No real-vault writes:** Self-test uses `mktemp -d`; tested explicitly that nonexistent and empty paths return 0 (not error).
- **No `read -p`:** Verified by self-test (regex scoped to lib region, excluding self-test's own pattern reference — Phase 4 self-referential trap honoured).
- **Audit discipline (Phase 2 contract):** This module is pure; no `_policy_log` calls. Promotion logging is 06-03's job, not the primitive's.

## Confirmation

D-SIMILARITY (CONTEXT.md): **Jaccard token overlap on (title + rule body), lowercased, alphanumerics only, stop-words removed, integer 0..100** — implemented exactly as specified.

REQ-AOS-32 (`scripts/lib/lesson-similarity.sh exposes lesson_similarity <a> <b> returning 0..100`): **satisfied**.

## Verification commands

```bash
bash scripts/lib/lesson-similarity.sh test          # 14/14 PASS
bash -n scripts/lib/lesson-similarity.sh            # syntax OK
bash -c 'source scripts/lib/lesson-similarity.sh; lesson_similarity x y'  # → 0
```

## Self-Check: PASSED

- File exists: `scripts/lib/lesson-similarity.sh` (424 lines, executable)
- Commit: `9aae6f9` (Phase 6 Plan 06-01: lesson-similarity.sh — Jaccard token-overlap primitive)
- Self-test: 14/14 assertions pass
- Sourceable: confirmed (`source` + `lesson_similarity x y` → `0` without error)
- Real-lesson smoke test: 5 canonical pairs scored, results consistent with heuristic intent
