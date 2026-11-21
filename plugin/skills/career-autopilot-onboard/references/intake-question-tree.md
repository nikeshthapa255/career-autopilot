# Phase 0 Intake Question Tree

Use this 7-step `ask_question` flow after parsing the candidate's resume into `<workspace>/resume/master_profile.md`.

Rules for running the interview:
1. Pre-fill every answer already stated in the parsed resume or the user's prompt. Present extracted values for confirmation rather than asking the user to retype them.
2. Put the recommended default first with `(Recommended)` in `ask_question` options.
3. Ask for free-text values (such as custom city, E.164 phone number, or custom compensation amount) in plain text only when not already extracted or supplied via an option.
4. Map every confirmed decision into `<workspace>/GLOBAL_REFERENCE.md` and log resolved policies in Section 4 (`Questions & Decisions Ledger`).

---

## Step 1: Identity, Links & Resume Page Geometry

**Goal:** Confirm extracted identity fields, compute true full-time YOE, collect missing links, and choose page geometry (`A4` vs `Letter`).

**Pre-Fill Summary to Show User Before Asking:**
- `full_name`, `resume_filename_slug` (`<First_Last>`), `email`
- `current_employer` (from most recent active role, or `None`)
- `actual_full_time_yoe` (computed strictly from non-overlapping full-time employment dates; internships listed separately and never double-counted)
- Extracted links (`linkedin`, `github`, `portfolio_or_website`) and education (`gpa` / `transcript_pdf_path` if present, else `[TODO: gpa]` / `[TODO: transcript_pdf]`)

**`ask_question` Call:**
- **Question 1 (`resume_page_size`):** `Which PDF page size should baseline and tailored resumes use?`
  - `A4 (210mm x 297mm) — standard in India, APAC, and Europe (Recommended)` -> `a4`
  - `US Letter (8.5in x 11in) — standard in the US and Canada` -> `letter`
- **Question 2 (`pronouns`):** `Should pronouns appear in your resume header?`
  - `Omit pronouns from the resume header (Recommended)` -> `omit`
  - `Include he/him` -> `he/him`
  - `Include she/her` -> `she/her`
  - `Include they/them` -> `they/them`

**Follow-up text (only if missing from resume):** Ask for `LinkedIn URL`, `GitHub / Portfolio URL` (if relevant to the target track), and whether `current_employer` and computed `actual_full_time_yoe` look accurate.

**Writes To:** `candidate_profile.*` and `execution_and_safety_policy.resume_page_size` in `<workspace>/GLOBAL_REFERENCE.md`.

---

## Step 2: Phone Privacy & ATS Supply Policy

**Goal:** Prevent unintended phone leaks on PDFs while avoiding mid-run pauses when an ATS marks Phone `[REQ]`.

**`ask_question` Call:**
- **Question 1 (`phone_policy`):** `How should phone numbers be handled on resume PDFs and ATS forms?`
  - `Omit on resume PDFs & optional ATS fields; supply only when an ATS marks Phone [REQ] (Recommended)` -> `omit_on_pdf_and_optional_supply_if_req`
  - `Omit everywhere (pause for manual entry if an ATS requires a phone number)` -> `omit_everywhere`
  - `Include on all resume PDFs and ATS application forms` -> `always_include`

**Conditional Follow-up:**
- If option 1 or 3 is selected and no valid E.164 number was parsed from the resume, ask once in plain text for the phone number in E.164 format (for Indian candidates, remind them to include `+91`, e.g., `+91 XXXXXXXXXX`).
- Store the value strictly inside private `<workspace>/GLOBAL_REFERENCE.md` (`candidate_profile.phone.value`). Never copy it into plugin files.
- If `omit_on_pdf_and_optional_supply_if_req` or `omit_everywhere` is chosen, remove the phone slot or omit it cleanly in `<workspace>/resume/backup_resume.html` so production renders have zero `[TODO: phone]` tokens.

**Writes To:** `candidate_profile.phone` and `execution_and_safety_policy.phone_policy`.

---

## Step 3: Target Roles, Domain Track & Competency Buckets

**Goal:** Lock role scope, domain-agnostic skill buckets, seniority stretch limits, and explicit exclusion filters so discovery and tailoring stay focused.

