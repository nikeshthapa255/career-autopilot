# Career Autopilot Onboarding Guide

> **Audience:** New users setting up `career-autopilot` for the first time across macOS, Linux, or Windows (WSL / Git Bash; native PowerShell is supported for PDF rendering via `render_resume_pdf.ps1`). Defaults start with an **India-first configuration** (`Asia/Kolkata`, `IST`, INR Lakhs Per Annum [LPA] and USD floors, no US work permit assumed, Employer of Record [EOR] and contractor screening), and every preference can be customized for any country, currency, work mode, or role domain during Phase 0. See [README.md](../README.md) for the quickstart overview.

---

## 1. Prerequisites by Operating System

| Platform | Browser / PDF Renderer Requirement | Shell & Archive Tools | Optional Extras |
| :--- | :--- | :--- | :--- |
| **macOS** | Google Chrome (`/Applications/Google Chrome.app`), Chromium, or Microsoft Edge | Built-in `bash`, `awk`, `sed`, `grep`, `unzip`, `git` | `gmail` Antigravity plugin (draft-first cold email); `chrome-devtools` MCP (`--autoConnect` for Mode B login portals) |
| **Linux** | `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser`, `microsoft-edge` on `PATH`, or `/snap/bin/chromium` | `bash`, `awk`, `sed`, `grep`, `unzip`, `git` | `poppler-utils` (`pdfinfo`) for extra PDF page verification |
| **Windows (WSL / Git Bash — Recommended on Windows)** | Linux `chromium` inside WSL **or** Windows host `chrome.exe` / `msedge.exe` (auto-discovered via `/mnt/c/Program Files/...` with `wslpath -w`) | `bash`, `awk`, `sed`, `grep`, `unzip`, `git` (`wslpath` on WSL) | Same as Linux; `render_resume_pdf.ps1` also works directly in native PowerShell |

If Chrome or Chromium lives in a custom path on macOS/Linux/WSL, run `export RESUME_CHROME_BIN="/path/to/chrome"` (or `$env:RESUME_CHROME_BIN="C:\path\to\chrome.exe"` in PowerShell) before rendering.

---

## 2. Install the `career-autopilot` Plugin

