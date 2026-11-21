#!/bin/sh
# Portable POSIX PreToolUse safety gate for the career-autopilot plugin.
# Reads Antigravity PreToolUse JSON from stdin without jq, enforces safety
# invariants, and prints a JSON decision object on stdout.

set -eu

emit_json() {
  decision="$1"
  reason="${2:-}"
  if [ -z "$reason" ]; then
    printf '{"decision":"%s"}\n' "$decision"
    return 0
  fi
  escaped_reason="$(printf '%s' "$reason" | LC_ALL=C awk '
    BEGIN { out = "" }
    {
      line = $0
      gsub(/\\/, "\\\\", line)
      gsub(/"/, "\\\"", line)
      gsub(/\t/, "\\t", line)
      gsub(/\r/, "\\r", line)
      if (NR > 1) out = out "\\n" line
      else out = line
    }
    END { printf "%s", out }
  ')"
  printf '{"decision":"%s","reason":"%s"}\n' "$decision" "$escaped_reason"
}

resolve_path() {
  raw_path="$1"
  base_cwd="$2"
  case "$raw_path" in
    "~"/*)
      printf '%s/%s\n' "${HOME:-}" "${raw_path#~/}"
      ;;
    /*)
      printf '%s\n' "$raw_path"
      ;;
    *)
      if [ -n "$base_cwd" ]; then
        printf '%s/%s\n' "${base_cwd%/}" "$raw_path"
      else
        printf '%s\n' "$raw_path"
      fi
      ;;
  esac
}

check_pdf_todo_gate() {
  pdf_input="$1"
  base_cwd="$2"
  pdf_abs="$(resolve_path "$pdf_input" "$base_cwd")"

  if [ -f "$pdf_abs" ]; then
    if LC_ALL=C grep -Eq '\[TODO:|\[USER INPUT NEEDED' "$pdf_abs" 2>/dev/null; then
      printf 'Blocked: resume PDF "%s" contains unresolved [TODO: or [USER INPUT NEEDED placeholders.\n' "$pdf_input"
      return 1
    fi
  fi

  pdf_dir="$(dirname "$pdf_abs")"
  for candidate_html in "$pdf_dir/resume_tailored.html" "$pdf_dir/backup_resume.html"; do
    if [ -f "$candidate_html" ]; then
      if LC_ALL=C grep -Eq '\[TODO:|\[USER INPUT NEEDED' "$candidate_html" 2>/dev/null; then
        printf 'Blocked: source HTML "%s" for "%s" still contains unresolved [TODO: or [USER INPUT NEEDED placeholders. Resolve and re-render without --allow-todo first.\n' "$candidate_html" "$pdf_input"
        return 1
      fi
    fi
  done

  return 0
}

AWK_RESULT="$(LC_ALL=C awk '
function parse_json_str(s, start_pos,    n, p, ch, esc, out, hex4) {
  n = length(s)
  p = start_pos + 1
  out = ""
  while (p <= n) {
    ch = substr(s, p, 1)
    if (ch == "\\") {
      p++
      if (p > n) break
      esc = substr(s, p, 1)
      if (esc == "\"" || esc == "\\" || esc == "/") out = out esc
      else if (esc == "n") out = out "\n"
      else if (esc == "t") out = out "\t"
      else if (esc == "r") out = out "\r"
      else if (esc == "b" || esc == "f") out = out " "
      else if (esc == "u" && p + 4 <= n) {
        hex4 = substr(s, p + 1, 4)
        p += 4
        out = out "?"
      } else {
        out = out esc
      }
      p++
    } else if (ch == "\"") {
      jp_next = p + 1
      return out
    } else {
      out = out ch
      p++
    }
  }
  jp_next = n + 1
  return out
}

function parse_hook_json(buf,    n, p, c, depth, expect_val, val, pk, gpk, k, tmp_p, next_c, ctype, parent_key, cur_key) {
  n = length(buf)
  p = 1
  depth = 0
  expect_val = 0
  tool_name = ""
  cmd_line = ""
  hook_cwd = ""

  while (p <= n) {
    c = substr(buf, p, 1)
    if (c ~ /[ \t\r\n,]/) {
      p++
      continue
    }
    if (c == "{") {
      depth++
      ctype[depth] = "{"
      parent_key[depth] = (expect_val && depth > 1 ? cur_key[depth - 1] : "")
      cur_key[depth] = ""
      expect_val = 0
      p++
    } else if (c == "[") {
      depth++
      ctype[depth] = "["
      parent_key[depth] = (expect_val && depth > 1 ? cur_key[depth - 1] : "")
      cur_key[depth] = ""
      expect_val = 0
      p++
    } else if (c == "}" || c == "]") {
      if (depth > 0) depth--
      expect_val = 0
      p++
    } else if (c == ":") {
      expect_val = 1
      p++
    } else if (c == "\"") {
      val = parse_json_str(buf, p)
      p = jp_next
      if (depth > 0 && ctype[depth] == "{" && !expect_val) {
        tmp_p = p
        while (tmp_p <= n && substr(buf, tmp_p, 1) ~ /[ \t\r\n]/) tmp_p++
        next_c = (tmp_p <= n ? substr(buf, tmp_p, 1) : "")
        if (next_c == ":") {
          cur_key[depth] = val
        }
      } else if (expect_val && depth > 0) {
        k = cur_key[depth]
        pk = parent_key[depth]
        gpk = (depth >= 2 ? parent_key[depth - 1] : "")
        if (depth == 2 && pk == "toolCall" && k == "name") {
          tool_name = val
        } else if (depth == 1 && k == "name" && tool_name == "") {
          tool_name = val
        } else if (depth == 3 && gpk == "toolCall" && pk == "args" && (k == "CommandLine" || k == "commandLine" || k == "command")) {
          cmd_line = val
        } else if (depth == 2 && pk == "args" && (k == "CommandLine" || k == "commandLine" || k == "command") && cmd_line == "") {
          cmd_line = val
        } else if (depth == 1 && (k == "CommandLine" || k == "commandLine") && cmd_line == "") {
          cmd_line = val
        } else if (depth == 1 && k == "cwd") {
          hook_cwd = val
        }
        expect_val = 0
      } else {
        expect_val = 0
      }
    } else {
      expect_val = 0
      if (c ~ /[A-Za-z0-9_.+-]/) {
        while (p <= n && substr(buf, p, 1) ~ /[A-Za-z0-9_.+-]/) p++
      } else {
        p++
      }
    }
  }
}

function base_name(path,    parts, cnt, i) {
  cnt = split(path, parts, "/")
  for (i = cnt; i >= 1; i--) {
    if (parts[i] != "") return parts[i]
  }
  return path
}

function is_protected_config(path) {
  return (path ~ /(^|\/)\.gemini\/config\/(user_)?config\.json$/)
}

function is_gmail_value_flag(fl) {
  return (fl ~ /^--(to|cc|bcc|subject|body|body-file|file|timezone|page-token|page_token|max|message|thread|id|emoji|name|bg-color|text-color|add|remove|add-labels|remove-labels|account)$/)
}

function split_segments(cmd, base_unatt,    n, i, ch, nx, in_sq, in_dq, cur, seg_cnt) {
  n = length(cmd)
  in_sq = 0
  in_dq = 0
  cur = ""
  seg_cnt = 0
  i = 1
  while (i <= n) {
    ch = substr(cmd, i, 1)
    nx = (i < n ? substr(cmd, i + 1, 1) : "")
    if (in_sq) {
      if (ch == "'"'"'") in_sq = 0
      cur = cur ch
      i++
    } else if (in_dq) {
      if (ch == "\\" && i < n) {
        cur = cur ch nx
        i += 2
        continue
      }
      if (ch == "\"") in_dq = 0
      cur = cur ch
      i++
    } else {
      if (ch == "\\" && i < n) {
        cur = cur ch nx
        i += 2
        continue
      }
      if (ch == "'"'"'") {
        in_sq = 1
        cur = cur ch
        i++
      } else if (ch == "\"") {
        in_dq = 1
        cur = cur ch
        i++
      } else if (ch == ";" || ch == "\n" || ch == "|" || ch == "(" || ch == ")" || ch == "`") {
        seg_cnt++
        segs[seg_cnt] = cur
        seg_unatts[seg_cnt] = base_unatt
        cur = ""
        if (ch == "|" && nx == "|") i += 2
        else i++
      } else if (ch == "$" && nx == "(") {
        seg_cnt++
        segs[seg_cnt] = cur
        seg_unatts[seg_cnt] = base_unatt
        cur = ""
        i += 2
      } else if (ch == "&") {
        seg_cnt++
        segs[seg_cnt] = cur
        seg_unatts[seg_cnt] = base_unatt
        cur = ""
        if (nx == "&") i += 2
        else i++
      } else {
        cur = cur ch
        i++
      }
    }
  }
  if (cur != "") {
    seg_cnt++
    segs[seg_cnt] = cur
    seg_unatts[seg_cnt] = base_unatt
  }
  return seg_cnt
}

function tokenize_segment(seg,    n, i, ch, nx, in_sq, in_dq, tok, has_tok, wc, redir_pending) {
  n = length(seg)
  in_sq = 0
  in_dq = 0
  tok = ""
  has_tok = 0
  wc = 0
  redir_pending = 0
  delete words
  delete redir_targets

  i = 1
  while (i <= n) {
    ch = substr(seg, i, 1)
    nx = (i < n ? substr(seg, i + 1, 1) : "")
    if (in_sq) {
      if (ch == "'"'"'") in_sq = 0
      else tok = tok ch
      i++
    } else if (in_dq) {
      if (ch == "\\" && i < n) {
        if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") {
          tok = tok nx
        } else {
          tok = tok ch nx
        }
        i += 2
        continue
      }
      if (ch == "\"") in_dq = 0
      else tok = tok ch
      i++
    } else {
      if (ch ~ /[ \t\r]/) {
        if (has_tok) {
          if (redir_pending) {
            redir_targets[tok] = 1
            redir_pending = 0
          } else {
            wc++
            words[wc] = tok
          }
          tok = ""
          has_tok = 0
        }
        i++
      } else if (ch == ">" || ch == "<") {
        if (has_tok) {
          if (redir_pending) {
            redir_targets[tok] = 1
            redir_pending = 0
          } else {
            wc++
            words[wc] = tok
          }
          tok = ""
          has_tok = 0
        }
        if (ch == ">") {
          redir_pending = 1
          if (nx == ">") i += 2
          else i++
        } else {
          i++
        }
      } else if (ch == "\\" && i < n) {
        has_tok = 1
        tok = tok nx
        i += 2
      } else if (ch == "'"'"'") {
        in_sq = 1
        has_tok = 1
        i++
      } else if (ch == "\"") {
        in_dq = 1
        has_tok = 1
        i++
      } else {
        has_tok = 1
        tok = tok ch
        i++
      }
    }
  }
  if (has_tok) {
    if (redir_pending) {
      redir_targets[tok] = 1
    } else {
      wc++
      words[wc] = tok
    }
  }
  return wc
}

function inspect_segment(seg, base_unatt,    wc, idx, tok, seg_unatt, eq_pos, vname, vval, exe, exe_lc, i, g_group, g_action, g_subj, g_query, g_files, g_file_cnt, fflag, fval, skip_next, has_upload_target, has_sed_inplace, has_allow_todo, shell_c_next, t, rt) {
  wc = tokenize_segment(seg)
  if (wc == 0) {
    for (rt in redir_targets) {
      if (is_protected_config(rt)) {
        deny_reason = "Blocked: never hand-edit ~/.gemini/config/config.json or user_config.json."
        return 1
      }
    }
    return 0
  }

  for (rt in redir_targets) {
    if (is_protected_config(rt)) {
      deny_reason = "Blocked: never hand-edit ~/.gemini/config/config.json or user_config.json."
      return 1
    }
  }

  seg_unatt = base_unatt
  idx = 1

  while (idx <= wc) {
    tok = words[idx]
    if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      eq_pos = index(tok, "=")
      vname = substr(tok, 1, eq_pos - 1)
      vval = substr(tok, eq_pos + 1)
      if (vname == "AGY_UNATTENDED" && vval != "") seg_unatt = 1
      idx++
      continue
    }
    if (tok == "env") {
      idx++
      while (idx <= wc) {
        t = words[idx]
        if (t == "-u" && idx < wc) {
          idx += 2
          continue
        }
        if (t ~ /^-[A-Za-z0]+$/) {
          idx++
          continue
        }
        if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
          eq_pos = index(t, "=")
          vname = substr(t, 1, eq_pos - 1)
          vval = substr(t, eq_pos + 1)
          if (vname == "AGY_UNATTENDED" && vval != "") seg_unatt = 1
          idx++
          continue
        }
        break
      }
      continue
    }
    if (tok == "command") {
      if (idx < wc && (words[idx + 1] == "-v" || words[idx + 1] == "-V")) {
        return 0
      }
      idx++
      if (idx <= wc && words[idx] == "-p") idx++
      continue
    }
    break
  }

  if (idx > wc) return 0

  exe = base_name(words[idx])
  exe_lc = tolower(exe)

  if (exe_lc == "which" || exe_lc == "type") return 0

  # Recurse into sh/bash/zsh -c scripts
  if (exe_lc ~ /^(sh|bash|zsh|dash|ksh|ash)$/) {
    shell_c_next = 0
    for (i = idx + 1; i <= wc; i++) {
      if (shell_c_next) {
        q_tail++
        q_cmd[q_tail] = words[i]
        q_unatt[q_tail] = seg_unatt
        break
      }
      if (words[i] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
        shell_c_next = 1
      }
    }
    return 0
  }

  # Prohibited PDF toolchains
  if (exe_lc ~ /^(pdflatex|xelatex|lualatex|typst|weasyprint)$/) {
    deny_reason = "Blocked: prohibited PDF toolchain \"" exe "\". Use render_resume_pdf.sh (headless Chrome/Chromium/Edge) instead."
    return 1
  }

  # Direct config writes via tee, cp, mv, rm, sed -i
  if (exe_lc ~ /^(tee|cp|mv|rm|install|touch|truncate)$/) {
    for (i = idx + 1; i <= wc; i++) {
      if (is_protected_config(words[i])) {
        deny_reason = "Blocked: never modify ~/.gemini/config/config.json or user_config.json from run_command."
        return 1
      }
    }
  }
  if (exe_lc == "sed") {
    has_sed_inplace = 0
    for (i = idx + 1; i <= wc; i++) {
      if (words[i] ~ /^-i/ || words[i] == "--in-place") has_sed_inplace = 1
      if (has_sed_inplace && is_protected_config(words[i])) {
        deny_reason = "Blocked: never modify ~/.gemini/config/config.json or user_config.json from run_command."
        return 1
      }
    }
  }

  # Language Server restricted mutation RPCs
  if (exe_lc == "curl" || exe_lc == "lsrpc") {
    for (i = idx + 1; i <= wc; i++) {
      if (words[i] ~ /(JetboxWriteState|DeletePlugin|InstallCustomization)/) {
        deny_reason = "Blocked: Language Server state-mutation RPCs are restricted from run_command."
        return 1
      }
    }
  }

  # Direct browser --print-to-pdf bypassing render_resume_pdf.sh
  if (exe_lc ~ /^(google-chrome|google-chrome-stable|chromium|chromium-browser|microsoft-edge|google chrome|microsoft edge|chrome\.exe|msedge\.exe)$/) {
    for (i = idx + 1; i <= wc; i++) {
      if (words[i] ~ /^--print-to-pdf(=|$)/) {
        deny_reason = "Blocked: direct headless browser --print-to-pdf bypasses the [TODO: placeholder gate. Use render_resume_pdf.sh instead."
        return 1
      }
    }
  }

  # Track render_resume_pdf calls
  if (exe_lc ~ /^render_resume_pdf(\.sh|\.ps1)?$/) {
    has_allow_todo = 0
    for (i = idx + 1; i <= wc; i++) {
      if (words[i] == "--allow-todo") has_allow_todo = 1
    }
    if (has_allow_todo) {
      saw_allow_todo_render = 1
      if (seg_unatt) {
        deny_reason = "Blocked: --allow-todo draft rendering is disallowed when AGY_UNATTENDED is set."
        return 1
      }
    }
    return 0
  }

  # Staging PDF into browser_sandbox/uploads/
  if (exe_lc ~ /^(cp|mv|install|rsync)$/) {
    has_upload_target = 0
    for (i = idx + 1; i <= wc; i++) {
      if (words[i] ~ /browser_sandbox\/uploads(\/|$)/) has_upload_target = 1
    }
    if (has_upload_target) {
      if (saw_allow_todo_render) {
        deny_reason = "Blocked: cannot stage a PDF rendered with --allow-todo into browser_sandbox/uploads/."
        return 1
      }
      for (i = idx + 1; i <= wc; i++) {
        if (tolower(words[i]) ~ /\.pdf$/ && !(words[i] ~ /browser_sandbox\/uploads/)) {
          pdf_check_cnt++
          pdf_checks[pdf_check_cnt] = words[i]
        }
      }
    }
    return 0
  }

  # Gmail CLI safety checks
  if (exe_lc == "gmail") {
    g_group = ""
    g_action = ""
    g_subj = ""
    g_query = ""
    g_file_cnt = 0
    skip_next = 0

    for (i = idx + 1; i <= wc; i++) {
      tok = words[i]
      if (skip_next) {
        skip_next = 0
        continue
      }
      if (tok ~ /^--[A-Za-z0-9_-]+=/) {
        eq_pos = index(tok, "=")
        fflag = substr(tok, 1, eq_pos - 1)
        fval = substr(tok, eq_pos + 1)
        if (fflag == "--file" && tolower(fval) ~ /\.pdf$/) {
          g_file_cnt++
          g_files[g_file_cnt] = fval
        } else if (fflag == "--subject") {
          g_subj = fval
        }
        continue
      }
      if (tok ~ /^-/) {
        if (is_gmail_value_flag(tok) && i < wc) {
          fval = words[i + 1]
          if (tok == "--file" && tolower(fval) ~ /\.pdf$/) {
            g_file_cnt++
            g_files[g_file_cnt] = fval
          } else if (tok == "--subject") {
            g_subj = fval
          }
          skip_next = 1
        }
        continue
      }

      if (g_group == "") {
        if (tok == "auth" || tok == "readonly" || tok == "mutate") {
          g_group = tok
        }
        continue
      }

      if (g_group == "auth") {
        if (tok == "login" || tok == "status") {
          deny_reason = "Blocked: \"gmail auth " tok "\" fails inside the sandbox; use list_plugin_accounts or sign in via the Gmail plugin card."
          return 1
        }
      } else if (g_group == "readonly") {
        g_query = (g_query == "" ? tok : g_query " " tok)
      } else if (g_group == "mutate") {
        if (g_action == "") {
          if (tok ~ /^(create-draft|update-draft|drafts|create-label|update-label|add-label|remove-label|delete-label|mark-read|mark-unread|archive|thread-modify|batch-modify|delete-draft|trash|delete-reaction|unreact|send|send-draft|send-with-attachment|reply|forward|react|create-reaction)$/) {
            g_action = tok
          }
        }
      }
    }

    if (g_group == "readonly") {
      if (tolower(g_query) ~ /(confirm you.?re a human|(greenhouse|ashby).{0,40}verification code|verification code.{0,40}(greenhouse|ashby))/) {
        deny_reason = "Blocked: auto-reading Gmail for ATS human-verification security codes is strictly forbidden."
        return 1
      }
      return 0
    }

    if (g_group == "mutate") {
      if ((g_subj ~ /^Job Application/ && g_subj ~ /->/) || g_subj ~ / -> /) {
        deny_reason = "Blocked: job application email subject must not contain \"->\"."
        return 1
      }
      if (g_file_cnt > 0 && g_action ~ /^(create-draft|update-draft|send|send-with-attachment|reply|forward)$/) {
        if (saw_allow_todo_render) {
          deny_reason = "Blocked: cannot attach a PDF rendered with --allow-todo to a Gmail draft or email."
          return 1
        }
        for (i = 1; i <= g_file_cnt; i++) {
          pdf_check_cnt++
          pdf_checks[pdf_check_cnt] = g_files[i]
        }
      }
      if (g_action ~ /^(send|send-draft|send-with-attachment|reply|forward|react|create-reaction)$/) {
        if (seg_unatt) {
          deny_reason = "Blocked: \"gmail mutate " g_action "\" is forbidden when AGY_UNATTENDED is set. Use \"gmail mutate create-draft\" instead."
          return 1
        }
        need_force_ask = 1
        force_ask_reason = "HITL cold-email gate: confirm recipient, subject (no current employer or ->), body, and [TODO:]-free PDF before running \"gmail mutate " g_action "\"."
      }
    }
  }

  return 0
}

{
  if (NR == 1) raw_buf = $0
  else raw_buf = raw_buf "\n" $0
}

END {
  if (raw_buf == "") {
    print "A"
    exit 0
  }

  parse_hook_json(raw_buf)

  if (tool_name != "" && tool_name != "run_command") {
    print "A"
    exit 0
  }
  if (cmd_line == "") {
    print "A"
    exit 0
  }

  deny_reason = ""
  need_force_ask = 0
  force_ask_reason = ""
  saw_allow_todo_render = 0
  pdf_check_cnt = 0

  q_head = 1
  q_tail = 1
  q_cmd[1] = cmd_line
  q_unatt[1] = (ENVIRON["AGY_UNATTENDED"] != "" ? 1 : 0)

  while (q_head <= q_tail) {
    cur_c = q_cmd[q_head]
    cur_u = q_unatt[q_head]
    q_head++

    delete segs
    delete seg_unatts
    seg_cnt = split_segments(cur_c, cur_u)
    for (s_i = 1; s_i <= seg_cnt; s_i++) {
      if (inspect_segment(segs[s_i], seg_unatts[s_i]) != 0) {
        print "D\t" deny_reason
        exit 0
      }
    }
  }

  if (hook_cwd != "") {
    print "C\t" hook_cwd
  }
  for (p_i = 1; p_i <= pdf_check_cnt; p_i++) {
    print "P\t" pdf_checks[p_i]
  }
  if (need_force_ask) {
    print "F\t" force_ask_reason
  } else {
    print "A"
  }
}
' 2>/dev/null || printf 'A\n')"

HOOK_CWD=""
FORCE_ASK_REASON=""
TAB="$(printf '\t')"

while IFS= read -r line; do
  [ -z "$line" ] && continue
  kind="${line%%"$TAB"*}"
  payload=""
  case "$line" in
    *"$TAB"*) payload="${line#*"$TAB"}" ;;
  esac

  case "$kind" in
    D)
      emit_json "deny" "$payload"
      exit 0
      ;;
    C)
      HOOK_CWD="$payload"
      ;;
    P)
      if ! err_msg="$(check_pdf_todo_gate "$payload" "$HOOK_CWD")"; then
        emit_json "deny" "$err_msg"
        exit 0
      fi
      ;;
    F)
      FORCE_ASK_REASON="$payload"
      ;;
    A)
      ;;
  esac
done <<EOF
$AWK_RESULT
EOF

if [ -n "$FORCE_ASK_REASON" ]; then
  emit_json "force_ask" "$FORCE_ASK_REASON"
else
  emit_json "allow"
fi
exit 0
