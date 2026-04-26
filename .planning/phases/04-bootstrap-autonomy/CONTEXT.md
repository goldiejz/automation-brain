# Phase 4 — AOS: Bootstrap Autonomy — Context

## Why this phase exists

Phase 3 made delivery self-improving. Phase 4 closes the next manual gate: **project bootstrap**.

Today, `ark create` requires a sequence of explicit choices — `--type`, `--stack`, `--deploy`, `--customer`, `--path`. Each is a manual gate. The user's mandate from day one was *"I describe a project, Ark ships it"* — that has to start with creation, not just delivery.

Phase 4 makes `ark create "service desk for managed-print provider"` produce a working scaffolded project with zero prompts.

## Position in AOS roadmap

This is Phase 4 of the 6-phase AOS journey. After this:
- Phase 5: Portfolio autonomy (Ark picks which project to ship next)
- Phase 6: Cross-customer learning autonomy
- Phase 7: Continuous operation (cron-driven INBOX consumption)

Phase 4 is the bookend to Phase 2: Phase 2 made *delivery* prompt-free; Phase 4 makes *creation* prompt-free. Together they cover the full AOS contract for a single project.

## Architectural decisions (autonomous defaults — no user grilling, per "Go don't stop")

### 1. Inference approach — Heuristic from project description
- One-line description → keyword match against `~/vaults/ark/bootstrap/project-types/*.md` templates
- Score each template by keyword overlap; highest-scoring template wins
- Confidence below threshold (e.g., 50% match) → escalate via ESCALATIONS.md as `architectural-ambiguity`
- No ML, no embeddings — pure heuristic counting. (Mirrors Phase 3 outcome-tagger style.)

### 2. Stack inference — Project-type defaults + override
- Each `project-types/*.md` template declares a default stack (e.g., service-desk → tanstack-router + d1 + workers + queues)
- Override via env or `policy.yml` `bootstrap.stack_override`
- New project types: scaffolded as "custom" with minimal stack (node-cli, no deploy)

### 3. Deploy target — Inferred from project type + customer policy
- service-desk / revops / ops-intelligence → cloudflare (existing Strategix default)
- custom / scratch → none
- Customer-level override in `~/vaults/ark/customers/<customer>/policy.yml` (creates the dir on first project)

### 4. Customer detection — From description, fallback to "scratch"
- "for `<customer-name>`" → use customer-name; create customer dir if new
- No customer phrase → treat as `scratch` (no commit to a customer-tagged path)
- Customer policy.yml inherits from project-type template

### 5. Per-project policy.yml — Auto-generated
- After creation, write `<project>/.planning/policy.yml` with inferred type + stack + deploy
- Phase 2's cascading config resolver already reads this; Phase 4 just generates it

### 6. CLAUDE.md generation
- Base template at `~/vaults/ark/bootstrap/claude-md-template.md` (universal sections)
- Project-type addendum from `project-types/*.md`
- Customer-specific footer (RBAC, deploy targets) from customer policy if exists
- Atomic write; never overwrites existing CLAUDE.md without confirmation (destructive op → ESCALATIONS)

## Single-writer / audit-trail discipline (Phase 3 pattern)

Every Phase 4 decision audit-logged via `_policy_log "bootstrap" "<DECISION>" "<reason>" "<context>"` so Phase 6 can promote cross-customer patterns.

Class taxonomy used:
- `bootstrap` (decision class) — project type / stack / deploy / customer inferred
- `escalation` (when confidence below threshold)

## Acceptance criteria (Phase 4 exit)

1. `scripts/bootstrap-policy.sh` exists; sourceable; self-test passes
2. `ark create "<one-line description>" --customer <name>` runs to completion with zero prompts
3. Inferred type / stack / deploy logged via `_policy_log "bootstrap" ...` with full context
4. Per-project `.planning/policy.yml` auto-generated with inferred values
5. CLAUDE.md atomically written from base + project-type addendum + customer footer
6. Existing `ark create` flag-based invocation still works (backward compat)
7. Tier 10 verify: scaffold 5 different project types from 1-line descriptions, no prompts, all produce valid CLAUDE.md + policy.yml + project dir
8. Existing Tier 1–9 still pass (no regression)

## Constraints

- Bash 3 (macOS)
- Single writer for audit log (`_policy_log` only; never inline INSERT)
- No new `read -p` in delivery-path or bootstrap-path scripts
- Backward compat: existing `ark create` flag invocation continues to work; Phase 4 only adds the description-based path
- Atomic writes (CLAUDE.md, policy.yml, package.json)
- Customer dir created on first project for that customer; idempotent

## Out of scope

- ML/LLM-based inference (heuristic only)
- Multi-language project types beyond what brain templates already support
- Customer billing / contract management
- Cross-customer template promotion (that's Phase 6)
- Continuous-operation INBOX (Phase 7)

## Risks

1. **Bad inference creates wrong scaffold** — mitigated by ESCALATIONS for low-confidence; user reviews queue before accepting. CLAUDE.md atomic-write prevents partial state.
2. **Project-type templates drift** — mitigated by Phase 6 cross-customer promotion (later); for now, manual template review.
3. **Customer dir creation collisions** — mitigated by mkdir-lock pattern from Phase 3.
