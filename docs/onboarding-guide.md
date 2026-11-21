# Career Autopilot Onboarding Guide

> **Audience:** New users setting up `career-autopilot` for the first time across macOS, Linux, WSL, or native Windows. Defaults start with an **India-first configuration** (`Asia/Kolkata`, `IST`, INR/USD floors, no US work permit assumed, EOR/contractor screening), and every preference can be customized for any country, currency, work mode, or role domain during Phase 0.

---

## 1. Prerequisites by Operating System

| Platform | Browser / PDF Renderer Requirement | Archive & Shell Tools | Optional Extras |
| :--- | :--- | :--- | :--- |
| **macOS** | Google Chrome (`/Applications/Google Chrome.app`), Chromium, or Microsoft Edge | Built-in `bash`, `unzip`, `awk`, `perl` | `gmail` Antigravity plugin (for draft-first cold email); `chrome-devtools` MCP (for Mode B login portals) |
| **Linux** | `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser`, `microsoft-edge` on `PATH`, or `/snap/bin/chromium` | `bash`, `unzip`, `awk` | `poppler-utils` (`pdfinfo`) for extra PDF page verification |
| **WSL (Windows Subsystem for Linux)** | Either Linux `chromium` inside WSL **or** Windows host `chrome.exe` / `msedge.exe` (auto-discovered via `/mnt/c/Program Files/...` with `wslpath -w`) | `bash`, `unzip`, `awk`, `wslpath` | Same as Linux |
| **Native Windows (PowerShell)** | Google Chrome or Microsoft Edge (`chrome.exe` / `msedge.exe`) | PowerShell (`render_resume_pdf.ps1`) or Git Bash (`render_resume_pdf.sh`) | `gmail` plugin + `chrome-devtools` MCP |

If Chrome or Chromium lives in a custom path on any platform, export `RESUME_CHROME_BIN="/path/to/chrome"` before running the renderer.

---

## 2. Install the `career-autopilot` Plugin

Choose **one** of these installation methods (do **not** hand-edit `~/.gemini/config/config.json`):

### Option A — Global User Install (Recommended for Personal Job Searches)
Copy `plugin/` into your global Antigravity plugins directory under `career-autopilot`:

```bash
mkdir -p ~/.gemini/config/plugins
cp -R ./plugin ~/.gemini/config/plugins/career-autopilot
```

Check first that `~/.gemini/config/plugins/` does not already contain another `career-autopilot` directory (plugin `name` collisions silently drop the second discovered plugin).

### Option B — Workspace Project Registration (`.agents/plugins.json`)
To load the plugin only inside a specific repository or workspace without copying it globally, create `<project-root>/.agents/plugins.json` pointing to the directory that **contains** your plugin directory (`.agents/plugins.json` scans each `entries[].path` one level deep, so put `career-autopilot/` inside a parent folder or rename/symlink `plugin` to `career-autopilot`):

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
Start a new session and verify `[Career Autopilot](customization://career-autopilot)` appears enabled in the Customizations panel (never emit `plugin://` links, and always keep the link target equal to the install directory name).

---

## 3. Initialize Your Private Job-Search Workspace

Keep personal resumes, phone numbers, and company targets **outside** the `career-autopilot` plugin repository. Run the workspace initializer into a dedicated private folder:

```bash
./plugin/skills/career-autopilot-onboard/scripts/init-workspace.sh ~/career-workspace
```

What this scaffolds from `workspace-template/`:
- `.gitignore` — ignores `resume/*.pdf`, `resume/master_profile.md`, `GLOBAL_REFERENCE.md`, `applications/`, `*.local.*`, and `scratch/` so personal PII cannot be committed accidentally.
- `GLOBAL_REFERENCE.md.template` — copied to `GLOBAL_REFERENCE.md` for your preferences, safety rules, and `Q-ID` Decisions Ledger.
- `resume/master_profile.md.template` — copied to `resume/master_profile.md` for your canonical experience and `Verified Quantitative Baseline`.
- `applications/tracker.md.template` and `applications/new_leads.md.template` — copied to `applications/tracker.md` and `applications/new_leads.md`.

Existing populated workspace files are never overwritten unless you pass `--force`.

---

## 4. Run Phase 0 Onboarding (`career-autopilot-onboard`)

Open Antigravity inside your private workspace (`~/career-workspace`) and provide your existing resume (`.pdf`, `.docx`, or `.md`/`.txt`), then ask the agent to run `career-autopilot-onboard`.

