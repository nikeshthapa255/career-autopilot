#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: render_resume_pdf.sh <input.html> <output.pdf> [--allow-todo] [--strict-1-page]

Renders an ATS-clean HTML resume to PDF via headless Chrome, Chromium, or Edge.
Supports macOS, Linux, WSL (Linux or Windows chrome.exe), and $RESUME_CHROME_BIN.

Options:
  --allow-todo     Allow "[TODO:" or "[USER INPUT NEEDED" markers for draft preview.
  --strict-1-page  Exit with code 5 if the rendered PDF is not strictly 1 page.
  -h, --help       Show this help message and exit.

Exit codes:
  0  Success
  1  Invalid arguments, missing input HTML, or no Chrome/Chromium/Edge binary found
  2  Unresolved "[TODO:" or "[USER INPUT NEEDED" placeholder found (without --allow-todo)
  3  Headless browser rendering failed
  4  Output PDF missing or empty
  5  --strict-1-page enabled and output PDF is not 1 page
EOF
}

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

resolve_chrome_bin() {
  local candidate=""

  if [ -n "${RESUME_CHROME_BIN:-}" ]; then
    if [ -x "$RESUME_CHROME_BIN" ]; then
      printf '%s\n' "$RESUME_CHROME_BIN"
      return 0
    fi
    if candidate="$(command -v "$RESUME_CHROME_BIN" 2>/dev/null)" && [ -n "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    echo "ERROR: RESUME_CHROME_BIN is set but not executable: $RESUME_CHROME_BIN" >&2
    return 1
  fi

  local os_name
  os_name="$(uname -s 2>/dev/null || printf 'Unknown')"

  case "$os_name" in
    Darwin)
      for candidate in \
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
        "/Applications/Chromium.app/Contents/MacOS/Chromium" \
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
        "${HOME}/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
        "${HOME}/Applications/Chromium.app/Contents/MacOS/Chromium"; do
        if [ -x "$candidate" ]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      for candidate in google-chrome chromium microsoft-edge; do
        if command -v "$candidate" >/dev/null 2>&1; then
          command -v "$candidate"
          return 0
        fi
      done
      ;;
    Linux)
      for candidate in \
        google-chrome \
        google-chrome-stable \
        chromium \
        chromium-browser \
        microsoft-edge \
        microsoft-edge-stable; do
        if command -v "$candidate" >/dev/null 2>&1; then
          command -v "$candidate"
          return 0
        fi
      done
      for candidate in \
        /snap/bin/chromium \
        /usr/bin/google-chrome \
        /usr/bin/chromium \
        /usr/bin/chromium-browser; do
        if [ -x "$candidate" ]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      if is_wsl; then
        for candidate in \
          "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" \
          "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
          "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
          "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"; do
          if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
        if command -v wslvar >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
          local win_local_app
          win_local_app="$(wslvar LOCALAPPDATA 2>/dev/null || true)"
          if [ -n "$win_local_app" ]; then
            candidate="$(wslpath -u "$win_local_app")/Google/Chrome/Application/chrome.exe"
            if [ -x "$candidate" ]; then
              printf '%s\n' "$candidate"
              return 0
            fi
          fi
        fi
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      for candidate in chrome chrome.exe msedge msedge.exe chromium; do
        if command -v "$candidate" >/dev/null 2>&1; then
          command -v "$candidate"
          return 0
        fi
      done
      for candidate in \
        "/c/Program Files/Google/Chrome/Application/chrome.exe" \
        "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
        "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
        "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"; do
        if [ -x "$candidate" ]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      ;;
  esac

  echo "ERROR: No supported Chrome, Chromium, or Microsoft Edge binary found." >&2
  echo "Install Google Chrome or Chromium, or set RESUME_CHROME_BIN=/path/to/browser." >&2
  echo "On native Windows PowerShell, use scripts/render_resume_pdf.ps1." >&2
  return 1
}

percent_encode_path() {
  local raw_path="$1"
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$raw_path" | perl -pe '
      s{^([A-Za-z]):/}{$1\0/};
      s{([^A-Za-z0-9_.~\/\0-])}{sprintf("%%%02X", ord($1))}ge;
      s{\0}{:}g;
    '
    return 0
  fi

  # Pure POSIX awk fallback (handles arbitrary bytes in C locale without Python/Node)
  printf '%s' "$raw_path" | LC_ALL=C awk '
  BEGIN {
    for (i = 1; i <= 255; i++) {
      c = sprintf("%c", i)
      ord[c] = sprintf("%%%02X", i)
    }
  }
  {
    if (NR > 1) printf "%%0A"
    out = ""
    n = length($0)
    for (i = 1; i <= n; i++) {
      ch = substr($0, i, 1)
      if (i == 2 && ch == ":" && substr($0, 1, 1) ~ /^[A-Za-z]$/) {
        out = out ch
      } else if (ch ~ /^[A-Za-z0-9_.~\/-]$/) {
        out = out ch
      } else if (ch in ord) {
        out = out ord[ch]
      }
    }
    printf "%s", out
  }'
}

