#!/usr/bin/env bash
# gsd-shape.sh — Shared library for GSD vs Ark phase-shape resolution
#
# Provides helper functions for any Ark script that needs to find phase
# directories, plan files, or sign-off artifacts in either layout.
#
# Usage:
#   source "$VAULT_PATH/scripts/lib/gsd-shape.sh"
#
# Functions exported:
#   normalize_phase_num  — "1.5" → "01.5"
#   is_gsd_project       — does $PROJECT_DIR use GSD layout?
#   resolve_phase_dir    — "1.5" → ".planning/phases/01.5-slug" or fallback
#   find_plan_files      — return all *-PLAN.md or PLAN.md in a phase dir
#   phase_artifact_path  — get path to ceo-report, team artifacts, etc.
#   list_phase_dirs      — enumerate all phase dirs in current project
#
# All functions assume PROJECT_DIR is set in the caller's scope.

# === Normalize phase number to GSD's zero-padded form ===
# Input: "1" → "01", "1.5" → "01.5", "10" → "10", "12.7" → "12.7"
gsd_normalize_phase_num() {
  local n="$1"
  local int_part="${n%%.*}"
  local dec_part=""
  if [[ "$n" == *.* ]]; then
    dec_part=".${n#*.}"
  fi
  if [[ ! "$int_part" =~ ^[0-9]+$ ]]; then
    echo "$n"
    return
  fi
  printf "%02d%s" "$int_part" "$dec_part"
}

# === Detect GSD layout ===
gsd_is_gsd_project() {
  local proj="${1:-${PROJECT_DIR:-$(pwd)}}"
  [[ -d "$proj/.planning/phases" ]] && \
    ls -1d "$proj/.planning/phases/"[0-9]* 2>/dev/null | head -1 | grep -q .
}

# === Resolve phase dir under either layout ===
# Returns: path to phase dir on stdout, exit 0 if existing, exit 1 if fallback
gsd_resolve_phase_dir() {
  local phase_num="$1"
  local proj="${2:-${PROJECT_DIR:-$(pwd)}}"
  local planning_root="$proj/.planning"
  local padded
  padded=$(gsd_normalize_phase_num "$phase_num")

  # GSD layout
  if [[ -d "$planning_root/phases" ]]; then
    local m
    m=$(ls -1d "$planning_root/phases/${padded}-"* 2>/dev/null | head -1)
    if [[ -n "$m" ]]; then
      echo "$m"
      return 0
    fi
    m=$(ls -1d "$planning_root/phases/${phase_num}-"* 2>/dev/null | head -1)
    if [[ -n "$m" ]]; then
      echo "$m"
      return 0
    fi
  fi

  # Ark legacy layout
  if [[ -d "$planning_root/phase-$phase_num" ]]; then
    echo "$planning_root/phase-$phase_num"
    return 0
  fi

  # Decimal Ark legacy
  local decimal_match
  decimal_match=$(ls -1d "$planning_root/phase-${phase_num}."* 2>/dev/null | head -1)
  if [[ -n "$decimal_match" ]]; then
    echo "$decimal_match"
    return 0
  fi

  # Fallback
  if gsd_is_gsd_project "$proj"; then
    echo "$planning_root/phases/${padded}-NEW"
  else
    echo "$planning_root/phase-$phase_num"
  fi
  return 1
}

# === Find ALL plan files in a phase dir ===
# GSD: NN-NN-PLAN.md or NN.X-NN-PLAN.md (multiple)
# Ark: PLAN.md (single)
gsd_find_plan_files() {
  local phase_dir="$1"
  [[ ! -d "$phase_dir" ]] && return 1

  # GSD multi-plan pattern
  local found=false
  for f in "$phase_dir"/*-PLAN.md; do
    [[ -f "$f" ]] || continue
    echo "$f"
    found=true
  done

  # Ark legacy single PLAN.md
  if [[ -f "$phase_dir/PLAN.md" ]]; then
    # Avoid duplicate if already matched above
    if [[ "$found" == "false" ]]; then
      echo "$phase_dir/PLAN.md"
    fi
  fi
}

# === Count actionable tasks across all plan files ===
gsd_count_tasks() {
  local phase_dir="$1"
  local total=0
  local plans
  plans=$(gsd_find_plan_files "$phase_dir")
  while IFS= read -r pf; do
    [[ -z "$pf" ]] && continue
    local c
    c=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\]' "$pf" 2>/dev/null || echo 0)
    total=$((total + c))
  done <<< "$plans"
  echo "$total"
}

# === Get path to a phase artifact ===
# Usage: gsd_phase_artifact_path <phase_num> <artifact_name>
# Examples:
#   gsd_phase_artifact_path 1.5 ceo-report
#   gsd_phase_artifact_path 1.5 team/security-audit.md
gsd_phase_artifact_path() {
  local phase_num="$1"
  local artifact="$2"
  local proj="${3:-${PROJECT_DIR:-$(pwd)}}"

  local phase_dir
  phase_dir=$(gsd_resolve_phase_dir "$phase_num" "$proj")

  case "$artifact" in
    ceo-report)
      # GSD-style: phase-dir/CEO-REPORT.md OR ark legacy: .planning/phase-N-ceo-report.md
      if [[ -f "$phase_dir/CEO-REPORT.md" ]]; then
        echo "$phase_dir/CEO-REPORT.md"
      else
        echo "$proj/.planning/phase-${phase_num}-ceo-report.md"
      fi
      ;;
    *)
      echo "$phase_dir/$artifact"
      ;;
  esac
}

# === List all phase dirs (sorted) ===
gsd_list_phase_dirs() {
  local proj="${1:-${PROJECT_DIR:-$(pwd)}}"
  local planning_root="$proj/.planning"

  # GSD layout first
  if [[ -d "$planning_root/phases" ]]; then
    ls -1d "$planning_root/phases/"[0-9]* 2>/dev/null | sort
  fi
  # Ark legacy
  ls -1d "$planning_root/phase-"[0-9]* 2>/dev/null | sort
}

# === Self-test (only runs when sourced with $1=test) ===
if [[ "${1:-}" == "test" ]]; then
  echo "🧪 gsd-shape.sh self-test"
  echo ""
  echo "normalize_phase_num:"
  for p in 0 1 1.5 2 2.1 10 12.7 99; do
    echo "  $p → $(gsd_normalize_phase_num "$p")"
  done

  if [[ -n "${TEST_PROJECT:-}" ]]; then
    echo ""
    echo "Tests against $TEST_PROJECT:"
    PROJECT_DIR="$TEST_PROJECT"
    if gsd_is_gsd_project; then
      echo "  ✅ Detected as GSD project"
    else
      echo "  ⚠️  Not GSD project"
    fi
    echo ""
    echo "  Phase dirs:"
    gsd_list_phase_dirs | sed "s|$TEST_PROJECT|.|" | head -10 | sed 's/^/    /'
    echo ""
    for p in 0 1 1.5 2.1; do
      d=$(gsd_resolve_phase_dir "$p")
      count=$(gsd_count_tasks "$d")
      echo "  Phase $p: $(echo $d | sed "s|$TEST_PROJECT|.|") ($count tasks)"
    done
  fi
fi
