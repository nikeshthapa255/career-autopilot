#!/usr/bin/env bash
# install-sidecars.sh — Idempotent, portable installer for Career Autopilot scheduled sidecars.
# Renders sidecar.json files into ~/.gemini/config/sidecars/<prefix>-{find-jobs,auto-apply}/sidecar.json
# (or into <tmp_dir> when --dry-run <tmp_dir> is passed).
# NEVER modifies user_config.json or enables automations automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

FIND_TEMPLATE="$SCRIPT_DIR/find-new-jobs.sidecar.json.template"
APPLY_TEMPLATE="$SCRIPT_DIR/auto-apply.sidecar.json.template"

DEFAULT_TZ="Asia/Kolkata"
DEFAULT_SCOUT_CRON="0 8 * * *"
DEFAULT_APPLY_CRON="0 9 * * *"
DEFAULT_PREFIX="career-autopilot"

WORKSPACE_PATH=""
RENDERER_PATH=""
CRON_TZ="$DEFAULT_TZ"
SCOUT_CRON="$DEFAULT_SCOUT_CRON"
APPLY_CRON="$DEFAULT_APPLY_CRON"
EMAIL_ACCOUNT=""
NO_GMAIL=0
PREFIX="$DEFAULT_PREFIX"
DRY_RUN_DIR=""
NON_INTERACTIVE=0
EXPLICIT_CRON=0
EXPLICIT_TZ=0