build_file_uri() {
  local fs_path="$1"
  local encoded
  encoded="$(percent_encode_path "$fs_path")"
  case "$encoded" in
    /*)
      printf 'file://%s\n' "$encoded"
      ;;
    *)
      printf 'file:///%s\n' "$encoded"
      ;;
  esac
}

count_pdf_pages() {
  local pdf_file="$1"
  local count=""

  if command -v pdfinfo >/dev/null 2>&1; then
    count="$(pdfinfo "$pdf_file" 2>/dev/null | LC_ALL=C awk -F: '/^Pages:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' || true)"
  fi

  if [ -z "$count" ] && command -v perl >/dev/null 2>&1; then
    count="$(perl -0777 -ne '
      my @counts = (/\/Type\s*\/Pages\b[^<>]*?\/Count\s+(\d+)/gs);
      if (@counts) {
        my $max = (sort { $b <=> $a } @counts)[0];
        print $max;
      }
    ' "$pdf_file" 2>/dev/null || true)"
  fi

  if [ -z "$count" ]; then
    count="$(LC_ALL=C grep -Eoa '/Type[[:space:]]*/Pages|/Count[[:space:]]+[0-9]+' "$pdf_file" 2>/dev/null | LC_ALL=C awk '
      /\/Type[[:space:]]*\/Pages/ { in_pages = 1; next }
      in_pages && /\/Count[[:space:]]+[0-9]+/ {
        val = $0
        sub(/^.*\/Count[[:space:]]+/, "", val)
        val += 0
        if (val > max) max = val
        in_pages = 0
      }
      END { if (max > 0) print max }
    ' || true)"
  fi

  if [ -z "$count" ]; then
    count="$(LC_ALL=C grep -Eoa -c '/Type[[:space:]]*/Page([^s]|$)' "$pdf_file" 2>/dev/null || true)"
  fi

  if [ -z "$count" ] || [ "$count" = "0" ]; then
    if command -v mdls >/dev/null 2>&1; then
      local mdls_pages
      mdls_pages="$(mdls -raw -name kMDItemNumberOfPages "$pdf_file" 2>/dev/null || true)"
      if [[ "$mdls_pages" =~ ^[0-9]+$ ]]; then
        count="$mdls_pages"
      fi
    fi
  fi

  printf '%s\n' "$count"
}

ALLOW_TODO=0
STRICT_1_PAGE=0
POSITIONAL=()
END_OF_OPTS=0

for arg in "$@"; do
  if [ "$END_OF_OPTS" -eq 1 ]; then
    POSITIONAL+=("$arg")
    continue
  fi
  case "$arg" in
    --)
      END_OF_OPTS=1
      ;;
    --allow-todo)
      ALLOW_TODO=1
      ;;
    --strict-1-page)
      STRICT_1_PAGE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $arg" >&2
      usage
      exit 1
      ;;
    *)
      POSITIONAL+=("$arg")
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  echo "ERROR: Expected <input.html> and <output.pdf>." >&2
  usage
  exit 1
fi

INPUT_HTML="${POSITIONAL[0]}"
OUTPUT_PDF="${POSITIONAL[1]}"

if [ ! -f "$INPUT_HTML" ]; then
  echo "ERROR: Input HTML not found: $INPUT_HTML" >&2
  exit 1
fi

# Reject unresolved placeholders unless --allow-todo is explicitly enabled.
if grep -Eq '\[TODO:|\[USER INPUT NEEDED' "$INPUT_HTML"; then
  if [ "$ALLOW_TODO" -ne 1 ]; then
    echo "ERROR: Unresolved placeholder(s) found in $INPUT_HTML:" >&2
    grep -En '\[TODO:|\[USER INPUT NEEDED' "$INPUT_HTML" >&2 || true
    echo "Resolve placeholders before rendering final PDF, or pass --allow-todo for drafts." >&2
    exit 2
  else
    echo "INFO: --allow-todo enabled; rendering draft despite unresolved placeholder(s)."
  fi
fi

if grep -Eq '\{\{[A-Z0-9_]+\}\}' "$INPUT_HTML"; then
  echo "WARNING: Unreplaced {{...}} template token(s) detected in $INPUT_HTML." >&2
