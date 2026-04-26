---
project_type: custom
source_project: none
template_version: 1.0
created: 2026-04-26
default_stack: custom
default_deploy: none
keywords:
---

# Custom / Scratch Project Bootstrap Template

Catch-all for projects that don't match a known type.

Used when:
- User invokes `ark create "scratchpad for X"` with no recognizable project-type keywords.
- Inference confidence is below threshold and user accepts the escalation by overriding to `--type custom`.

Stack: minimal — `package.json` only (or `go.mod`, etc., depending on user override).
Deploy: none. User must explicitly set `--deploy` if they want one.

No project-section / purpose-section / scope-section guidance — this template intentionally provides no opinions, because the project's purpose is unknown.