**Pre-Fill Summary to Show User:**
- Inferred `domain_track` (`engineering | product | design | data | gtm | operations | research`)
- Proposed `competency_buckets[]` extracted from the resume (for example, `Languages`, `Backend & Distributed Systems`, `AI / ML`, `Frontend` for SWE; or `Product Strategy`, `Analytics & Experimentation`, `Execution & Tooling` for PM; or `Core Craft`, `Tools & Platforms`, `Domain Expertise` for other domains)
- Proposed target `titles[]`

**`ask_question` Call:**
- **Question 1 (`domain_track`):** `Which primary domain track best matches the roles you are targeting?`
  - `Software / AI / Systems Engineering (Recommended when resume is technical)` -> `engineering`
  - `Data / ML / Applied Research` -> `data` (or `research`)
  - `Product Management / Technical Program Management` -> `product`
  - `Design / UX / Creative` -> `design`
  - `Go-To-Market / Growth / Operations` -> `gtm` (or `operations`)
- **Question 2 (`excluded_role_signals`, `is_multi_select: true`):** `Which out-of-scope role types should discovery automatically skip?`
  - `Unpaid, equity-only, or 100% commission roles (Recommended)` -> `unpaid_or_100pct_commission`
  - `Security clearance or citizen-only onsite mandates (Recommended)` -> `clearance_or_citizenship_mandate`
  - `Pure AppSec / CVE hunting / Bug Bounty / Vulnerability Research` -> `pure_appsec_cve_hunting`
  - `Dedicated SRE / DevOps / Terraform / Puppet infra-ops roles` -> `dedicated_infra_sre_ops`
  - `Pure non-coding sales / presales / RevOps / BI-only roles` -> `non_coding_sales_or_bi_only`

**Follow-up confirmation:** Confirm exact `target_roles.titles[]`, `target_roles.competency_buckets[]`, `seniority_window.min_yoe`, `seniority_window.max_yoe_stretch` (default: `actual_full_time_yoe + 2`), `role_eligibility_tracks.track_1_skill_match_min_pct` (default `80`), and any `role_eligibility_tracks.track_2_specialty_targets[]` (focused stretch tracks the candidate explicitly wants).

**Writes To:** `target_roles.*` in `<workspace>/GLOBAL_REFERENCE.md` and `Skills & Competency Buckets` in `<workspace>/resume/master_profile.md`.

---

## Step 4: Geography, Work Modes, Timezone Overlap & Notice Period

**Goal:** Establish India-first defaults (or user-overridden country/timezone), approved work modes, ATS city formatting, foreign visa answers, and notice/relocation policy.

**India-First Baseline Presented for Confirmation:**
- `residence_country`: `India`
- `primary_iana`: `Asia/Kolkata` | `display_label`: `IST (UTC+5:30)`
- `home_country_authorized`: `true` | `foreign_visas_held`: `[]`
- `standard_foreign_visa_answer`: `"N/A - I will be working outside the target country (remote from India)"` (or `No` when applying strictly for remote India/EOR employment and only `Yes/No` exists)

**`ask_question` Call:**
- **Question 1 (`work_modes`, regions & timezone-shift cap, `is_multi_select: true`):** `Which work modes, hiring regions, and timezone overlap levels do you want to target?`
  - `Remote — India, Worldwide, or APAC daytime/async (Recommended)` -> `remote_india_worldwide_apac` (`extended_overlap_willingness: false`, `max_overlap_shift_hours: 3`, `allow_full_foreign_shift_oncall: false`)
  - `Remote — EU / UK afternoon or partial US overlap (<= 4h shift; no full US night shift)` -> `remote_partial_overlap_4h` (`extended_overlap_willingness: true`, `max_overlap_shift_hours: 4`, `allow_full_foreign_shift_oncall: false`)
  - `Remote — Extended cross-ocean overlap (up to 6h shift; no full foreign-TZ shift or on-call)` -> `remote_extended_overlap_6h` (`extended_overlap_willingness: true`, `max_overlap_shift_hours: 6`, `allow_full_foreign_shift_oncall: false`)
  - `Remote — Full US / foreign-timezone hours & on-call rotation` -> `remote_full_foreign_shift_oncall` (`extended_overlap_willingness: true`, `max_overlap_shift_hours: 12`, `allow_full_foreign_shift_oncall: true`)
  - `Hybrid or Onsite — Indian hubs (e.g., Bengaluru, Pune, Mumbai, Delhi NCR, Chennai)` -> `hybrid_onsite_india`
  - `Open to international relocation (while noting remote preference first)` -> `international_relocation`
