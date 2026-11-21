#!/usr/bin/env bash
# test_render_resume_pdf.sh — End-to-end test suite for render_resume_pdf.sh,
# synthetic fixtures, and plugin/sidecar JSON validation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

RENDERER="$REPO_ROOT/plugin/skills/career-autopilot-apply/scripts/render_resume_pdf.sh"
FIX_GENERIC="$SCRIPT_DIR/fixtures/sample_resume_generic.html"
FIX_TODO="$SCRIPT_DIR/fixtures/sample_resume_todo.html"
FIX_TRAPS="$SCRIPT_DIR/fixtures/sample_ats_traps.html"

PLUGIN_JSON="$REPO_ROOT/plugin/plugin.json"
HOOKS_JSON="$REPO_ROOT/plugin/hooks.json"
SCOUT_SIDECAR="$REPO_ROOT/automations/find-new-jobs.sidecar.json.template"
APPLY_SIDECAR="$REPO_ROOT/automations/auto-apply.sidecar.json.template"

SKIP_MISSING_SIBLINGS=0
for arg in "$@"; do
  case "$arg" in
    --skip-missing-siblings) SKIP_MISSING_SIBLINGS=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: test_render_resume_pdf.sh [--skip-missing-siblings]

Exercises:
  1. render_resume_pdf.sh [TODO: block (exit 2 without --allow-todo)
  2. render_resume_pdf.sh --allow-todo draft pass (exit 0)
  3. Strict 1-page Letter & A4 PDF rendering on sample_resume_generic.html
  4. Trap fixture integrity check (sample_ats_traps.html)
  5. JSON syntax validation on plugin.json, hooks.json, and sidecar templates
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

TMP_ROOT="$SCRIPT_DIR/.test-tmp"
mkdir -p "$TMP_ROOT"
WORK_TMP="$(mktemp -d "$TMP_ROOT/run-XXXXXX")"
cleanup() {
  rm -rf "$WORK_TMP"
  rmdir "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file_exists() {
  local f="$1"
  if [ ! -f "$f" ]; then
    fail "Expected file missing: $f"
  fi
}

validate_json_file() {
  local file="$1"
  local allow_jsonc="${2:-0}"

  if [ ! -f "$file" ]; then
    if [ "$SKIP_MISSING_SIBLINGS" -eq 1 ]; then
      echo "SKIP: Missing sibling JSON file ($file)"
      return 0
    fi
    fail "Missing JSON file: $file"
  fi

  local check_target="$file"
  if [ "$allow_jsonc" -eq 1 ]; then
    # Strip standalone // comments for strict JSON parsers when checking JSONC plugin.json
    check_target="$WORK_TMP/$(basename "$file").stripped.json"
    awk '!/^[[:space:]]*\/\// { print }' "$file" > "$check_target"
  fi

  if command -v jq >/dev/null 2>&1; then
    jq empty "$check_target" || fail "Invalid JSON (jq): $file"
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    python3 -m json.tool "$check_target" >/dev/null || fail "Invalid JSON (python3): $file"
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$check_target" || fail "Invalid JSON (node): $file"
  elif command -v osascript >/dev/null 2>&1; then
    JSON_CHECK_FILE="$check_target" osascript -l JavaScript -e '
      ObjC.import("Foundation");
      var p = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("JSON_CHECK_FILE"));
      var data = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
      JSON.parse(ObjC.unwrap(data));
    ' >/dev/null || fail "Invalid JSON (osascript): $file"
  else
    fail "No JSON validator (jq, python3, node, osascript) available."
  fi
  echo "PASS: Valid JSON syntax -> $file"
}

check_pdf_mediabox() {
  local pdf_file="$1"
  local expected_label="$2"
  local min_w="$3"
  local max_w="$4"
  local min_h="$5"
  local max_h="$6"

  local box
  box="$(LC_ALL=C grep -Eao '/MediaBox[[:space:]]*\[[[:space:]]*[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+[0-9.]+[[:space:]]*\]' "$pdf_file" | head -n 1 || true)"
  if [ -z "$box" ]; then
    echo "INFO: /MediaBox not directly grep-able in compressed stream for $expected_label; skipping raw dimension check."
    return 0
  fi

  local dims
  dims="$(printf '%s' "$box" | sed -E 's/.*\[[[:space:]]*([0-9.]+)[[:space:]]+([0-9.]+)[[:space:]]+([0-9.]+)[[:space:]]+([0-9.]+)[[:space:]]*\].*/\3 \4/')"
  local w h
  w="$(printf '%s' "$dims" | awk '{print int($1 + 0.5)}')"
  h="$(printf '%s' "$dims" | awk '{print int($2 + 0.5)}')"

  if [ "$w" -lt "$min_w" ] || [ "$w" -gt "$max_w" ] || [ "$h" -lt "$min_h" ] || [ "$h" -gt "$max_h" ]; then
    fail "PDF MediaBox dimensions for $expected_label out of expected bounds: ${w}x${h} pts"
  fi
  echo "PASS: Verified $expected_label PDF MediaBox (${w}x${h} pts)"
}

