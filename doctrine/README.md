# Doctrine — Universal Standards & Governance

Universal principles and standards that apply to all projects (Strategix and all customer projects).

## Structure

- **bootstrap-standard.md** — Standard bootstrap order and universal checklist
  - 14 gate items (CLAUDE.md exists, tasks/ exists, vault skeleton exists, etc.)
  - 12-step execution order (research, plan, scaffold, contradiction-check, etc.)
  - Applies across all projects regardless of type or customer

- **project-standard.md** — Required files, directory structure, conventions
  - Symlink/reference to `~/vaults/StrategixMSPDocs/project-standard.md` (canonical Strategix standard)
  - Applies to all new projects; establishes naming, structure, discipline rules

- **shared-conventions.md** — Rules applying to all projects
  - RBAC centralization (single source of truth per repo)
  - Currency/duration column suffixes (_zar, _usd, _minutes, _seconds)
  - Immutability and data structure patterns
  - Truth hierarchy (STATE.md → ALPHA.md → PROJECT.md → CLAUDE.md → vault docs)
  - Doc/code drift is a defect, not a footnote

- **glossary.md** — Terminology and definitions
  - L-NNN = Lesson (captured rule preventing specific mistake)
  - D-NNN = Design decision or drift (findings)
  - P-NNN = Pattern (cross-project meta-insight)
  - Phase = Bootstrap phase (P1, P2, P3) or implementation phase
  - Brain = This Obsidian vault (automation-brain)

## Authority Hierarchy

1. **Project `.planning/STATE.md`** — Primary implementation truth
2. **Project `.planning/ALPHA.md`** — Gate definition
3. **Project `.planning/PROJECT.md`** — Durable intent
4. **Project `CLAUDE.md`** — Repo-specific working instructions
5. **This doctrine** (`bootstrap-standard.md`, `shared-conventions.md`) — Universal standards
6. **Vault reference docs** — Training and historical context

Never quote doctrine as live state. Always verify against project STATE.md.

---

*Doctrine established 2026-04-25*
