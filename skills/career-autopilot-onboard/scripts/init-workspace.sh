#!/usr/bin/env bash
# init-workspace.sh — Safely scaffolds a private Career Autopilot workspace
# from workspace-template/ without overwriting existing files unless --force.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PLUGIN_DIR="$(cd "$SKILL_DIR/../.." && pwd -P)"

FORCE=0
TEMPLATES_ONLY=0
EXPLICIT_TEMPLATE_DIR=""
TARGET_DIR=""

usage() {
  cat <<'EOF'
Usage: init-workspace.sh [OPTIONS] <target-workspace-dir>

Scaffolds a private Career Autopilot job-search workspace from workspace-template/
without overwriting existing files unless --force is passed.

Options:
  --force                Overwrite existing files in <target-workspace-dir>
  --templates-only       Copy only .gitignore and *.template files (skip seeding *.md)
  --template-dir <dir>   Explicit path to workspace-template/
  -h, --help             Show this help message and exit

Template Discovery Order (when --template-dir is not specified):
  1. $CAREER_AUTOPILOT_TEMPLATE_DIR environment variable
  2. <plugin-dir>/workspace-template (relative to skills/career-autopilot-onboard/scripts)
  3. <skill-dir>/resources/workspace-template
  4. ./workspace-template or ../workspace-template (from current working directory)
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

is_valid_template_dir() {
  local dir="$1"
  [ -d "$dir" ] &&
    [ -f "$dir/.gitignore" ] &&
    [ -f "$dir/GLOBAL_REFERENCE.md.template" ] &&
    [ -f "$dir/resume/master_profile.md.template" ]
}

resolve_template_dir() {
  local candidate=""

  if [ -n "$EXPLICIT_TEMPLATE_DIR" ]; then
    if is_valid_template_dir "$EXPLICIT_TEMPLATE_DIR"; then
      (cd "$EXPLICIT_TEMPLATE_DIR" && pwd -P)
      return 0
    fi
    die "Specified --template-dir is invalid or incomplete: $EXPLICIT_TEMPLATE_DIR"
  fi

  if [ -n "${CAREER_AUTOPILOT_TEMPLATE_DIR:-}" ]; then
    if is_valid_template_dir "$CAREER_AUTOPILOT_TEMPLATE_DIR"; then
      (cd "$CAREER_AUTOPILOT_TEMPLATE_DIR" && pwd -P)
      return 0
    fi
    die "CAREER_AUTOPILOT_TEMPLATE_DIR is invalid or incomplete: $CAREER_AUTOPILOT_TEMPLATE_DIR"
  fi

  for candidate in \
    "$PLUGIN_DIR/workspace-template" \
    "$SKILL_DIR/resources/workspace-template" \
    "$PWD/workspace-template" \
    "$PWD/../workspace-template"; do
    [ -n "$candidate" ] || continue
    if is_valid_template_dir "$candidate"; then
      (cd "$candidate" && pwd -P)
      return 0
    fi
  done

  printf '%s\n' \
    "ERROR: Could not locate workspace-template/ directory." \
    "Checked:" \
    "  - $PLUGIN_DIR/workspace-template" \
    "  - $SKILL_DIR/resources/workspace-template" \
    "  - $PWD/workspace-template" \
    "  - $PWD/../workspace-template" \
    "If the plugin was copied standalone outside its repository, pass --template-dir <path/to/workspace-template> or set CAREER_AUTOPILOT_TEMPLATE_DIR." >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --templates-only)
      TEMPLATES_ONLY=1
      shift
      ;;
    --template-dir)
      [ "$#" -ge 2 ] || die "Missing value for --template-dir"
      EXPLICIT_TEMPLATE_DIR="$2"
      shift 2
      ;;
    --template-dir=*)
      EXPLICIT_TEMPLATE_DIR="${1#--template-dir=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1 (run with --help for usage)"
      ;;
    *)
      if [ -n "$TARGET_DIR" ]; then
        die "Unexpected extra argument: $1 (expected single <target-workspace-dir>)"
      fi
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  printf 'ERROR: Missing <target-workspace-dir>.\n\n' >&2
  usage >&2
  exit 1
fi

TEMPLATE_DIR="$(resolve_template_dir)"
TEMPLATE_PARENT_ABS="$(cd "$TEMPLATE_DIR/.." && pwd -P)"