# 0. Verify fixtures exist
assert_file_exists "$FIX_GENERIC"
assert_file_exists "$FIX_TODO"
assert_file_exists "$FIX_TRAPS"

# 1. Verify trap fixture integrity
grep -q 'tabindex="-1"' "$FIX_TRAPS" || fail "Trap fixture missing tabindex=-1 honeypot"
grep -q 'FROBSCOTTLE' "$FIX_TRAPS" || fail "Trap fixture missing prompt-injection canary"
grep -q 'no_ai_attestation' "$FIX_TRAPS" || fail "Trap fixture missing anti-LLM honesty gate"
grep -q 'non-compete' "$FIX_TRAPS" || fail "Trap fixture missing shady legal clause trigger"
echo "PASS: ATS trap fixture integrity verified"

# 2. Validate JSON files
validate_json_file "$PLUGIN_JSON" 1
validate_json_file "$HOOKS_JSON" 0
validate_json_file "$SCOUT_SIDECAR" 0
validate_json_file "$APPLY_SIDECAR" 0

# 3. Verify renderer script existence & syntax
if [ ! -f "$RENDERER" ]; then
  if [ "$SKIP_MISSING_SIBLINGS" -eq 1 ]; then
    echo "SKIP: Renderer script not yet created ($RENDERER)"
    exit 0
  fi
  fail "Renderer script missing: $RENDERER"
fi

[ -x "$RENDERER" ] || fail "Renderer script is not executable: $RENDERER"
bash -n "$RENDERER" || fail "Bash syntax check failed for $RENDERER"
echo "PASS: Renderer executable & syntax valid"

# 4. Test [TODO: block (must exit 2 without --allow-todo)
TODO_BLOCKED_PDF="$WORK_TMP/todo_blocked.pdf"
set +e
"$RENDERER" "$FIX_TODO" "$TODO_BLOCKED_PDF" >/dev/null 2>&1
TODO_EXIT="$?"
set -e
if [ "$TODO_EXIT" -ne 2 ]; then
  fail "Expected exit code 2 for [TODO: without --allow-todo, got $TODO_EXIT"
fi
if [ -e "$TODO_BLOCKED_PDF" ]; then
  fail "Blocked [TODO: render unexpectedly produced output file: $TODO_BLOCKED_PDF"
fi
echo "PASS: Renderer exited 2 on unresolved [TODO: without --allow-todo"

# 5. Test --allow-todo draft pass (must exit 0)
TODO_ALLOWED_PDF="$WORK_TMP/todo_allowed.pdf"
"$RENDERER" "$FIX_TODO" "$TODO_ALLOWED_PDF" --allow-todo >/dev/null
[ -s "$TODO_ALLOWED_PDF" ] || fail "Expected non-empty draft PDF with --allow-todo"
echo "PASS: Renderer exited 0 with --allow-todo"

# 6. Test strict 1-page Letter rendering
LETTER_PDF="$WORK_TMP/generic_letter.pdf"
LETTER_OUT="$("$RENDERER" "$FIX_GENERIC" "$LETTER_PDF" --strict-1-page)"
[ -s "$LETTER_PDF" ] || fail "Expected non-empty Letter PDF"
printf '%s\n' "$LETTER_OUT" | grep -q 'Page count: 1' || fail "Expected Page count: 1 for Letter fixture"
check_pdf_mediabox "$LETTER_PDF" "Letter" 608 616 788 796
echo "PASS: Letter 1-page strict render succeeded"

# 7. Test strict 1-page A4 rendering
A4_HTML="$WORK_TMP/sample_resume_generic_a4.html"
sed 's/data-page-size="letter"/data-page-size="a4"/' "$FIX_GENERIC" > "$A4_HTML"
A4_PDF="$WORK_TMP/generic_a4.pdf"
A4_OUT="$("$RENDERER" "$A4_HTML" "$A4_PDF" --strict-1-page)"
[ -s "$A4_PDF" ] || fail "Expected non-empty A4 PDF"
printf '%s\n' "$A4_OUT" | grep -q 'Page count: 1' || fail "Expected Page count: 1 for A4 fixture"
check_pdf_mediabox "$A4_PDF" "A4" 591 599 838 846
echo "PASS: A4 1-page strict render succeeded"

echo "ALL TESTS PASSED."
