#!/usr/bin/env bash
# test_zero_pii_scan.sh — Verifies zero candidate PII, hardcoded home paths, or legacy reference leaks
# across plugin/, workspace-template/, automations/, docs/, README.md, and tests/fixtures/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

ALLOW_MISSING=0
for arg in "$@"; do
  case "$arg" in
    --allow-missing) ALLOW_MISSING=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: test_zero_pii_scan.sh [--allow-missing]

Scans plugin/, workspace-template/, automations/, docs/, README.md, and tests/fixtures/
for personal emails, hardcoded user home paths, real phone numbers, non-placeholder
profile URLs, and legacy reference workspace names.
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

REQUIRED_TARGETS=(
  "$REPO_ROOT/plugin"
  "$REPO_ROOT/workspace-template"
  "$REPO_ROOT/automations"
  "$REPO_ROOT/docs"
  "$REPO_ROOT/README.md"
  "$REPO_ROOT/tests/fixtures"
)

SCAN_TARGETS=()
MISSING_TARGETS=()

for target in "${REQUIRED_TARGETS[@]}"; do
  if [ -e "$target" ]; then
    SCAN_TARGETS+=("$target")
  else
    MISSING_TARGETS+=("$target")
  fi
done

if [ "${#MISSING_TARGETS[@]}" -gt 0 ]; then
  echo "Missing target path(s):" >&2
  for m in "${MISSING_TARGETS[@]}"; do
    echo "  - $m" >&2
  done
  if [ "$ALLOW_MISSING" -ne 1 ]; then
    echo "FAIL: Required distributable directories/files are missing (pass --allow-missing for partial dev checks)." >&2
    exit 1
  fi
fi

if [ "${#SCAN_TARGETS[@]}" -eq 0 ]; then
  echo "FAIL: No scan targets exist." >&2
  exit 1
fi

FAILURES=0

report_failure() {
  local title="$1"
  local findings="$2"
  if [ -n "$findings" ]; then
    echo "FAIL [$title]:" >&2
    printf '%s\n' "$findings" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# 1. Hardcoded OS user home paths (/Users/<name>, /home/<name>, C:\Users\<name>)
HOME_PATH_MATCHES="$(
  grep -rnEo '(/Users/|/home/|C:\\Users\\)[A-Za-z0-9._-]+' "${SCAN_TARGETS[@]}" 2>/dev/null \
    | grep -Ev '(/Users/|/home/|C:\\Users\\)(example|alice|username|your-user|candidate|<[^>]+>|\*|\{\{[^}]+\}\})([/\\"'"'"'[:space:]]|$)' \
    || true
)"
report_failure "Hardcoded user home directory path" "$HOME_PATH_MATCHES"

# 2. file:///Users/ or file:///home/ URIs
FILE_URI_MATCHES="$(
  grep -rnE 'file:///(Users|home|C:/Users)/' "${SCAN_TARGETS[@]}" 2>/dev/null \
    | grep -Ev 'file:///(Users|home|C:/Users)/(example|alice|username|your-user|candidate|<[^>]+>)' \
    || true
)"
report_failure "Hardcoded file:// home directory URI" "$FILE_URI_MATCHES"

# 3. Real email addresses outside RFC 2606 / synthetic placeholder patterns
EMAIL_MATCHES="$(
  grep -rnEo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${SCAN_TARGETS[@]}" 2>/dev/null \
    | grep -Ev '@(example\.(com|org|net)|company\.example|domain\.com|placeholder\.invalid|localhost\.localdomain)([[:space:]"'"'"'`,;>)]|$)' \
    | grep -Ev ':(first|first\.last|user|name)@company\.com([[:space:]"'"'"'`,;>)]|$)' \
    || true
)"
report_failure "Non-placeholder email address" "$EMAIL_MATCHES"

# 4. Real-looking international phone numbers (allow obvious dummy zeros/555 or template placeholders)
PHONE_MATCHES="$(
  grep -rnEo '\+[1-9][0-9]{0,2}[[:space:]-]?[0-9]{4,5}[[:space:]-]?[0-9]{4,5}' "${SCAN_TARGETS[@]}" 2>/dev/null \
    | grep -Ev '\+91[[:space:]-]?(00000|90000|98765)[[:space:]-]?(00000|43210)|\+1[[:space:]-]?555[[:space:]-]?01[0-9]{2}' \
    || true
)"
report_failure "Non-placeholder phone number" "$PHONE_MATCHES"

# 5. Non-placeholder LinkedIn or GitHub profile URLs (allow official plugin repo URL only)
PROFILE_MATCHES="$(
  grep -rnEo '(linkedin\.com/in/|github\.com/)[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?' "${SCAN_TARGETS[@]}" 2>/dev/null \
    | grep -Ev 'github\.com/nikeshthapa255/career-autopilot([/?&#"'"'"'[:space:]]|$)' \
    | grep -Ev '(linkedin\.com/in/|github\.com/)(example|example-candidate|your-handle|your-username|your-org|career-autopilot|ChromeDevTools|google|anthropics)([/?&#"'"'"'[:space:]]|$)' \
    || true
)"
report_failure "Non-placeholder LinkedIn/GitHub URL" "$PROFILE_MATCHES"

# 6. Legacy reference workspace filenames and old prototype skill/plugin names
LEGACY_MATCHES="$(
  grep -rnE 'india_remote_100k_jobs|remote_100k_jobs|job-apply-kit|\.agents/skills/job-apply' "${SCAN_TARGETS[@]}" 2>/dev/null || true
)"
report_failure "Legacy reference workspace token" "$LEGACY_MATCHES"

if [ "$FAILURES" -gt 0 ]; then
  echo "FAIL: Zero-PII scan detected $FAILURES violation category(ies)." >&2
  exit 1
fi

echo "PASS: Zero-PII scan clean across ${#SCAN_TARGETS[@]} target path(s)."
