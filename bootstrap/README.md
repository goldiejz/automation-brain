# Bootstrap — Templates & Decision Support

Templates, checklists, and guides for bootstrapping new projects, extracted from successful Strategix + customer bootstraps.

## Structure

- **project-types/** — Templates for different project archetypes
  - `service-desk-template.md` — ITIL service desk (from Strategix servicedesk + future customer instances)
  - `revops-template.md` — RevOps / sales operations (from Strategix crm)
  - `ops-intelligence-template.md` — Operations dashboard (from Strategix ioc)
  - `custom-type-template.md` — For novel project types (fill in as needed)

- **vault-structure/** — Directory templates for different domains
  - `minimum-vault.md` — Universal stub folders + purposes
  - `domain-specific-vaults.md` — MSP vaults vs marketplace vaults vs SaaS platform vaults

- **claude-md-sections.md** — Reusable CLAUDE.md sections (13 standard sections with content from successful projects)

- **anti-patterns.md** — Common mistakes in bootstrap with L-NNN citations
  - "Inline RBAC → cite L-018"
  - "Unsuffixed currency columns → cite L-021"
  - "No contradiction pass → cite L-012"

- **contradiction-checklist.md** — Decision points and conflict resolution rules learned across all bootstraps

## Using Bootstrap Templates

1. **New service desk project?** → Load `service-desk-template.md` + `minimum-vault.md`
2. **Revops platform?** → Load `revops-template.md` + `domain-specific-vaults.md` (SaaS section)
3. **Custom type?** → Load `custom-type-template.md` + ask brain for similar projects

Each template includes:
- Pre-filled CLAUDE.md sections (copy-paste ready)
- Vault skeleton (folder structure)
- Task surface template (`tasks/todo.md`, `tasks/lessons.md`)
- Contradiction checklist (pre-populated for that project type)
- Integration diagram (how this project connects to other projects)

---

*Templates established 2026-04-25*
