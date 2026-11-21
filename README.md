# Career Autopilot (`career-autopilot`)

A zero-PII, distributable **Antigravity plugin**, **private workspace template**, and **scheduled automation kit** for end-to-end job discovery, grounded 1-page resume tailoring, guardrailed ATS applications, and HITL cold outreach.

Designed with **India-first configurable defaults** (`Asia/Kolkata`, `IST / UTC+5:30`, INR/USD/EUR compensation floors, remote EOR/contractor screening, `+91` required-only phone handling, `A4`/`Letter` PDFs) and adaptable to any country, timezone, currency, work mode (`remote`, `hybrid`, `onsite`), or role domain.

---

## Key Capabilities & Safety Defaults

- **Zero PII in Repo / Plugin:** Candidate profiles, phone numbers, links, and application logs live exclusively in your separate private workspace (protected by `.gitignore`), never inside the shared plugin.
- **Safe `hitl_pre_submit` Default:** Web applications fill mapped fields, attach a verified `[TODO:`-free 1-page PDF, capture a screenshot, and pause before **Submit** unless you explicitly opt into `yolo_with_guardrails` during Phase 0 onboarding.
- **Strict Anti-Bot & Honesty Guardrails:** Unconditionally stops on CAPTCHAs, email human-verification security codes (never auto-reads email to bypass human checks), login/MFA walls, anti-LLM honesty declarations, shady legal clauses, hidden DOM honeypots, and indirect prompt injections.
- **Cold Email (`Workflow 3`) = Strict HITL:** Zero email guessing; drafts via `gmail` CLI (`AGY_ACCOUNT`, `--to ""` hold support, `AGY_UNATTENDED` send-block) or outputs clean Markdown dossiers if you use another mail client.
- **Battle-Tested ATS + Generic Portal Coverage:** Structured intake for Ashby, Greenhouse, Lever, YC Jobs / WaaS, HN Who is Hiring, Notion, and Breezy, plus adaptive live DOM inspection (`Mode A`) and authenticated Chrome `--autoConnect` (`Mode B`) for arbitrary portals.

---

## Repository Structure

- [plugin/](plugin/README.md) — Distributable `career-autopilot` Antigravity plugin (`plugin.json`, root `hooks.json`, `rules/AGENTS.md`, `agents/`, and skills `career-autopilot-onboard`, `career-autopilot-scout`, `career-autopilot-apply`, `clear-natural-english`).
- [workspace-template/](workspace-template/GLOBAL_REFERENCE.md.template) — Zero-PII workspace scaffold (`GLOBAL_REFERENCE.md.template`, `master_profile.md.template`, `tracker.md.template`, `new_leads.md.template`, `.gitignore`).
- [automations/](automations/README.md) — Parameterized `CRON_TZ=Asia/Kolkata` scheduled sidecars (`find-new-jobs`, `auto-apply`) and `install-sidecars.sh`.
- [docs/](docs/framework-architecture.md) — Full technical documentation:
  - [framework-architecture.md](docs/framework-architecture.md)
  - [antigravity-plugin-and-sidecar-spec.md](docs/antigravity-plugin-and-sidecar-spec.md)
  - [browser-extension-architecture.md](docs/browser-extension-architecture.md)
  - [onboarding-guide.md](docs/onboarding-guide.md)
- [tests/](tests/test_zero_pii_scan.sh) — Automated zero-PII scanner, PDF renderer gate tests, and synthetic HTML fixtures.

---

## 5-Step Quickstart

### 1. Install the Plugin
Copy `plugin/` into your global Antigravity plugins folder (recommended) or reference its parent via `.agents/plugins.json`:

```bash
mkdir -p ~/.gemini/config/plugins
cp -R ./plugin ~/.gemini/config/plugins/career-autopilot
```

### 2. Initialize a Private Candidate Workspace
Keep your personal resume and targets outside the plugin repo:

```bash
./plugin/skills/career-autopilot-onboard/scripts/init-workspace.sh ~/career-workspace
```

### 3. Run Phase 0 Onboarding (`career-autopilot-onboard`)
Open `~/career-workspace` in Antigravity, share your existing resume (`.pdf`, `.docx`, or `.md`), and run `career-autopilot-onboard` to extract `resume/master_profile.md`, configure `GLOBAL_REFERENCE.md` (including `hitl_pre_submit` vs opt-in `yolo_with_guardrails`), and verify your 1-page baseline PDF.

### 4. Run Phase 1 Discovery (`career-autopilot-scout`)
Ask Antigravity to run `career-autopilot-scout` to fetch, deduplicate, screen against traps/comp/YOE/region gates, and tier leads into `applications/new_leads.md` and `applications/tracker.md`.

### 5. Run Phase 2 Applications (`career-autopilot-apply`) & Optional Sidecars
Ask Antigravity to run `career-autopilot-apply` to fan out isolated workers (up to 32), render strict 1-page PDFs, run serialized browser applies, and stage HITL cold-email drafts. To schedule daily runs:

```bash
./automations/install-sidecars.sh --workspace ~/career-workspace --tz Asia/Kolkata
```

Then enable the generated automations manually from the Antigravity UI via `[Open Automations Dashboard](sidecar://dashboard)`.

---

## Running Verification Tests

```bash
./tests/test_zero_pii_scan.sh
./tests/test_render_resume_pdf.sh
```

See [docs/onboarding-guide.md](docs/onboarding-guide.md) for OS-specific Chrome/WSL setup and troubleshooting.
