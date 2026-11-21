# Scheduled Automations (`career-autopilot`)

Parameterized Antigravity **Scheduled Sidecar** (`"builtin": "schedule"`) templates and a portable bash installer for recurring job discovery and draft/pre-stage application runs.

## Included Templates

1. **`find-new-jobs.sidecar.json.template`** — *`<FirstName> — Find New Jobs`*
   - **Installed target:** `~/.gemini/config/sidecars/<firstname>-find-jobs/sidecar.json` (auto-detected from `--first-name`, `<workspace>/GLOBAL_REFERENCE.md` `full_name`, `git config user.name`, or OS user; overridable with `--prefix`, fallback `career-autopilot`)
   - **What it runs:** Invokes `career-autopilot-scout` against your private workspace, audits Ashby (`posting-api` + `ApiJobPosting`), Greenhouse (`boards-api` + embed), Lever, YC Jobs, HN *Who is Hiring*, and configured boards, screens for hidden geo/visa gates, localization risk, anti-LLM checks, prompt injections, and honeypots, deduplicates against `applications/tracker.md` and `applications/new_leads.md`, and queues verified `Tier A` / `Tier B1` leads.
   - **Permissions:** Scoped strictly to `read_file`/`write_file` on `{{WORKSPACE_PATH}}`, `command(curl)`, and explicit ATS `read_url(<domain>)` grants (no wildcards).

2. **`auto-apply.sidecar.json.template`** — *`<FirstName> — Apply & Draft Pipeline`*
   - **Installed target:** `~/.gemini/config/sidecars/<firstname>-auto-apply/sidecar.json`
   - **What it runs:** Invokes `career-autopilot-apply` on queued leads, fans out up to 32 isolated per-application workers (`applications/<company-slug>/`), renders strict 1-page PDFs via `{{SCRIPT_RENDERER_PATH}}` (`--strict-1-page`), executes Workflow 2 respecting `execution_and_safety_policy.web_apply_mode` (`hitl_pre_submit` by default; `yolo_with_guardrails` only if opted in), and prepares strict HITL cold-email drafts (`AGY_UNATTENDED=1` draft-only Gmail or copy-paste `cold_email.md` dossiers).
   - **Safety guarantees:** Never holds `gmail mutate send*`, `send-draft`, `send-with-attachment`, `reply`, or `forward` permissions, never uses wildcard grants (`command(*)`, `read_file(*)`, etc.), and stops unconditionally on CAPTCHAs, email human-verification security codes, login/MFA gates, anti-LLM honesty prompts, and shady legal clauses.

## Quick Install

Run the idempotent installer with your workspace path (defaults to `Asia/Kolkata` timezone, `0 8 * * *` discovery, and `0 9 * * *` apply/draft):

```bash
./install-sidecars.sh \
  --workspace "/path/to/your/job-search-workspace" \
  --tz "Asia/Kolkata" \
  --scout-cron "0 8 * * *" \
  --apply-cron "0 9 * * *" \
  --email "candidate@example.com"
```

If you use Outlook, Proton, Apple Mail, or prefer copy-paste dossiers without connecting the Gmail plugin, pass `--no-gmail` (strips Gmail CLI grants cleanly):

```bash
./install-sidecars.sh --workspace "/path/to/your/job-search-workspace" --no-gmail
```

To preview rendered JSON files in a temporary directory without touching `~/.gemini/config/sidecars/`:

```bash
./install-sidecars.sh \
  --workspace "/path/to/your/job-search-workspace" \
  --no-gmail \
  --dry-run /tmp/career-autopilot-sidecars
```

## Placeholders Reference

| Placeholder | Default / Example | Purpose |
| :--- | :--- | :--- |
| `{{WORKSPACE_PATH}}` | `/path/to/your/job-search-workspace` | Scopes `workspace_uris` (`file://...` URI-encoded), `read_file`, `write_file`, and prompt workspace context |
| `{{SCRIPT_RENDERER_PATH}}` | Auto-detected `render_resume_pdf.sh` | Exact path granted via `command(...)` for strict 1-page PDF rendering |
| `{{CRON_TZ}}` | `Asia/Kolkata` | IANA timezone placed in `CRON_TZ=<zone>` at `args[0]` |
| `{{CRON_SCHEDULE}}` | `0 8 * * *` / `0 9 * * *` | Standard 5-field cron expression (`minute hour day-of-month month day-of-week`) |
| `{{EMAIL_ACCOUNT}}` | `candidate@example.com` or `none` | Passed to `AGY_ACCOUNT` for draft-only `gmail mutate create-draft` |
| `{{DISPLAY_PREFIX}}` | `<FirstName>` (e.g., `Alex` or `Career Autopilot`) | Title-cased prefix shown in the Automations dashboard `display_name` |

### Common Schedules (`Asia/Kolkata` / IST)

- **Daily 8:00 AM / 9:00 AM IST:** `0 8 * * *` / `0 9 * * *`
- **Weekdays (Mon–Fri) 9:00 AM IST:** `0 9 * * 1-5`
- **Twice Daily (9:00 AM & 9:00 PM IST):** `0 9,21 * * *`
- **Weekly (Monday 9:00 AM IST):** `0 9 * * 1`

## Enabling Automations Safely

`install-sidecars.sh` **never** edits `user_config.json` and **never** enables sidecars automatically. After installing:

1. Run an interactive test run of discovery and apply in Antigravity so global permissions and `render_resume_pdf.sh` execution are verified.
2. Open the **Automations** dashboard (`[Open Automations Dashboard](sidecar://dashboard)`) and manually enable:
   - **`<FirstName> — Find New Jobs`** (`<firstname>-find-jobs`)
   - **`<FirstName> — Apply & Draft Pipeline`** (`<firstname>-auto-apply`)
