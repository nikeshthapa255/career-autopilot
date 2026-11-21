# Application State: {{COMPANY_NAME}} — {{ROLE_TITLE}}

- **Company Slug:** `{{COMPANY_SLUG}}`
- **Target Role:** `{{ROLE_TITLE}}`
- **Workflows Executed:** `Workflow 1` / `Workflow 2` / `Workflow 3`
- **Status:** `Drafted` / `Pre-Filled (Paused Before Submit)` / `Blocked on User Input` / `Gmail Draft Saved` / `Copy-Paste Dossier Ready` / `Submitted (HITL Confirmed)` / `Submitted (YOLO Web Apply)`
- **Last Updated:** `YYYY-MM-DD HH:MM {{TZ_LABEL}}`

## 1. Resume Used
- **HTML Source:** `applications/{{COMPANY_SLUG}}/resume_tailored.html`
- **PDF Output:** `applications/{{COMPANY_SLUG}}/{{CANDIDATE_SLUG}}_{{COMPANY_TOKEN}}_Resume.pdf`
- **Page Size:** `{{PAGE_SIZE}}` (`letter` / `a4`)
- **Render Mode:** `strict (--strict-1-page)` / `--allow-todo` *(1-page visually verified via `read_file`: Yes/No)*
- **Unresolved Placeholders:** `None` / `<list>`

## 2. Website Application State (Workflow 2)
- **Apply URL:** `{{APPLY_URL}}`
- **Execution Mode & Portal Mode:** `{{WEB_APPLY_MODE}}` (`hitl_pre_submit` | `yolo_with_guardrails`) / `Mode A (Public DOM)` | `Mode B (--autoConnect)`
- **ATS Platform & Detected Gates:** `<Ashby / Greenhouse / Lever / Workday / Notion / Breezy / Generic Portal>` (`CAPTCHA: ...`, `Honeypot: ...`, `Prompt Injection: ...`, `Anti-LLM Honesty Check: ...`, `Login/MFA: ...`)
- **Root Upload Staging & Tab Isolation:** `Staged at <Root Artifact Directory Path>/browser_sandbox/uploads/{{CANDIDATE_SLUG}}_{{COMPANY_TOKEN}}_Resume.pdf: Yes/No` | `Isolated Tab Verified: Yes/No`
- **Browser Subagent Run:** `<subagent conversationId or Not Run>`
- **Fields Filled vs Blocked:**
  | Field | Req/Opt | Value Filled / Mapped | Status |
  | :--- | :-: | :--- | :--- |
  | ... | ... | ... | `Filled` / `Blocked` / `Skipped (Honeypot)` / `[HUMAN AUTHORING REQUIRED]` |
- **Screenshot / Visual Evidence:** `<path or note>`
- **Submission Confirmation:** `<HTTP status + exact confirmation text, or Pending HITL Submit>`

## 3. Cold Email / Outreach State (Workflow 3)
- **Outreach Eligibility:** `Eligible` / `Skipped (<reason>)`
- **Cold Email Dossier:** `applications/{{COMPANY_SLUG}}/cold_email.md` (or `Not Created`)
- **Verified Recipient(s) & Source URL:** `<email + public Source URL, or [NO VERIFIED EMAIL]>`
- **Subject Validation:** `Matches "Job Application: <Exact Role Title> — <Candidate Name>" and excludes forbidden_subject_tokens: Yes/No`
- **Delivery Channel:** `gmail` (`AGY_ACCOUNT={{AGY_ACCOUNT}}`) / `copy_paste_dossier`
- **Gmail Draft ID:** `<draft_id or Not Created>` *(Note `--to ""` if `[HOLD]` draft)*
- **Pre-Conditions:** `<e.g., Resolve phone if required; submit primary form first>`
- **Explicit HITL Approval:** `Pending` / `Approved (YYYY-MM-DD HH:MM)`

## 4. Blockers & Questions for `GLOBAL_REFERENCE.md`
- [ ] `<Exact blocker, shady clause, anti-LLM honesty check, or Q-ID question uncovered during execution>`
