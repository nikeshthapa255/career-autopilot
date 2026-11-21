---
name: career-autopilot-onboard
description: >-
  Initializes a private career-autopilot job-search workspace, parses a
  candidate resume (PDF, DOCX, Markdown, or plain text) into a canonical
  master_profile.md with a Verified Quantitative Baseline, runs a structured
  preference and safety interview to populate GLOBAL_REFERENCE.md, and renders
  a verified 1-page baseline PDF resume. Use when onboarding a new candidate,
  setting up a private job-application workspace, importing an updated resume,
  or updating target roles, compensation floors, location policies, safety
  modes, or cold-outreach settings.
---

# Career Autopilot Onboarding (Phase 0)

Sets up a candidate's private job-application workspace from an existing resume and a structured preference interview before discovery or applications begin.

> **Plugin vs. Workspace Boundary:** Never store personal resumes, phone numbers, emails, or application state inside the `career-autopilot` plugin folder. Write all candidate data strictly inside `<workspace>/`.

## Quick Assets

- Structured Intake Interview: [intake-question-tree.md](./references/intake-question-tree.md)
- Workspace Initializer Script: [init-workspace.sh](./scripts/init-workspace.sh)
- Shared Resume HTML Template: [resume_template.html](../career-autopilot-apply/resources/resume_template.html)
- Cross-Platform PDF Renderer: [render_resume_pdf.sh](../career-autopilot-apply/scripts/render_resume_pdf.sh)

---

## Step 1: Initialize or Inspect `<workspace>`

1. Ask for or confirm `<workspace>` (a private local directory outside the plugin directory).
2. If `<workspace>` is new or missing templates, run:
   ```bash
   ./scripts/init-workspace.sh "<target-workspace-dir>"
   ```
   (From the plugin install directory, invoke `<plugin-dir>/skills/career-autopilot-onboard/scripts/init-workspace.sh "<target-workspace-dir>"`; it automatically locates the bundled `<plugin-dir>/workspace-template/`.)
3. `init-workspace.sh` scaffolds `.gitignore`, `GLOBAL_REFERENCE.md.template`, `resume/master_profile.md.template`, `applications/tracker.md.template`, and `applications/new_leads.md.template` without overwriting populated user files unless `--force` is passed.
4. For incremental updates inside an existing `<workspace>`, read `<workspace>/resume/master_profile.md` and `<workspace>/GLOBAL_REFERENCE.md` first so prior Q-ID decisions and application history stay intact.

---

## Step 2: Parse Existing Resume (PDF / DOCX / MD / TXT)

Inspect the candidate's source resume using environment-safe tools only (no unapproved Python, Node, or LaTeX runtimes):

- **PDF (`.pdf`):** Read directly via `read_file` to inspect layout, dates, bullets, education, and metrics.
- **DOCX (`.docx`):** Extract XML text with standard POSIX tools (reading both `word/document.xml` and any `word/header*.xml` where contact headers often sit):
  ```bash
  unzip -p "<resume.docx>" "word/header*.xml" "word/document.xml" 2>/dev/null \
    | awk '{
        gsub(/<\/w:p>|<w:br[^>]*>|<w:cr[^>]*>/, "\n")
        gsub(/<w:tab[^>]*>/, " | ")
        gsub(/<[^>]*>/, "")
        gsub(/&amp;/, "\\&")
        gsub(/&lt;/, "<")
        gsub(/&gt;/, ">")
        gsub(/&quot;/, "\"")
        gsub(/&apos;/, "\047")
        print
      }' \
    | awk 'NF'
  ```
- **Markdown or Plaintext (`.md`, `.txt`):** Read directly via `read_file`.

---

## Step 3: Build `master_profile.md` & `Verified Quantitative Baseline`

Synthesize `<workspace>/resume/master_profile.md` from `<workspace>/resume/master_profile.md.template` using **only** facts present in the source resume:

1. **Identity & Links:** `full_name`, `pronouns` (if given), `email`, `phone` (keep `[OMITTED BY POLICY]` or `[TODO: phone]` until confirmed in Step 4), `linkedin`, `github`, `portfolio_or_website`, and header location.
2. **Summary & Experience:** Preserve verbatim employer names, exact job titles, start/end dates, and role type (`full-time` vs `internship` vs `contract`). Group verified bullet achievements cleanly without inventing metrics or inflating scope.
3. **Domain-Agnostic Competency Buckets (`competency_buckets[]`):** Group verified tools, languages, methods, or domain capabilities into role-appropriate categories (engineering, product, design, data, GTM, operations, or research) rather than assuming software-only labels.
4. **Education & Optional Sections:** Record degrees/certifications/institutions/dates verbatim; include optional `Publications`, `Certifications`, `Patents`, or `Leadership` only if verified. Mark missing optional screening items (e.g., GPA, transcript path) as `[TODO: <field>]`.
5. **Mandatory `Verified Quantitative Baseline` Block:**
   - Extract every confirmed numeric claim verbatim (percentages, latencies, scale figures, revenue/ARR, team sizes, customer counts).
   - Compute `actual_full_time_yoe` strictly from non-overlapping full-time employment dates, explicitly listing internships separately so downstream YOE gates never double-count them.
   - Downstream tailoring may reorder or tighten bullets, never invent or extrapolate numbers beyond this baseline.