usage() {
  cat <<'EOF'
Usage: install-sidecars.sh [OPTIONS]

Render parameterized Career Autopilot scheduled sidecar configurations into
~/.gemini/config/sidecars/<prefix>-find-jobs/sidecar.json and
~/.gemini/config/sidecars/<prefix>-auto-apply/sidecar.json.

Options:
  --workspace <dir>         Absolute or relative path to your private job-search workspace
  --renderer <path>         Path to render_resume_pdf.sh (auto-detected if omitted)
  --tz <iana_zone>          IANA timezone for CRON_TZ (default: Asia/Kolkata)
  --scout-cron <5-field>    Cron schedule for job discovery (default: "0 8 * * *")
  --apply-cron <5-field>    Cron schedule for apply/draft pipeline (default: "0 9 * * *")
  --cron <5-field>          Set the same 5-field cron schedule for both sidecars
  --email <address|none>    Connected Gmail account for AGY_ACCOUNT, or "none" (no Gmail)
  --no-gmail                Disable Gmail CLI grants (copy-paste Markdown dossiers only)
  --prefix <kebab-prefix>   Sidecar directory ID prefix (default: career-autopilot)
  --dry-run <tmp_dir>       Write rendered files into <tmp_dir> instead of ~/.gemini/config/sidecars
  -y, --non-interactive     Use flags/defaults without prompting interactively
  -h, --help                Show this help message

Safety Guarantees:
  - Never edits user_config.json or enables sidecars automatically.
  - Never includes generic wildcards or outbound email send permissions.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

resolve_path_clean() {
  local raw="$1"
  if [ -d "$raw" ]; then
    (cd "$raw" && pwd -P)
    return 0
  fi
  local parent base
  parent="$(dirname "$raw")"
  base="$(basename "$raw")"
  if [ -d "$parent" ]; then
    printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
    return 0
  fi
  case "$raw" in
    /*) printf '%s\n' "$raw" ;;
    *)  printf '%s/%s\n' "$(pwd -P)" "$raw" ;;
  esac
}

detect_default_renderer() {
  local installed="$HOME/.gemini/config/plugins/career-autopilot/skills/career-autopilot-apply/scripts/render_resume_pdf.sh"
  local repo_local="$REPO_ROOT/plugin/skills/career-autopilot-apply/scripts/render_resume_pdf.sh"
  if [ -f "$installed" ]; then
    printf '%s\n' "$installed"
  else
    printf '%s\n' "$repo_local"
  fi
}

json_escape() {
  LC_ALL=C awk 'BEGIN {
    s = ENVIRON["RAW_VAL"]
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, "\\t", s)
    gsub(/\r/, "", s)
    printf "%s", s
  }'
}

uri_encode_path() {
  LC_ALL=C awk 'BEGIN {
    s = ENVIRON["RAW_VAL"]
    for (i = 0; i < 256; i++) {
      ord[sprintf("%c", i)] = i
    }
    out = ""
    n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c ~ /^[A-Za-z0-9._~\/-]$/) {
        out = out c
      } else {
        out = out sprintf("%%%02X", ord[c])
      }
    }
    printf "%s", out
  }'
}

extract_tz_from_cron() {
  local expr="$1"
  local trimmed
  trimmed="$(printf '%s' "$expr" | awk '{$1=$1; print}')"
  case "$trimmed" in
    CRON_TZ=*)
      local rest="${trimmed#CRON_TZ=}"
      printf '%s\n' "${rest%% *}"
      ;;
    TZ=*)
      local rest="${trimmed#TZ=}"
      printf '%s\n' "${rest%% *}"
      ;;
  esac
}

strip_tz_from_cron() {
  local expr="$1"
  local trimmed
  trimmed="$(printf '%s' "$expr" | awk '{$1=$1; print}')"
  case "$trimmed" in
    CRON_TZ=*|TZ=*)
      local rest="${trimmed#*=}"
      printf '%s\n' "${rest#* }"
      ;;
    *)
      printf '%s\n' "$trimmed"
      ;;
  esac
}

validate_cron_5fields() {
  local label="$1"
  local expr="$2"
  local count
  count="$(printf '%s' "$expr" | awk '{print NF}')"
  if [ "$count" -ne 5 ]; then
    die "$label must be a valid 5-field cron expression (got '$expr')."
  fi
}

validate_prefix() {
  local p="$1"
  if ! printf '%s' "$p" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
    die "--prefix must be lowercase kebab-case ([a-z0-9-]+), got '$p'."
  fi
}

validate_tz_name() {
  local z="$1"
  if ! printf '%s' "$z" | grep -Eq '^[A-Za-z0-9_/+.-]+$'; then
    die "Invalid IANA timezone format: '$z' (expected e.g. Asia/Kolkata or Europe/Berlin)."
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace)
      [ "$#" -ge 2 ] || die "--workspace requires a directory path"
      WORKSPACE_PATH="$2"
      shift 2
      ;;
    --workspace=*)
      WORKSPACE_PATH="${1#*=}"
      shift
      ;;
    --renderer)
      [ "$#" -ge 2 ] || die "--renderer requires a file path"
      RENDERER_PATH="$2"
      shift 2
      ;;
    --renderer=*)
      RENDERER_PATH="${1#*=}"
      shift
      ;;
    --tz)
      [ "$#" -ge 2 ] || die "--tz requires an IANA timezone"
      CRON_TZ="$2"
      EXPLICIT_TZ=1
      shift 2
      ;;
    --tz=*)
      CRON_TZ="${1#*=}"
      EXPLICIT_TZ=1
      shift
      ;;
    --scout-cron)
      [ "$#" -ge 2 ] || die "--scout-cron requires a 5-field cron expression"
      SCOUT_CRON="$2"
      EXPLICIT_CRON=1
      shift 2
      ;;
    --scout-cron=*)
      SCOUT_CRON="${1#*=}"
      EXPLICIT_CRON=1
      shift
      ;;
    --apply-cron)
      [ "$#" -ge 2 ] || die "--apply-cron requires a 5-field cron expression"
      APPLY_CRON="$2"
      EXPLICIT_CRON=1
      shift 2
      ;;
    --apply-cron=*)
      APPLY_CRON="${1#*=}"
      EXPLICIT_CRON=1
      shift
      ;;
    --cron)
      [ "$#" -ge 2 ] || die "--cron requires a 5-field cron expression"
      SCOUT_CRON="$2"
      APPLY_CRON="$2"
      EXPLICIT_CRON=1
      shift 2
      ;;
    --cron=*)
      SCOUT_CRON="${1#*=}"
      APPLY_CRON="$SCOUT_CRON"
      EXPLICIT_CRON=1
      shift
      ;;
    --email)
      [ "$#" -ge 2 ] || die "--email requires an email address or 'none'"
      EMAIL_ACCOUNT="$2"
      shift 2
      ;;
    --email=*)
      EMAIL_ACCOUNT="${1#*=}"
      shift
      ;;
    --no-gmail)
      NO_GMAIL=1
      EMAIL_ACCOUNT="none"
      shift
      ;;
    --prefix)
      [ "$#" -ge 2 ] || die "--prefix requires a kebab-case prefix"
      PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      PREFIX="${1#*=}"
      shift
      ;;
    --dry-run)
      if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
        DRY_RUN_DIR="$2"
        shift 2
      else
        DRY_RUN_DIR="/tmp/career-autopilot-sidecars-dryrun"
        shift
      fi
      ;;
    --dry-run=*)
      DRY_RUN_DIR="${1#*=}"
      shift
      ;;
    -y|--non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help for usage)"
      ;;
  esac
done

[ -f "$FIND_TEMPLATE" ] || die "Missing template: $FIND_TEMPLATE"
[ -f "$APPLY_TEMPLATE" ] || die "Missing template: $APPLY_TEMPLATE"

if [ -z "$RENDERER_PATH" ]; then
  RENDERER_PATH="$(detect_default_renderer)"
fi

# Determine interactive prompt behavior cleanly.
if [ "$NON_INTERACTIVE" -eq 0 ] && [ -z "$DRY_RUN_DIR" ] && [ -t 0 ] && [ -z "$WORKSPACE_PATH" ]; then
  printf 'Career Autopilot Sidecar Installer\n'
  printf '==================================\n'
  local_default_ws="$(pwd -P)"
  read -r -p "Private job-search workspace path [$local_default_ws]: " input_ws
  WORKSPACE_PATH="${input_ws:-$local_default_ws}"

  read -r -p "IANA timezone [$CRON_TZ]: " input_tz
  if [ -n "$input_tz" ]; then
    CRON_TZ="$input_tz"
    EXPLICIT_TZ=1
  fi

  read -r -p "Discovery (find-jobs) 5-field cron [$SCOUT_CRON]: " input_scout
  SCOUT_CRON="${input_scout:-$SCOUT_CRON}"

  read -r -p "Apply/Draft (auto-apply) 5-field cron [$APPLY_CRON]: " input_apply
  APPLY_CRON="${input_apply:-$APPLY_CRON}"

  read -r -p "Connected Gmail account for draft-only outreach (or 'none') [none]: " input_email
  EMAIL_ACCOUNT="${input_email:-none}"

  read -r -p "Path to render_resume_pdf.sh [$RENDERER_PATH]: " input_renderer
  RENDERER_PATH="${input_renderer:-$RENDERER_PATH}"

  read -r -p "Sidecar folder prefix [$PREFIX]: " input_prefix
  PREFIX="${input_prefix:-$PREFIX}"
fi

if [ -z "$WORKSPACE_PATH" ]; then
  if [ -n "$DRY_RUN_DIR" ]; then
    WORKSPACE_PATH="/tmp/career-autopilot-workspace"
  else
    die "Missing --workspace <dir> in non-interactive mode."
  fi
fi

WORKSPACE_PATH="$(resolve_path_clean "$WORKSPACE_PATH")"
RENDERER_PATH="$(resolve_path_clean "$RENDERER_PATH")"

if [ "$EXPLICIT_TZ" -eq 0 ]; then
  detected_tz="$(extract_tz_from_cron "$SCOUT_CRON")"
  if [ -z "$detected_tz" ]; then
    detected_tz="$(extract_tz_from_cron "$APPLY_CRON")"
  fi
  if [ -n "$detected_tz" ]; then
    CRON_TZ="$detected_tz"
  fi
fi

SCOUT_CRON="$(strip_tz_from_cron "$SCOUT_CRON")"
APPLY_CRON="$(strip_tz_from_cron "$APPLY_CRON")"

validate_prefix "$PREFIX"
validate_tz_name "$CRON_TZ"
validate_cron_5fields "--scout-cron" "$SCOUT_CRON"
validate_cron_5fields "--apply-cron" "$APPLY_CRON"

email_lower="$(printf '%s' "$EMAIL_ACCOUNT" | tr '[:upper:]' '[:lower:]')"
if [ "$NO_GMAIL" -eq 1 ] || [ -z "$email_lower" ] || [ "$email_lower" = "none" ]; then
  NO_GMAIL=1
  EMAIL_ACCOUNT="none"
fi

if [ -n "$DRY_RUN_DIR" ]; then
  TARGET_ROOT="$(resolve_path_clean "$DRY_RUN_DIR")"
else
  TARGET_ROOT="$HOME/.gemini/config/sidecars"
fi

FIND_OUT_DIR="$TARGET_ROOT/${PREFIX}-find-jobs"
APPLY_OUT_DIR="$TARGET_ROOT/${PREFIX}-auto-apply"
FIND_OUT_FILE="$FIND_OUT_DIR/sidecar.json"
APPLY_OUT_FILE="$APPLY_OUT_DIR/sidecar.json"

mkdir -p "$FIND_OUT_DIR" "$APPLY_OUT_DIR"

export RAW_VAL="$WORKSPACE_PATH"
VAL_WORKSPACE_PATH="$(json_escape)"
VAL_WORKSPACE_URI_PATH="$(uri_encode_path)"

export RAW_VAL="$RENDERER_PATH"
VAL_RENDERER_PATH="$(json_escape)"

export RAW_VAL="$CRON_TZ"
VAL_CRON_TZ="$(json_escape)"

export RAW_VAL="$SCOUT_CRON"
VAL_SCOUT_CRON="$(json_escape)"

export RAW_VAL="$APPLY_CRON"
VAL_APPLY_CRON="$(json_escape)"

export RAW_VAL="$EMAIL_ACCOUNT"
VAL_EMAIL_ACCOUNT="$(json_escape)"

render_template() {
  local template_file="$1"
  local out_file="$2"
  local cron_val="$3"
  local strip_gmail="$4"

  export VAL_WORKSPACE_PATH VAL_WORKSPACE_URI_PATH VAL_RENDERER_PATH VAL_CRON_TZ VAL_EMAIL_ACCOUNT
  export VAL_CRON_SCHEDULE="$cron_val"
  export STRIP_GMAIL="$strip_gmail"

  LC_ALL=C awk '
    function replace_all(str, pat, rep,    idx, out) {
      out = ""
      while ((idx = index(str, pat)) > 0) {
        out = out substr(str, 1, idx - 1) rep
        str = substr(str, idx + length(pat))
      }
      return out str
    }
    {
      line = $0
      if (ENVIRON["STRIP_GMAIL"] == "1" && index(line, "\"command(gmail ") > 0) {
        next
      }
      line = replace_all(line, "file://{{WORKSPACE_PATH}}", "file://" ENVIRON["VAL_WORKSPACE_URI_PATH"])
      line = replace_all(line, "{{WORKSPACE_PATH}}", ENVIRON["VAL_WORKSPACE_PATH"])
      line = replace_all(line, "{{SCRIPT_RENDERER_PATH}}", ENVIRON["VAL_RENDERER_PATH"])
      line = replace_all(line, "{{CRON_TZ}}", ENVIRON["VAL_CRON_TZ"])
      line = replace_all(line, "{{CRON_SCHEDULE}}", ENVIRON["VAL_CRON_SCHEDULE"])
      line = replace_all(line, "{{EMAIL_ACCOUNT}}", ENVIRON["VAL_EMAIL_ACCOUNT"])
      print line
    }
  ' "$template_file" > "$out_file"
}

validate_rendered_json() {
  local json_file="$1"
  if grep -Eq '\{\{[A-Z0-9_]+\}\}' "$json_file"; then
    die "Unresolved template placeholder remains in $json_file"
  fi
  if grep -Eq '"(command|read_file|write_file|read_url|mcp)\(\*\)"' "$json_file"; then
    die "Forbidden wildcard permission found in $json_file"
  fi
  if grep -Eq '"command\(gmail mutate (send|send-draft|send-with-attachment|reply|forward)' "$json_file"; then
    die "Forbidden outbound Gmail send permission found in $json_file"
  fi
  if command -v jq >/dev/null 2>&1; then
    jq empty "$json_file" || die "Invalid JSON syntax (jq) in $json_file"
  elif command -v osascript >/dev/null 2>&1; then
    JSON_FILE_CHECK="$json_file" osascript -l JavaScript -e '
      ObjC.import("Foundation");
      var p = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("JSON_FILE_CHECK"));
      var data = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
      JSON.parse(ObjC.unwrap(data));
    ' >/dev/null || die "Invalid JSON syntax (osascript) in $json_file"
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    python3 -m json.tool "$json_file" >/dev/null || die "Invalid JSON syntax (python3) in $json_file"
  else
    grep -q '"builtin": "schedule"' "$json_file" || die "Missing builtin schedule key in $json_file"
    grep -q '"restart_policy": "always"' "$json_file" || die "Missing restart_policy always in $json_file"
  fi
}

render_template "$FIND_TEMPLATE" "$FIND_OUT_FILE" "$VAL_SCOUT_CRON" "0"
validate_rendered_json "$FIND_OUT_FILE"

render_template "$APPLY_TEMPLATE" "$APPLY_OUT_FILE" "$VAL_APPLY_CRON" "$NO_GMAIL"
validate_rendered_json "$APPLY_OUT_FILE"

printf '\nRendered scheduled sidecar configs successfully:\n'
printf '  1. Career Autopilot — Find New Jobs (%s-find-jobs)\n     -> %s\n' "$PREFIX" "$FIND_OUT_FILE"
printf '  2. Career Autopilot — Apply & Draft Pipeline (%s-auto-apply)\n     -> %s\n' "$PREFIX" "$APPLY_OUT_FILE"
printf '\nSettings applied:\n'
printf '  - Workspace: %s\n' "$WORKSPACE_PATH"
printf '  - Renderer:  %s\n' "$RENDERER_PATH"
printf '  - Timezone:  %s\n' "$CRON_TZ"
printf '  - Schedules: scout="%s" | apply="%s"\n' "$SCOUT_CRON" "$APPLY_CRON"
if [ "$NO_GMAIL" -eq 1 ]; then
  printf '  - Outreach:  Copy-paste Markdown dossier mode (Gmail CLI grants omitted)\n'
else
  printf '  - Outreach:  Draft-only Gmail CLI (AGY_ACCOUNT=%s; outbound send grants omitted)\n' "$EMAIL_ACCOUNT"
fi

if [ -n "$DRY_RUN_DIR" ]; then
  printf '\n[DRY RUN] Wrote output to %s (user_config.json and ~/.gemini/config/sidecars untouched).\n' "$TARGET_ROOT"
else
  printf '\nIMPORTANT — Automations are installed DISABLED by default:\n'
  printf '  - user_config.json was NOT modified.\n'
  printf '  - Run a test run interactively first to verify permissions.\n'
  printf '  - Enable "Career Autopilot — Find New Jobs" and "Career Autopilot — Apply & Draft Pipeline"\n'
  printf '    manually in the Automations dashboard: [Open Automations Dashboard](sidecar://dashboard)\n'
fi
