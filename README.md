# Career Autopilot

Career Autopilot is an Antigravity plugin and automation kit for running a structured job search. It parses your existing resume into a canonical profile, scouts and screens job boards, tailors 1-page PDF resumes, fills web application forms in a browser, and drafts cold outreach emails for your approval.

All personal data stays outside this repository. Your resume, preferences, phone number, and application history live in a separate private workspace protected by `.gitignore`.

The default settings target candidates based in India (`Asia/Kolkata`, `IST / UTC+5:30`, INR/USD/EUR compensation floors, remote EOR and contractor checks, `+91` phone handling, and `A4` or `Letter` PDFs). You can change country, timezone, currency, work mode (`remote`, `hybrid`, `onsite`), and job domain during onboarding.

## Requirements

- [Antigravity](https://antigravity.google/docs) with plugin support
- Google Chrome, Chromium, or Microsoft Edge (used in headless mode to render 1-page PDFs)
- Standard POSIX shell tools on macOS, Linux, or WSL (`bash`, `awk`, `sed`, `grep`, `unzip`), or PowerShell on Windows
- Optional: the Antigravity Gmail plugin for creating email drafts (without it, outreach saves as copy-paste Markdown files)

## How it works

The plugin splits the job search into three phases, backed by an editing skill (`clear-natural-english`) that keeps summaries, essays, and emails plain and free of AI filler:

1. **Onboard (`career-autopilot-onboard`):** Extracts facts, dates, and verified metrics from your `.pdf`, `.docx`, or `.md` resume into `resume/master_profile.md`, interviews you to populate `GLOBAL_REFERENCE.md`, and renders a 1-page baseline PDF.
2. **Scout (`career-autopilot-scout`):** Searches Ashby, Greenhouse, Lever, YC Jobs, Hacker News Who is Hiring, Notion, Breezy, and custom portals (`Mode A` public DOM inspection or `Mode B` authenticated Chrome `--autoConnect`). Deduplicates against your tracker, checks compensation and years-of-experience fit, flags location-adjusted pay, and tiers leads into `applications/new_leads.md` and `applications/tracker.md`.
3. **Fit rubric and prep map (`career-autopilot-fit`, optional):** Generates `requirements/README.md` and per-track guides with a Mermaid mind-map, dual-track eligibility gate (`>= 80%` verified skill match or wanted specialty track), instant-skip mismatch filters, and a focused interview prep queue. When present, `career-autopilot-scout` and `career-autopilot-apply` enforce its triage gate before queuing or tailoring.
4. **Apply (`career-autopilot-apply`):** Fans out up to 32 isolated workers (one per company folder) to tailor 1-page resumes and map form fields, runs serialized browser file uploads from the root coordinator, and prepares cold-email drafts when a public contact email is verified.

## Safety rules

- **Pre-submit pause by default:** Web applications run in `hitl_pre_submit` mode out of the box. The agent fills mapped fields, attaches a `[TODO:`-free 1-page PDF, takes a screenshot, and stops before clicking Submit. You can opt into `yolo_with_guardrails` during onboarding.
- **Hard stops on human gates:** Even in `yolo_with_guardrails` mode, the agent stops immediately on CAPTCHAs, email human-verification codes (it never reads your inbox to bypass human checks), login or MFA walls, anti-LLM authorship checks, and unusual legal terms (broad non-competes, outside-work IP assignment, or device surveillance).
- **Prompt-injection and honeypot defense:** Job descriptions and form labels are treated as untrusted text. Hidden off-screen inputs are left blank, and embedded prompt-injection tokens are stripped.
- **No automatic emails:** Cold outreach never guesses email addresses and never sends without your explicit approval in chat after showing the exact recipient, subject, body, and PDF path. Scheduled runs are blocked from sending email at both the permission and hook layers.
- **Grounded facts only:** Resumes, form answers, and emails draw only from `resume/master_profile.md` and its locked quantitative baseline. The PDF renderer exits with an error if any `[TODO:` or `[USER INPUT NEEDED` placeholder remains.

## Quickstart

### 1. Install the plugin

Copy `plugin/` into your global Antigravity plugins directory, along with `workspace-template/` so workspace setup works from any folder:

```bash
mkdir -p ~/.gemini/config/plugins
cp -R ./plugin ~/.gemini/config/plugins/career-autopilot
mkdir -p ~/.gemini/config/plugins/career-autopilot/skills/career-autopilot-onboard/resources
cp -R ./workspace-template ~/.gemini/config/plugins/career-autopilot/skills/career-autopilot-onboard/resources/workspace-template
```

To manage or toggle the plugin later, open **Customizations** in Antigravity (`customization://career-autopilot`). For project-scoped installation via `.agents/plugins.json`, see [plugin/README.md](plugin/README.md).

### 2. Create a private workspace

Keep your resume and application records outside this repository:

```bash
./plugin/skills/career-autopilot-onboard/scripts/init-workspace.sh ~/career-workspace
```

### 3. Run onboarding

Open `~/career-workspace` in Antigravity, share your current resume (`.pdf`, `.docx`, or `.md`), and ask the agent to run `career-autopilot-onboard`. It creates `resume/master_profile.md`, fills out `GLOBAL_REFERENCE.md` through a short interview, and verifies your 1-page baseline PDF.

### 4. Scout matching roles

Ask Antigravity to run `career-autopilot-scout`. Verified leads land in `applications/new_leads.md` and `applications/tracker.md`.

### 5. Tailor and apply

Ask Antigravity to run `career-autopilot-apply` on your queued roles. Each target gets its own folder under `applications/<company-slug>/` holding the tailored HTML, 1-page PDF, form state log, and optional email draft.

## Scheduled automations

To run discovery and application prep on a daily cron schedule, generate the Antigravity sidecar configs:

```bash
./automations/install-sidecars.sh --workspace ~/career-workspace --tz Asia/Kolkata
```

The installer prefixes sidecar IDs and dashboard names with your first name (`<firstname>-find-jobs` and `<firstname>-auto-apply`, resolved from `--first-name`, `GLOBAL_REFERENCE.md`, `git config user.name`, or your OS user, and overridable with `--prefix`). Automations install disabled by default. Review them and turn them on manually from the Antigravity Automations dashboard (`sidecar://dashboard`).

See [automations/README.md](automations/README.md) for custom schedules, Gmail vs. copy-paste email flags, and `--dry-run` previews.

## Repository layout

| Path | Contents |
| :--- | :--- |
| [plugin/](plugin/README.md) | Distributable Antigravity plugin (`plugin.json`, root `hooks.json`, `rules/AGENTS.md`, `agents/`, live UI Extension `sidecars/dashboard/`, and 5 skills: `career-autopilot-onboard`, `career-autopilot-scout`, `career-autopilot-fit` [optional], `career-autopilot-apply`, `clear-natural-english`) |
| [workspace-template/](workspace-template/GLOBAL_REFERENCE.md.template) | Starter files for a private candidate workspace (`.gitignore`, `GLOBAL_REFERENCE.md.template`, `master_profile.md.template`, `tracker.md.template`, `new_leads.md.template`, optional `requirements/README.md.template`) |
| [automations/](automations/README.md) | Parameterized scheduled sidecar templates (`find-new-jobs`, `auto-apply`) and `install-sidecars.sh` |
| [docs/](docs/framework-architecture.md) | Architecture and platform guides: [framework architecture](docs/framework-architecture.md), [plugin and sidecar spec](docs/antigravity-plugin-and-sidecar-spec.md), [browser architecture](docs/browser-extension-architecture.md), and [onboarding guide](docs/onboarding-guide.md) |
| [tests/](tests/test_zero_pii_scan.sh) | Zero-PII scanner, PDF renderer gate tests, JSON validators, and synthetic HTML fixtures |

## Verification tests

Run both test scripts from the repository root:

```bash
./tests/test_zero_pii_scan.sh
./tests/test_render_resume_pdf.sh
```

For macOS, Linux, WSL, and Windows Chrome setup and troubleshooting, see [docs/onboarding-guide.md](docs/onboarding-guide.md).