- **Question 2 (`notice_period_days`):** `What is your notice period for earliest start date calculations?`
  - `30 days / 1 month (today + 30d) (Recommended)` -> `30`
  - `Immediate / 0–15 days` -> `15`
  - `60 days / 2 months` -> `60`
  - `90 days / 3 months` -> `90`

**Follow-up text (if missing):**
- Confirm the exact numeric `timezone.max_overlap_shift_hours` hard cap and `timezone.allow_full_foreign_shift_oncall` boolean (`false` by default unless `remote_full_foreign_shift_oncall` was selected). Note explicitly that postings exceeding `max_overlap_shift_hours` or requiring disallowed full foreign-timezone shifts/on-call are hard-excluded (`tz_shift_exceeded` / `full_foreign_shift_oncall`) rather than kept in `Tier B2`.
- Ask for `residence_city` (used for ATS `City*` inputs, e.g., `<City>, India`), `preferred_onsite_hybrid_hubs[]` (if `hybrid` or `onsite` is selected), and whether `resume_header_location` should show `India (IST / UTC+5:30)` or `<City>, India`.
- If the user is NOT based in India, capture their actual `residence_country`, `residence_city`, `primary_iana` timezone, `display_label`, and `foreign_visas_held`.
- If `international_relocation` is selected, confirm `relocation_policy.mode: yes_with_remote_preference_note` (`"First preference is always the remote role."`) and record `open_relocation_hubs[]`.

**Writes To:** `target_geos.*`, `timezone.*`, and `notice_and_relocation.*`.

---

## Step 5: Compensation Floor, Multi-Currency FX & EOR Localization Policy

**Goal:** Set a clear minimum compensation floor across INR (`LPA`), USD, or EUR, freeze an explicit FX comparison snapshot, and define how to handle unstated pay or location-adjusted EOR bands.

**`ask_question` Call:**
- **Question 1 (`comp_floor` preset):** `What is your minimum annual gross/base compensation floor?`
  - `>= $100,000 USD/year (or INR equivalent ~85 LPA; select currency/custom next if different) (Recommended for global USD remote)` -> `100000_USD`
  - `>= 45 LPA INR/year (~$53k USD; India domestic & APAC floor)` -> `4500000_INR`
  - `>= 30 LPA INR/year (~$35k USD; early/mid India domestic floor)` -> `3000000_INR`
  - `>= $70,000 USD/year (~59 LPA INR)` -> `70000_USD`
  - `Custom amount & currency (USD / INR / EUR / GBP)` -> `custom`
- **Question 2 (`accept_location_adjusted_eor` & `require_explicit_comp`):** `How should discovery treat unstated pay or "location-adjusted" EOR pay language?`
  - `Require explicit comp >= floor; route "location-adjusted" postings to Tier B2 warning (Recommended)` -> `strict_comp_b2_loc`
  - `Allow unstated comp into Tier B2; route "location-adjusted" postings to Tier B2 warning` -> `allow_b2_unstated_b2_loc`
  - `Strictly exclude both unstated comp and "location-adjusted" postings` -> `strict_both`

**Record Explicit FX Snapshot:**
- Prompt or confirm current `fx_reference_rates` (`as_of: YYYY-MM-DD`, e.g., `INR_per_USD`, `INR_per_EUR` or inverse ratios to `comp_floor.currency`) and `contract_annualization_hours: 2000`.

**Writes To:** `comp_floor.*`.

---

## Step 6: Website Execution Mode & Legal Clause Guardrails

**Goal:** Keep safe human-in-the-loop pre-submit confirmation as the default, while offering explicit opt-in to `yolo_with_guardrails`, and define shady legal triggers.

**`ask_question` Call:**
- **Question 1 (`web_apply_mode`):** `How should website applications (Workflow 2) behave at the final Submit button?`
  - `Safe HITL Pre-Submit — fill fields, upload PDF, screenshot, and pause for my final Submit click (Recommended)` -> `hitl_pre_submit`
  - `Opt-in YOLO with Guardrails — auto-check standard privacy/AI disclosures and click Submit, while still halting on CAPTCHAs, email verification codes, logins, anti-LLM honesty checks, and shady legal clauses` -> `yolo_with_guardrails`
- **Question 2 (`shady_clause_escalation_triggers`):** `When should form checkboxes or legal agreements pause for your review?`
  - `Auto-handle standard recruiting privacy/AI-hiring disclosures; pause on non-competes, broad outside-work IP assignment, invasive device tracking, or liability waivers (Recommended)` -> `standard_triggers`
  - `Pause on ALL legal, privacy, or consent checkboxes` -> `pause_all_legal`