# Resolve target path via nearest existing ancestor BEFORE creating any directory.
resolve_target_before_mkdir() {
  local raw="$1"
  local abs="$raw"
  case "$abs" in
    /*) ;;
    *) abs="$PWD/$abs" ;;
  esac
  local probe="$abs"
  local suffix=""
  while [ ! -d "$probe" ]; do
    local base
    base="$(basename "$probe")"
    local parent
    parent="$(dirname "$probe")"
    if [ "$parent" = "$probe" ]; then
      break
    fi
    if [ -n "$suffix" ]; then
      suffix="$base/$suffix"
    else
      suffix="$base"
    fi
    probe="$parent"
  done
  local real_base
  real_base="$(cd "$probe" && pwd -P)"
  if [ -n "$suffix" ]; then
    printf '%s/%s\n' "${real_base%/}" "$suffix"
  else
    printf '%s\n' "$real_base"
  fi
}

TARGET_CANDIDATE="$(resolve_target_before_mkdir "$TARGET_DIR")"
CONFIG_ROOT="$(resolve_target_before_mkdir "$HOME/.gemini/config")"

# Guard against initializing inside the plugin, template, ~/.gemini/config, or any plugin.json tree.
case "$TARGET_CANDIDATE" in
  "$PLUGIN_DIR"|"$PLUGIN_DIR"/*|"$TEMPLATE_DIR"|"$TEMPLATE_DIR"/*|"$TEMPLATE_PARENT_ABS"|"$TEMPLATE_PARENT_ABS"/*|"$CONFIG_ROOT"|"$CONFIG_ROOT"/*)
    die "Target workspace ($TARGET_CANDIDATE) must be a separate private directory outside the plugin repository and ~/.gemini/config."
    ;;
esac

probe_plugin="$TARGET_CANDIDATE"
while [ -n "$probe_plugin" ] && [ "$probe_plugin" != "/" ]; do
  if [ -f "$probe_plugin/plugin.json" ]; then
    die "Target workspace ($TARGET_CANDIDATE) cannot be inside an Antigravity plugin directory ($probe_plugin)."
  fi
  parent_plugin="$(dirname "$probe_plugin")"
  [ "$parent_plugin" = "$probe_plugin" ] && break
  probe_plugin="$parent_plugin"
done

mkdir -p "$TARGET_DIR"
TARGET_ABS="$(cd "$TARGET_DIR" && pwd -P)"

mkdir -p "$TARGET_ABS/resume" "$TARGET_ABS/applications"

COPIED_COUNT=0
SEEDED_COUNT=0
SKIPPED_COUNT=0

copy_safe() {
  local src="$1"
  local dst="$2"
  local mode="$3"

  [ -f "$src" ] || die "Expected template file missing: $src"
  mkdir -p "$(dirname "$dst")"

  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    printf 'SKIP (exists): %s\n' "$dst"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi

  cp "$src" "$dst"
  if [ "$mode" = "seed" ]; then
    printf 'SEED: %s\n' "$dst"
    SEEDED_COUNT=$((SEEDED_COUNT + 1))
  else
    printf 'COPY: %s\n' "$dst"
    COPIED_COUNT=$((COPIED_COUNT + 1))
  fi
}

# 1. Scaffold protective .gitignore and canonical *.template files
copy_safe "$TEMPLATE_DIR/.gitignore" "$TARGET_ABS/.gitignore" "copy"
copy_safe "$TEMPLATE_DIR/GLOBAL_REFERENCE.md.template" "$TARGET_ABS/GLOBAL_REFERENCE.md.template" "copy"
copy_safe "$TEMPLATE_DIR/resume/master_profile.md.template" "$TARGET_ABS/resume/master_profile.md.template" "copy"
copy_safe "$TEMPLATE_DIR/applications/tracker.md.template" "$TARGET_ABS/applications/tracker.md.template" "copy"
copy_safe "$TEMPLATE_DIR/applications/new_leads.md.template" "$TARGET_ABS/applications/new_leads.md.template" "copy"
if [ -f "$TEMPLATE_DIR/requirements/README.md.template" ]; then
  copy_safe "$TEMPLATE_DIR/requirements/README.md.template" "$TARGET_ABS/requirements/README.md.template" "copy"
fi

# 2. Seed initial working Markdown files when absent (never overwriting populated files without --force)
if [ "$TEMPLATES_ONLY" -ne 1 ]; then
  copy_safe "$TEMPLATE_DIR/GLOBAL_REFERENCE.md.template" "$TARGET_ABS/GLOBAL_REFERENCE.md" "seed"
  copy_safe "$TEMPLATE_DIR/resume/master_profile.md.template" "$TARGET_ABS/resume/master_profile.md" "seed"
  copy_safe "$TEMPLATE_DIR/applications/tracker.md.template" "$TARGET_ABS/applications/tracker.md" "seed"
  copy_safe "$TEMPLATE_DIR/applications/new_leads.md.template" "$TARGET_ABS/applications/new_leads.md" "seed"
fi

RENDER_SCRIPT="$PLUGIN_DIR/skills/career-autopilot-apply/scripts/render_resume_pdf.sh"
if [ -f "$PLUGIN_DIR/automations/install-sidecars.sh" ]; then
  SIDECAR_INSTALLER="$PLUGIN_DIR/automations/install-sidecars.sh"
elif [ -f "$TEMPLATE_PARENT_ABS/automations/install-sidecars.sh" ]; then
  SIDECAR_INSTALLER="$TEMPLATE_PARENT_ABS/automations/install-sidecars.sh"
else
  SIDECAR_INSTALLER="<plugin-dir>/automations/install-sidecars.sh"
fi

printf '\nWorkspace initialized: %s\n' "$TARGET_ABS"
printf 'Template source:       %s\n' "$TEMPLATE_DIR"
printf 'Summary:               %d copied, %d seeded, %d skipped\n' "$COPIED_COUNT" "$SEEDED_COUNT" "$SKIPPED_COUNT"

cat <<EOF

Next Steps:
  1. Run Phase 0 onboarding with the career-autopilot-onboard skill:
     Prompt example:
       "Onboard my workspace at $TARGET_ABS using my resume at <path-to-resume.pdf|.docx|.md>."
     This populates resume/master_profile.md (with Verified Quantitative Baseline),
     runs the structured preference & safety interview into GLOBAL_REFERENCE.md,
     and renders your verified 1-page baseline PDF.

  2. Verify the headless PDF renderer:
     "$RENDER_SCRIPT" --help
     (After Phase 0 populates resume/backup_resume.html:)
     "$RENDER_SCRIPT" \\
       "$TARGET_ABS/resume/backup_resume.html" \\
       "$TARGET_ABS/resume/<Candidate_Slug>_Backup_Resume.pdf" \\
       --strict-1-page

  3. Optional — Install daily scheduled sidecars (discovery + draft/pre-stage):
     "$SIDECAR_INSTALLER" --workspace "$TARGET_ABS"
     (Then review and enable manually in Antigravity Automations: sidecar://dashboard)
EOF