### Step 4.1 Resume Intake & Quantitative Baseline Lock
- **PDF:** Parsed directly via Antigravity `read_file`.
- **DOCX:** Extracted via standard POSIX `unzip -p <file.docx> word/document.xml` + tag stripping (zero external Python/Node dependencies required).
- **Markdown / Text:** Read directly via `read_file`.

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
   - **Gmail Connected:** Run `list_plugin_accounts` and select your `AGY_ACCOUNT`. Cold email remains **strict HITL** (`create-draft` only; never sent without explicit chat approval showing exact `To` and `Subject`).
   - **No Gmail Plugin (`email_plugin: none`):** If you use Outlook, Proton, or Apple Mail, choose `none` so Workflow 3 writes ready-to-paste `cold_email.md` dossiers instead of calling `gmail`.
   - **Subject Confidentiality Guard:** Automatically adds `current_employer` and `->` to `forbidden_subject_tokens` so subject lines follow `Job Application: <Exact Role Title> — <Candidate Name>` without leaking your employer.
6. **Page Size & Baseline PDF Verification:**
   - Pick `a4` (`210mm x 297mm`, default in India/EU/APAC) or `letter` (`8.5in x 11in`, common for US applications).
   - Phase 0 renders your baseline `Backup_Resume.pdf` via `render_resume_pdf.sh` (or `.ps1` on Windows) and inspects it with `read_file` to confirm crisp 1-page output.

---

## 5. Run Phase 1 (`career-autopilot-scout`) & Phase 2 (`career-autopilot-apply`)

1. **Discover & Screen Jobs (`career-autopilot-scout`):**
   - Searches Ashby, Greenhouse, Lever, YC Jobs / WaaS, HN Who is Hiring, Notion/Breezy, and generic Mode A/B portals.
   - Deduplicates against `applications/tracker.md` and `applications/new_leads.md`, applies YOE, FX/comp, hidden-region, anti-LLM, honeypot, and prompt-injection gates, and tiers passing roles (`Tier A`, `Tier B1`, `Tier B2`).
2. **Tailor, Apply & Draft Outreach (`career-autopilot-apply`):**
   - Spawns isolated per-slug workers (up to 32) to tailor strict 1-page PDFs (`Workflow 1`), inspect live ATS forms and traps (`Workflow 2`), and research verified public contacts (`Workflow 3`).
   - Root coordinator executes browser uploads serially (`browser_sandbox/uploads/`), respects `hitl_pre_submit` or opt-in `yolo_with_guardrails`, and prepares HITL cold-email drafts/dossiers.

### Optional: Install Scheduled Sidecars (`automations/install-sidecars.sh`)
```bash
./automations/install-sidecars.sh \
  --workspace ~/career-workspace \
  --tz Asia/Kolkata \
  --scout-cron "0 8 * * *" \
  --apply-cron "0 9 * * *"
```
Review the generated files, then enable them manually inside Antigravity via `[Open Automations Dashboard](sidecar://dashboard)`. Scheduled runs never modify `user_config.json` and never hold `gmail mutate send*` permissions (`AGY_UNATTENDED` blocks sends at the CLI layer).

---

## 6. Troubleshooting

- **`Google Chrome executable not found`:** Install Chrome/Chromium/Edge or set `export RESUME_CHROME_BIN="/abs/path/to/chrome"`. On WSL, verify Windows host `chrome.exe` is accessible under `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe` or install `chromium` inside WSL.
- **Renderer exits with code `2`:** Unresolved `[TODO:` or `[USER INPUT NEEDED` markers remain in the HTML file. Replace them before final PDF generation (only pass `--allow-todo` for human draft previews).
- **Renderer exits with code `5` (`--strict-1-page`):** Your tailored HTML spilled onto page 2. Tighten verbose bullet phrasing in `resume_tailored.html` first, then adjust `--section-gap` / `--entry-gap` CSS variables slightly while keeping `--body-size >= 8.8pt`.
- **`UPLOAD_NEEDS_PERMISSION` 60-second timeout:** Ensure browser upload steps run from the root conversation (not deep inside nested subagents) so the permission prompt is visible in the main UI. If it times out, attach the exact `applications/<slug>/<Candidate>_Resume.pdf` manually in the open tab or re-run the upload turn.
- **Paused tab overwritten or reset to `about:blank`:** Wait for a paused tab awaiting a CAPTCHA or 8-char email security code to finish before launching another `browser` turn, or force `newPage()` isolation. When resuming an idle tab, verify the target URL and re-stage the PDF into root `browser_sandbox/uploads/`.
- **Login-gated portals (YC WaaS, LinkedIn, Workday accounts):** Use **Mode B** (`chrome-devtools` MCP `--autoConnect`) while signed into your normal Chrome profile so the agent never asks for passwords or 2FA tokens.
- **Gmail CLI `needs authentication` or `AGY_UNATTENDED` error:** Run `list_plugin_accounts`, sign in via the Gmail plugin card if prompted, and keep scheduled sidecars strictly on `create-draft` / `update-draft`.