---

## Step 4: Run the Structured Preference & Safety Interview

Follow [intake-question-tree.md](./references/intake-question-tree.md) (Steps 1–7) using `ask_question`, skipping or pre-confirming values already clear from the resume.

Key defaults and policy rules to capture in `<workspace>/GLOBAL_REFERENCE.md`:

1. **India-First Parameterized Defaults (100% Configurable):**
   - Pre-seed defaults for Indian candidates (`residence_country: India`, `primary_iana: Asia/Kolkata`, `display_label: IST (UTC+5:30)`, `+91` phone formatting guidance, `home_country_authorized: true`, `foreign_visas_held: []`, `standard_foreign_visa_answer: "N/A - I will be working outside the target country (remote from India)"`, INR `LPA` alongside USD/EUR `comp_floor` + `fx_reference_rates` date snapshot, EOR/contractor viability, and APAC / EU / optional US-overlap preferences).
   - Override any field cleanly for candidates in other countries, timezones, currencies, or hybrid/onsite preferences (`work_modes`: `remote`, `hybrid`, `onsite`).
2. **Phone Privacy Policy (`phone_policy`):**
   - Recommend `omit_on_pdf_and_optional_supply_if_req` (omit phone from resume PDFs and optional ATS fields; supply the private E.164 number only when an ATS marks Phone `[REQ]`), while supporting `omit_everywhere` and `always_include`.
3. **Safe Default Execution Policy (`web_apply_mode`):**
   - Default `web_apply_mode` to **`hitl_pre_submit`** (fill form, stage PDF, screenshot, and pause before clicking Submit).
   - Explicitly ask whether the candidate wants to keep `hitl_pre_submit` or opt into **`yolo_with_guardrails`** (auto-submit non-blocked forms and standard non-shady privacy/AI disclosures, while still halting unconditionally on CAPTCHAs, email human-verification codes, login/MFA gates, `[HUMAN AUTHORING REQUIRED]` anti-LLM honesty checks, and shady legal clauses).
4. **Cold Email Strict HITL & Employer Confidentiality (`outreach_policy`):**
   - Keep `outreach_policy.mode: hitl_strict` unconditionally (never auto-send cold emails).
   - Check connected email accounts via `list_plugin_accounts` (`gmail` optional). If connected, set `email_plugin: gmail` and `agy_account`; if absent or if the user prefers Outlook, Proton Mail, or Apple Mail, set `email_plugin: none` (clean Markdown copy-paste dossier fallback).
   - Auto-populate `forbidden_subject_tokens` with `candidate_profile.current_employer` (when non-empty), `"->"`, and any custom confidential terms so current employer names never leak into email subjects.
5. **Decisions Ledger:** Record every confirmed preference in `<workspace>/GLOBAL_REFERENCE.md` Section 4 (`Q1–Q7+`) and ensure `<workspace>/applications/tracker.md` and `<workspace>/applications/new_leads.md` are initialized cleanly.

---

## Step 5: Render & Visually Verify Baseline 1-Page PDF

Before concluding onboarding, verify the rendering pipeline produces a clean 1-page baseline resume:

1. Copy [resume_template.html](../career-autopilot-apply/resources/resume_template.html) to `<workspace>/resume/backup_resume.html` and substitute all `{{...}}` fields from `<workspace>/resume/master_profile.md` (including `data-page-size` set to `a4` or `letter`, and omitting `{{PHONE_SEGMENT}}` per `phone_policy`).
2. Run [render_resume_pdf.sh](../career-autopilot-apply/scripts/render_resume_pdf.sh) (or `render_resume_pdf.ps1` on native Windows PowerShell) with `--strict-1-page`:
   ```bash
   ../career-autopilot-apply/scripts/render_resume_pdf.sh \
     "<workspace>/resume/backup_resume.html" \
     "<workspace>/resume/<Candidate_Slug>_Backup_Resume.pdf" \
     --strict-1-page
   ```
   - Never pass `--allow-todo` for a production baseline. If intentional `[TODO:` fields remain pending user input, render a draft preview with `--allow-todo`, warn the user clearly, and keep production applications blocked until resolved.
3. **Mandatory Visual Check:** Open `<workspace>/resume/<Candidate_Slug>_Backup_Resume.pdf` via `read_file` to verify strictly **1 page** (`Page 1 of 1`), readable margins, zero overlapping/clipped text, and zero leaked `[TODO:` tokens. If it overflows to page 2, tighten phrasing or adjust template CSS spacing variables (`--section-gap`, `--entry-gap`, `--bullet-gap`) and re-verify.

---

## Step 6: Summary & Next Steps

Report the generated workspace files (`GLOBAL_REFERENCE.md`, `resume/master_profile.md`, `resume/<Candidate_Slug>_Backup_Resume.pdf`, `applications/tracker.md`, `applications/new_leads.md`) and tell the user they can now:
- Run **Phase 1 discovery** via `career-autopilot-scout` to populate `applications/new_leads.md` and `applications/tracker.md`.
- Run **Phase 2 applications** via `career-autopilot-apply` (tailored 1-page PDFs, guardrailed website applications, and optional HITL cold email outreach).
- Optionally install daily scheduled automations using the repository's `automations/install-sidecars.sh`.
