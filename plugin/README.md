# Career Autopilot

Role-agnostic, zero-PII job application automation for Antigravity.

The plugin keeps all logic, prompts, templates, and safety checks inside `career-autopilot`, separate from your private candidate workspace (`master_profile.md`, `GLOBAL_REFERENCE.md`, and `applications/`). Pre-seeded defaults target candidates based in India (`India`, `IST / UTC+5:30`, `Asia/Kolkata`, `+91` phone handling, no US visa assumed, INR LPA alongside USD/EUR compensation floors), while every geography, timezone, work mode (`remote`, `hybrid`, `onsite`), domain track, and currency can be changed during onboarding.

## Bundled components

- **Skills**
  - `career-autopilot-onboard`: Phase 0 intake from PDF, DOCX, Markdown, or plain text resumes, extracting a locked `Verified Quantitative Baseline`, running a structured preference interview, scaffolding the private workspace via `init-workspace.sh`, and verifying a baseline 1-page PDF.
  - `career-autopilot-scout`: Phase 1 multi-source discovery across Ashby, Greenhouse, Lever, YC, HN Algolia, Notion, Breezy, and generic public (`Mode A`) or authenticated (`Mode B` `--autoConnect`) portals with deduplication, tiering, YOE/FX checks, anti-LLM checks, and prompt-injection/honeypot screening.
  - `career-autopilot-apply`: Phase 2 execution across Workflow 1 (grounded tailoring and cross-platform headless Chrome/Chromium/Edge 1-page PDF rendering), Workflow 2 (serialized `browser_sandbox/uploads/` staging and guardrailed form filling), and Workflow 3 (verified public email outreach with strict HITL approval).
  - `clear-natural-english`: Prose clarity and anti-AI-slop editing standard (`SKILL.md` + `references/patterns-and-examples.md`) applied to tailored resume bullets, ATS essay responses, cold emails, and follow-ups.
- **Subagents**
  - `career-autopilot-scout`: Read-only Phase 1 discovery and screening scout.
  - `career-autopilot-worker`: Phase 2 isolated per-application worker scoped strictly to one `applications/<company-slug>/` folder.
- **Always-on rules (`rules/AGENTS.md`)**: Enforces zero fabrication, `[TODO:` placeholder gates, safe `hitl_pre_submit` default, unconditional anti-bot/anti-CAPTCHA/no-email-code-bypass rules, prompt-injection/honeypot defense, shady legal clause escalation, and strict HITL cold email gates.
- **Lifecycle hook (`hooks.json` -> `hooks/pre_tool_safety.sh`)**: Portable POSIX `sh` `PreToolUse` gate for `run_command` that blocks unattended Gmail sends (`AGY_UNATTENDED`), enforces interactive confirmation (`force_ask`) on live Gmail sends, prevents staging or attaching PDFs with unresolved `[TODO:` markers, blocks direct headless `--print-to-pdf` bypasses, and blocks prohibited PDF engines or direct config file edits.

## Installation and compatibility

The `career-autopilot` namespace is distinct from standalone `job-apply` setups and installs with zero collision.

### Global installation

Copy (or symlink) the `plugin/` directory to `~/.gemini/config/plugins/career-autopilot`:

```bash
cp -R plugin ~/.gemini/config/plugins/career-autopilot
```

Manage or toggle the plugin directly in Antigravity Customizations at [Career Autopilot](customization://career-autopilot). Do not hand-edit `~/.gemini/config/config.json`.

### Project-scoped installation

To load the plugin inside a single repository without global installation:

1. Copy or symlink `plugin/` to `.agents/plugins/career-autopilot/` inside your repository, **or**
2. Place it inside a directory named `career-autopilot/` and point `.agents/plugins.json` at its parent directory with `"include_only": ["career-autopilot"]`.

### Prerequisites and platform support

- **macOS, Linux, WSL, and Windows**: Headless PDF rendering uses Google Chrome, Chromium, or Microsoft Edge via `render_resume_pdf.sh` (POSIX bash) or `render_resume_pdf.ps1` (Windows PowerShell), supporting both `a4` and `letter` page sizes.
- **POSIX shell utilities**: `sh`, `awk`, `sed`, `grep`, and `unzip` (for DOCX resume parsing). `jq` is not required by the runtime `PreToolUse` hook.
- **Optional Gmail plugin**: Cold outreach can create drafts through the Antigravity `gmail` plugin (`AGY_ACCOUNT`) when connected, or fall back cleanly to copy-paste Markdown dossiers (`cold_email.md`) for any other mail client.
- **Optional Chrome DevTools (`--autoConnect`)**: Used in `Mode B` for login-gated boards (such as Workday, LinkedIn, Wellfound, Instahyre, Cutshort, or YC Work at a Startup) without asking for passwords or 2FA codes.
- **Optional scheduled automations**: Cron sidecar templates (`find-new-jobs` and `auto-apply`) live in `automations/` at the repository root. Install them with `automations/install-sidecars.sh` and enable them manually from [Open Automations Dashboard](sidecar://dashboard).

## Safety defaults

- **Browser apply (`web_apply_mode`)**: Defaults to `hitl_pre_submit` (fill verified fields, upload the clean 1-page PDF, capture a screenshot, and wait for user confirmation before clicking Submit). `yolo_with_guardrails` is strictly opt-in during Phase 0.
- **Cold email (`outreach_policy.mode`)**: Always `hitl_strict`. Requires a verifiable public `Source URL` for every recipient, rejects subjects containing your current employer or `->`, and never sends without explicit chat approval after showing `To`, `Subject`, body, and PDF path.
- **Anti-bot boundary**: Never solves CAPTCHAs, never reads Gmail/email automatically to extract human-verification codes, and stops on shady legal clauses.

## Example prompts

- "Onboard my resume into a private Career Autopilot workspace with India-default preferences and render a baseline 1-page PDF"
- "Scout verified remote and hybrid roles matching my workspace preferences, screen for ATS traps and salary localization, and update new_leads.md"
- "Tailor a grounded 1-page PDF resume for my top queued roles, run pre-submit browser apply prep, and draft cold outreach"
