# Ark Dash — Executive Dashboard

A Rust-based TUI dashboard for the Ark OS agentic operating system.

## What it shows

- **Projects** — All brain-integrated projects with phase, status, lifecycle, decisions, tokens, budget tier
- **Employees** — Pluggable agent roster (drop a JSON file in `vault/employees/` to add a new role)
- **Events** — Recent decisions, budget tier changes, sign-offs across all projects
- **Metrics** — Aggregate KPIs: total projects, employees, lessons, tokens; per-project budget gauges

## Install Rust (if not already installed)

```bash
# Via Homebrew (recommended for macOS):
brew install rust

# Or via rustup (the official installer):
# (You will need to run this manually — automated installs are blocked for security)
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Build

```bash
cd ~/vaults/ark/dashboard
cargo build --release
```

Binary output: `target/release/ark-dash`

## Install globally

```bash
ln -sf ~/vaults/ark/dashboard/target/release/ark-dash ~/.local/bin/ark-dash
```

Now run from anywhere: `ark-dash`

## Usage

```bash
# Default: scans ~/code for projects, ~/vaults/ark for vault
ark-dash

# Custom paths
ark-dash --projects ~/work --vault ~/my-brain

# Faster refresh (default 2000ms)
ark-dash --refresh 500
```

## Keybindings

| Key | Action |
|-----|--------|
| `Tab` / `Shift-Tab` | Switch panel |
| `↑↓` or `j/k` | Navigate within panel |
| `r` | Force refresh |
| `h` | Toggle help overlay |
| `q` / `Esc` | Quit |

## Pluggable Employee Registry

The dashboard reads `~/vaults/ark/employees/*.json` at runtime. Each file defines a "role" available to the brain.

### Add a new employee

Create `~/vaults/ark/employees/my-role.json`:

```json
{
  "id": "data-scientist",
  "title": "Data Scientist",
  "department": "Analytics",
  "skills": ["pandas", "ml", "visualization"],
  "dispatch": {
    "type": "claude-subagent",
    "subagent_type": "general-purpose"
  },
  "cost_per_task": "medium",
  "status": "available",
  "description": "Analyzes project data, runs ML experiments."
}
```

Refresh dashboard (`r`) — new employee appears.

### Dispatch types

- `claude-subagent` — Uses Claude Code's Agent tool with `subagent_type` field
- `cli` — Shell command (e.g., `codex exec -`, `npm test`)
- `api` — Direct API call to a model (specify `model` field)

### Cost tiers

`free` (green), `low` (cyan), `medium` (yellow), `high` (red) — used for budget routing.

### Status

`available`, `busy`, `blocked` — currently informational; future versions will track real-time agent state.

## Architecture

```
ark-dash (Rust binary)
  ├── reads ~/code/*/.parent-automation/ → projects panel
  ├── reads ~/vaults/ark/employees/*.json → employees panel
  ├── reads ~/vaults/ark/observability/*.jsonl → events
  └── aggregates → metrics panel

Employees can be added without recompiling:
  Drop a .json file in employees/ → next refresh picks it up.
```

## Why Rust?

- **Single binary** — no runtime dependencies, ships as one executable
- **Fast** — TUI redraws are instant even with 100+ projects
- **Memory-safe** — won't crash mid-shift, no GC pauses
- **Ratatui** — the modern TUI library for Rust, widely used

## Future additions

- `ark-dash dispatch <employee-id> <task>` — hire an employee from the CLI
- Real-time websocket streaming from running brain processes
- Cost-per-month projection based on tier history
- Click-through to view individual project's CEO report
- Employee performance metrics (success rate, avg time per task)