Choose **one** of these installation methods (manage enabling/disabling from Antigravity's **Customizations** UI rather than editing Antigravity config files manually):

### Option 1 — Antigravity CLI (`agy`, Recommended)
Install directly from GitHub in one command:

```bash
agy plugin install https://github.com/nikeshthapa255/career-autopilot
```

This installs the plugin into `~/.gemini/config/plugins/career-autopilot` (on macOS/Linux/WSL). Re-run the command to update, or toggle/uninstall it from Antigravity's **Customizations** panel.

### Option 2 — Git-Only Global User Install (No CLI Needed)
Clone the repository directly into your global Antigravity plugins directory under `career-autopilot`:

```bash
git clone https://github.com/nikeshthapa255/career-autopilot ~/.gemini/config/plugins/career-autopilot
```

To pull updates later, run `git -C ~/.gemini/config/plugins/career-autopilot pull`. Check first that `~/.gemini/config/plugins/` does not already contain another `career-autopilot` directory (plugin `name` collisions silently drop the second discovered plugin).

### Option 3 — Workspace Project Registration (`.agents/plugins.json`)
To load the plugin only inside a specific repository or workspace without installing it globally, clone it into a directory named `career-autopilot/` and create `<project-root>/.agents/plugins.json` pointing to its parent directory (`.agents/plugins.json` scans each `entries[].path` one level deep; see [antigravity-plugin-and-sidecar-spec.md](./antigravity-plugin-and-sidecar-spec.md)):

```json
{
  "entries": [
    {
      "path": "~/path/to/plugins-parent-dir",
      "include_only": ["career-autopilot"]
    }
  ]
}
```

### Verify Active Plugin in Antigravity
Start a new Antigravity session, open **Customizations** in the sidebar (or open `customization://career-autopilot`), and verify **Career Autopilot** is enabled. To use the live side-pane dashboard, enable the `career-autopilot/dashboard` sidecar in **Extensions / Customizations** and open `sidecar://career-autopilot/dashboard/`.

---

## 3. Initialize Your Private Job-Search Workspace

Keep personal resumes, phone numbers, and company targets **outside** the `career-autopilot` plugin directory. You can either open an empty folder (such as `~/career-workspace`) in Antigravity and let `career-autopilot-onboard` scaffold it automatically, or run the initializer script directly (replace `<plugin-dir>` if you used Option 3):

```bash
~/.gemini/config/plugins/career-autopilot/skills/career-autopilot-onboard/scripts/init-workspace.sh ~/career-workspace
```

What this scaffolds from `workspace-template/`:
- `.gitignore` — ignores `resume/*.pdf`, `resume/master_profile.md`, `GLOBAL_REFERENCE.md`, `applications/`, `*.local.*`, and `scratch/` (if you choose to track your private workspace in Git).
- `GLOBAL_REFERENCE.md.template` — copied to `GLOBAL_REFERENCE.md` for your preferences, safety rules, and `Q-ID` Decisions Ledger (reusable answers to recurring ATS questions).
- `resume/master_profile.md.template` — copied to `resume/master_profile.md` for your canonical experience and `Verified Quantitative Baseline`.
- `applications/tracker.md.template` and `applications/new_leads.md.template` — copied to `applications/tracker.md` and `applications/new_leads.md`.
- `requirements/README.md.template` — optional starter template used by `career-autopilot-fit`.

Existing populated workspace files are never overwritten unless you pass `--force`.

---

## 4. Run Phase 0 Onboarding (`career-autopilot-onboard`)

Open Antigravity inside your private workspace (`~/career-workspace`), attach your existing resume (`.pdf`, `.docx`, or `.md`/`.txt`) in chat or paste its file path, and ask the agent to run `career-autopilot-onboard`.

### Step 4.1 Resume Intake & Quantitative Baseline Lock
- **PDF:** Inspected directly by Antigravity.
- **DOCX:** Extracted via standard POSIX `unzip -p <file.docx> word/document.xml` + tag stripping (zero external Python/Node dependencies required).
- **Markdown / Text:** Read directly from disk.

The skill populates `resume/master_profile.md` with your exact employers, titles, dates, education, `competency_buckets[]` (for engineering, product, design, data, GTM, or ops tracks), and a locked **`Verified Quantitative Baseline`** section. Downstream resume tailoring cannot invent numbers or alter dates outside this file.

### Step 4.2 Preference & Safety Interview
The onboarding interview resolves key policy decisions up front so Phase 1 and Phase 2 never stall mid-run:

1. **Identity & Phone Policy:** Confirms full name, optional pronouns, filename slug (`First_Last`), email, links, and `current_employer`. Recommended default: `omit_on_pdf_and_optional_supply_if_req` (keeps `+91` / E.164 phone numbers off tailored PDFs and optional inputs, supplying your number only when an ATS form marks Phone `[REQ]`).
2. **Location, Timezone & Work Authorization (India-First Defaults):**
   - Defaults to `India`, `IST (UTC+5:30)`, `Asia/Kolkata`, `N/A - I will be working outside the United States` on foreign visa prompts, and `"First preference is always the remote role."` on relocation questions.
   - Resume header uses `India (IST / UTC+5:30)` (or your country/timezone) while ATS city inputs receive `<City>, India` (e.g., `Bengaluru, India`, `Hyderabad, India`, `Pune, India`).
   - Non-Indian candidates can set any country, `CRON_TZ` IANA zone, visa status, and `work_modes` (`remote`, `hybrid`, `onsite`).
3. **Compensation Floor & EOR Screening:**
   - Set an explicit floor in `INR` (LPA/annual), `USD`, `EUR`, or `GBP`, plus an explicit `fx_reference_rates` snapshot date for cross-currency checks.
   - Choose how to handle `"location-adjusted"` or `"local EOR"` pay disclaimers (`tier_b2_warn` recommended so suspicious downward localization is flagged before applying).
4. **Web Apply Safety Mode (`hitl_pre_submit` Default vs. Opt-In YOLO):**
   - **`hitl_pre_submit` (Default):** Fills all mapped fields, stages and attaches the clean 1-page PDF, takes a pre-submit screenshot, and pauses so you inspect and click **Submit**.
   - **`yolo_with_guardrails` (Explicit Opt-In):** Choose this in Phase 0 if you want the browser step to accept standard non-shady recruiting privacy/AI-disclosure checkboxes and click **Submit** automatically on clean forms. Even in YOLO mode, the plugin **always stops** on CAPTCHAs, email human-verification security codes, login/MFA screens, anti-LLM honesty declarations (`[HUMAN AUTHORING REQUIRED]`), and shady legal clauses (broad non-competes, off-hours IP assignment, invasive monitoring).
5. **Cold Outreach & Email Plugin Fallback:**
   - **Gmail Connected:** The agent checks connected Antigravity Gmail accounts (`list_plugin_accounts`) and records your chosen account (`AGY_ACCOUNT`) in `GLOBAL_REFERENCE.md`. Cold email remains **strict human-in-the-loop (HITL)** (`create-draft` only; never sent without explicit chat approval showing exact `To` and `Subject`).
   - **No Gmail Plugin (`email_plugin: none`):** If you use Outlook, Proton, or Apple Mail, choose `none` so cold outreach writes ready-to-paste `cold_email.md` dossiers instead of calling `gmail`.
   - **Subject Confidentiality Guard:** Automatically adds `current_employer` and `->` to `forbidden_subject_tokens` so subject lines follow `Job Application: <Exact Role Title> — <Candidate Name>` without leaking your employer.
6. **Page Size & Baseline PDF Verification:**
   - Pick `a4` (`210mm x 297mm`, default in India/EU/APAC) or `letter` (`8.5in x 11in`, common for US applications).
   - Phase 0 renders your baseline `Backup_Resume.pdf` via `<plugin-dir>/skills/career-autopilot-apply/scripts/render_resume_pdf.sh` (or `render_resume_pdf.ps1` on PowerShell) and visually verifies 1-page output.

---

## 5. Run Phase 1 (`career-autopilot-scout`), Optional Fit Map (`career-autopilot-fit`), & Phase 2 (`career-autopilot-apply`)

1. **Discover & Screen Jobs (`career-autopilot-scout`):**
   - Searches Ashby, Greenhouse, Lever, YC Jobs / YC Work at a Startup (WaaS), HN Who is Hiring, Notion/Breezy, and custom portals (`Mode A` public page inspection or `Mode B` authenticated Chrome `--autoConnect`).
   - Deduplicates against `applications/tracker.md` and `applications/new_leads.md`, applies YOE, FX/comp, hidden-region, timezone-shift (`max_overlap_shift_hours`), anti-LLM, honeypot, and prompt-injection gates, and tiers passing roles (`Tier A`, `Tier B1`, `Tier B2`).
2. **Optional Fit Rubric & Interview Prep (`career-autopilot-fit`):**
   - Builds `requirements/README.md` and per-track guides with a Mermaid mind-map, dual-track fit rubric (`>= 80%` verified match or wanted specialty track), and prioritized interview prep queue.
3. **Tailor, Apply & Draft Outreach (`career-autopilot-apply`):**
   - Spawns isolated per-company workers (up to 32) to tailor strict 1-page PDFs (`Workflow 1`), inspect live ATS forms and traps (`Workflow 2`), and research verified public contacts (`Workflow 3`).
   - The root coordinator executes browser uploads serially, respects `hitl_pre_submit` or opt-in `yolo_with_guardrails`, and prepares HITL cold-email drafts or copy-paste dossiers.

### Optional: Configure Scheduled Automations (UI or CLI)
After onboarding, open the **Career Autopilot** side-pane in Antigravity (`sidecar://career-autopilot/dashboard/`), go to the **Automations** tab, choose your schedules and timezone, and click **Save Sidecar Configs**.

Or run the CLI installer from any directory (pass `--no-gmail` if you do not use the Gmail plugin; see [automations/README.md](../automations/README.md) for all flags):

```bash
~/.gemini/config/plugins/career-autopilot/automations/install-sidecars.sh \
  --workspace ~/career-workspace \
  --tz Asia/Kolkata \
  --scout-cron "0 8 * * *" \
  --apply-cron "0 9 * * *"
```

Review the generated configs, then enable them manually inside Antigravity's **Automations** panel (`sidecar://dashboard`). Scheduled runs never hold `gmail mutate send*` permissions (`AGY_UNATTENDED` blocks outbound sends at the hook layer).

---

## 6. Troubleshooting

- **`Google Chrome executable not found`:** Install Chrome/Chromium/Edge or set `export RESUME_CHROME_BIN="/abs/path/to/chrome"` (PowerShell: `$env:RESUME_CHROME_BIN="C:\path\to\chrome.exe"`). On WSL, verify Windows host `chrome.exe` is accessible under `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe` or install `chromium` inside WSL.
- **Manual PDF renderer syntax:** `~/.gemini/config/plugins/career-autopilot/skills/career-autopilot-apply/scripts/render_resume_pdf.sh input.html output.pdf --strict-1-page` (or `render_resume_pdf.ps1` on PowerShell).
- **Renderer exits with code `2`:** Unresolved `[TODO:` or `[USER INPUT NEEDED` markers remain in the HTML file. Replace them before final PDF generation (only pass `--allow-todo` for human draft previews).
- **Renderer exits with code `5` (`--strict-1-page`):** Your tailored HTML spilled onto page 2. Tighten verbose bullet phrasing in `resume_tailored.html` first, then adjust `--section-gap` / `--entry-gap` CSS variables slightly while keeping `--body-size >= 8.8pt`.
- **Browser upload permission timeout:** Keep browser upload turns in the main chat session so the upload permission prompt is visible, or attach `applications/<slug>/<Candidate>_Resume.pdf` manually in the open browser tab.
- **Paused browser tab overwritten:** Finish any open tab paused on a CAPTCHA or email verification code before starting another browser apply, or ask the agent to open a fresh tab.
- **Login-gated portals (YC WaaS, LinkedIn, Workday accounts):** Install the `chrome-devtools` MCP plugin and launch Chrome with `--autoConnect` (**Mode B**) while signed into your normal Chrome profile so the agent never asks for passwords or 2FA tokens.
- **Gmail CLI authentication or unattended send block:** Check connected accounts in Antigravity's Plugins Manager (`gmail` plugin card) and keep scheduled automations strictly on `create-draft` / `update-draft` (`AGY_UNATTENDED` intentionally blocks automated sends).