fi

CHROME_BIN="$(resolve_chrome_bin)" || exit 1

INPUT_DIR="$(cd "$(dirname "$INPUT_HTML")" && pwd -P)"
INPUT_ABS="$INPUT_DIR/$(basename "$INPUT_HTML")"

mkdir -p "$(dirname "$OUTPUT_PDF")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_PDF")" && pwd -P)"
OUTPUT_ABS="$OUTPUT_DIR/$(basename "$OUTPUT_PDF")"

CHROME_USER_DATA="$(mktemp -d "${TMPDIR:-/tmp}/chrome-resume-pdf-XXXXXX")"
CHROME_LOG="$(mktemp "${TMPDIR:-/tmp}/chrome-resume-log-XXXXXX")"
cleanup() {
  rm -rf "$CHROME_USER_DATA" "$CHROME_LOG"
}
trap cleanup EXIT

CHROME_INPUT_PATH="$INPUT_ABS"
CHROME_OUTPUT_PATH="$OUTPUT_ABS"
CHROME_PROFILE_PATH="$CHROME_USER_DATA"

if [[ "$CHROME_BIN" == *.exe ]]; then
  if is_wsl && command -v wslpath >/dev/null 2>&1; then
    CHROME_INPUT_PATH="$(wslpath -m "$INPUT_ABS")"
    CHROME_OUTPUT_PATH="$(wslpath -w "$OUTPUT_ABS")"
    CHROME_PROFILE_PATH="$(wslpath -w "$CHROME_USER_DATA")"
  elif command -v cygpath >/dev/null 2>&1; then
    CHROME_INPUT_PATH="$(cygpath -m "$INPUT_ABS")"
    CHROME_OUTPUT_PATH="$(cygpath -w "$OUTPUT_ABS")"
    CHROME_PROFILE_PATH="$(cygpath -w "$CHROME_USER_DATA")"
  else
    echo "ERROR: Windows browser binary ($CHROME_BIN) requires wslpath or cygpath to translate paths." >&2
    exit 1
  fi
fi

INPUT_URI="$(build_file_uri "$CHROME_INPUT_PATH")"

if ! "$CHROME_BIN" \
  --headless=new \
  --disable-gpu \
  --no-first-run \
  --no-default-browser-check \
  --disable-extensions \
  --no-pdf-header-footer \
  --user-data-dir="$CHROME_PROFILE_PATH" \
  --print-to-pdf="$CHROME_OUTPUT_PATH" \
  "$INPUT_URI" >"$CHROME_LOG" 2>&1; then
  echo "ERROR: Headless browser PDF rendering failed ($CHROME_BIN)." >&2
  cat "$CHROME_LOG" >&2 || true
  exit 3
fi

if [ ! -s "$OUTPUT_ABS" ]; then
  echo "ERROR: Output PDF is missing or empty: $OUTPUT_ABS" >&2
  cat "$CHROME_LOG" >&2 || true
  exit 4
fi

PAGE_COUNT="$(count_pdf_pages "$OUTPUT_ABS")"
FILE_SIZE_BYTES="$(wc -c < "$OUTPUT_ABS" | tr -d '[:space:]')"
echo "Rendered PDF: $OUTPUT_ABS (${FILE_SIZE_BYTES} bytes)"

if [[ "$PAGE_COUNT" =~ ^[0-9]+$ ]]; then
  echo "Page count: $PAGE_COUNT"
  if [ "$PAGE_COUNT" -gt 1 ]; then
    if [ "$STRICT_1_PAGE" -eq 1 ]; then
      echo "ERROR: Rendered resume spans $PAGE_COUNT pages (> 1 page) with --strict-1-page enabled." >&2
      exit 5
    fi
    echo "WARNING: Rendered resume spans $PAGE_COUNT pages (> 1 page). Tighten wording or CSS spacing." >&2
  elif [ "$PAGE_COUNT" -eq 0 ]; then
    if [ "$STRICT_1_PAGE" -eq 1 ]; then
      echo "ERROR: Could not verify 1-page count in PDF metadata with --strict-1-page enabled." >&2
      exit 5
    fi
    echo "WARNING: Could not verify non-zero page count in PDF metadata; inspect via read_file." >&2
  fi
else
  if [ "$STRICT_1_PAGE" -eq 1 ]; then
    echo "ERROR: Could not parse PDF page count with --strict-1-page enabled." >&2
    exit 5
  fi
  echo "WARNING: Could not parse page count automatically; inspect $OUTPUT_ABS via read_file." >&2
fi