**Non-Negotiable Safety Policy Note (Displayed to User):**
Regardless of `web_apply_mode`, the agent will **never** solve or bypass CAPTCHAs, click anti-bot gates, auto-read emails for `"confirm you're a human"` verification codes, bypass logins/MFA, answer anti-LLM honesty booleans dishonestly (`[HUMAN AUTHORING REQUIRED]`), or populate hidden honeypot inputs.

**Writes To:** `execution_and_safety_policy.*`.

---

## Step 7: Cold Email Outreach Setup, Confidentiality & Baseline Render Check

**Goal:** Detect connected email integrations via `list_plugin_accounts`, enforce strict HITL email outreach with employer confidentiality guards, and complete the baseline 1-page PDF verification.

**Pre-Step Tool Check:** Call `list_plugin_accounts` before asking Step 7 questions so you know whether `gmail` is connected and which account identifier(s) exist.

**`ask_question` Call:**
- **Question 1 (`outreach_policy.email_plugin`):** `How would you like to prepare cold outreach emails (Workflow 3, always strict HITL — never auto-sent)?`
  - If `gmail` is connected:
    - `Use connected Gmail plugin in draft-first HITL mode (create-draft only; show To & Subject before any send) (Recommended)` -> `gmail`
    - `Generate clean Markdown copy-paste email dossiers only (for Outlook, Proton, Apple Mail, or manual send)` -> `none`
    - `Skip cold email outreach completely (website applications only)` -> `disabled`
  - If no `gmail` account is connected:
    - `Generate clean Markdown copy-paste email dossiers only (no Gmail plugin required; works with Outlook, Proton, Apple Mail) (Recommended)` -> `none`
    - `Skip cold email outreach completely (website applications only)` -> `disabled`
- **Question 2 (`outreach_policy.eligibility_rule`):** `Which targets should receive optional cold outreach alongside website applications?`
  - `Established companies or high-fit roles meeting my comp floor with a verified public email; skip lightweight form-only apps like Notion forms (Recommended)` -> `established_or_comp_floor_verified_email`
  - `Only top-priority Tier A roles with a verified founder or hiring-lead email` -> `tier_a_only`
  - `Disable cold outreach` -> `disabled`

**Confidentiality & Subject Validation Confirmation:**
- Show the mandatory subject format: `Job Application: <Exact Role Title> — <Candidate Name>`.
- Confirm `forbidden_subject_tokens` automatically populated with `candidate_profile.current_employer` (if non-empty and not `"None"`), `"->"`, and any extra confidential client/project names the user wants blocked from email subjects.

**Writes To:** `outreach_policy.*` in `<workspace>/GLOBAL_REFERENCE.md`.

---

## Step 8 (Post-Interview Execution): Baseline 1-Page Render Verification

Immediately after writing `<workspace>/resume/master_profile.md` and `<workspace>/GLOBAL_REFERENCE.md` (with Step 1–7 recorded in Section 4):
1. Copy `../career-autopilot-apply/resources/resume_template.html` to `<workspace>/resume/backup_resume.html`.
2. Populate `<workspace>/resume/backup_resume.html` from `<workspace>/resume/master_profile.md` (setting `<html lang="en" data-page-size="a4">` or `"letter"` per `resume_page_size`, replacing all `{{...}}` template tokens, and omitting `{{PHONE_SEGMENT}}` when `phone_policy` omits phone on PDFs).
3. Run `../career-autopilot-apply/scripts/render_resume_pdf.sh` (or `render_resume_pdf.ps1` on native Windows PowerShell) with `--strict-1-page` and **without** `--allow-todo` to produce `<workspace>/resume/<Candidate_Slug>_Backup_Resume.pdf`.
   - If intentional `[TODO:` fields remain unresolved in the draft, inform the user clearly, run a preview render with `--allow-todo`, and note that strict production applications remain blocked until `[TODO:` markers are resolved.
4. Inspect `<workspace>/resume/<Candidate_Slug>_Backup_Resume.pdf` via `read_file` to verify `Page 1 of 1`, crisp layout, and zero leaked `[TODO:` strings.
5. Present the created workspace files and next steps (Phase 1 discovery via `career-autopilot-scout`, Phase 2 apply via `career-autopilot-apply`, and optional `automations/install-sidecars.sh` setup).
