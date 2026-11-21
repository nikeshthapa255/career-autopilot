# Workflow 3: Verified Cold Email Outreach (Strict HITL)

Researches verified public contacts and authentic technical/product hooks, pairs outreach with a strict 1-page tailored PDF resume, drafts a concise cold email package, and enforces a **mandatory HITL approval gate** before sending.

> **Eligibility Gate (`outreach_policy`):** Evaluate `GLOBAL_REFERENCE.md` -> `outreach_policy` before researching or drafting:
> - Run Workflow 3 **only** when `eligibility_rule` passes (e.g., established company or remote target-domain role meeting `comp_floor`) AND the ATS is **not** listed in `skip_form_only_ats` (e.g., `notion_form`).
> - Skip cold email for roles failing `comp_floor` or companies lacking a verified public email, routing those roles solely through [Workflow 2 (Browser Apply)](./workflow-2-browser-apply.md).

---

## Step 1: Research Verified Contacts & Authentic Hooks (Zero Guessing)

Using `search_web` (company `/team`, `/about`, `/careers`, `/blog`, official GitHub org/commits, YC company profiles, HN *Who is Hiring?* threads):

1. **Identify the Decision-Maker:**
   - Founder, CTO, VP/Head of Engineering, Hiring Manager, or Functional Lead for the target team.
   - Record exact full name, role/title, and public profile URLs.
2. **Strict Public Email Verification (Zero Guessing):**
   - Record an email address **only** if explicitly published on a verifiable public source, and store the exact **`Source URL`** alongside it.
   - **NEVER** guess, extrapolate, or synthesize addresses like `first@company.com`.
   - **No-Email Fallback:** If no verified public email exists, **skip Workflow 3 completely**, log `[NO VERIFIED EMAIL — SKIP COLD EMAIL, ROUTE TO WORKFLOW 2]` in `applications/<company-slug>/application_state.md`, and proceed solely with [Workflow 2](./workflow-2-browser-apply.md).
3. **Collect 2–3 Authentic Recent Hooks:**
   - Open-source repos, engineering architecture posts, benchmarks, product releases, or technical writing directly tied to the target role.

---

## Step 2: Generate & Verify Strict 1-Page PDF Resume

1. Run [Workflow 1](./workflow-1-tailor.md) with `--strict-1-page` (NO `--allow-todo`) to produce:
   - `applications/<company-slug>/resume_tailored.html`
   - `applications/<company-slug>/<Candidate_Slug>_<Company>_Resume.pdf`
2. Inspect the PDF directly with `read_file` to confirm `Page 1 of 1` and clean rendering.
3. Never attach a draft containing `[TODO:` or `[USER INPUT NEEDED` to an email draft or outgoing message.

---

## Step 3: Draft & Validate Cold Email Dossier (`applications/<company-slug>/cold_email.md`)

Create `applications/<company-slug>/cold_email.md` with:

1. **Target Metadata:**
   - Target role title and posting URL
   - Verified recipient(s) + exact public `Source URL`
   - Tailored 1-page PDF path
2. **Mandatory Subject Template & Forbidden-Token Check:**
   - Build the subject from `outreach_policy.subject_template`:
     - `Job Application: <Exact Role Title> — <Candidate Name>` *(or `Job Application for <Exact Role Title> at <Company> — <Candidate Name>`)*
   - **Forbidden Subject Tokens (`outreach_policy.forbidden_subject_tokens`):** Reject any subject containing `candidate_profile.current_employer` (case-insensitive), `->` arrows, custom confidential tokens from `GLOBAL_REFERENCE.md`, or marketing hype strings.
3. **Body (120–170 Words):**
   - Apply the bundled [clear-natural-english](../../clear-natural-english/SKILL.md) skill so the note reads like a real person writing to a specific engineering or hiring lead (direct opener, plain verbs, zero hype, zero fake contrasts or wrap-up filler).
   - **Hook (1–2 sentences):** Reference a specific verified technical/product detail from Step 1 (no generic flattery).
   - **Grounded Proof Points (2–3 concise bullets or sentences):** Cite only verified achievements and metrics from `resume/master_profile.md` (`Verified Quantitative Baseline`).
   - **Attachment & Logistics (1–2 sentences):** Reference the attached 1-page PDF, state `resume_header_location` / `timezone.display_label` and work-auth/overlap fit cleanly, and ask for a brief 15-minute intro call.
4. **Follow-Up Template (5–7 Days Later):**
   - 40–70 words, polite single-reply bump reinforcing one relevant point.
5. **Pre-Send HITL Checklist:**
   - [ ] Tailored PDF rendered cleanly without `--allow-todo` and verified `Page 1 of 1` via `read_file`.
   - [ ] Recipient email verified with explicit public `Source URL`.
   - [ ] Subject matches `Job Application: <Exact Role Title> — <Candidate Name>` and passes `forbidden_subject_tokens` (zero `current_employer`, zero `->`).
   - [ ] Exact `To`, `Subject`, body, and attachment path displayed to user in chat.
   - [ ] Explicit user approval received before sending.

---

## Step 4: Mandatory HITL Approval Gate & Delivery (`Gmail` Optional + Copy-Paste Fallback)

**NEVER send an email automatically.** Always display the exact **`To`**, exact **`Subject`**, full body (or exact copy), PDF attachment path, and `Draft ID` (if created) directly in chat before requesting send approval.

Check `GLOBAL_REFERENCE.md` (`outreach_policy.email_plugin` / `agy_account`) and run `list_plugin_accounts`:

### Path A — `gmail` Plugin Connected (`outreach_policy.email_plugin == "gmail"`)

1. Ensure the `gmail` CLI is initialized (`<GMAIL_SKILL_DIR>/scripts/gmail --version`, then invoke bare `gmail`). Always set `AGY_ACCOUNT="<outreach_policy.agy_account>"` when multiple accounts exist.
2. Write the approved plain-text body to conversation scratch storage (avoid transient files inside `applications/`).
3. **Create Safe Draft (`--to ""` Hold Pattern When Gated):**
   - Ready draft (all pre-conditions satisfied):
     ```bash
     AGY_ACCOUNT="<email>" gmail mutate create-draft \
       --to "<verified_recipient>" \
       --subject "<validated_subject>" \
       --body-file "<scratch/body.txt>" \
       --file "applications/<company-slug>/<Candidate_Slug>_<Company>_Resume.pdf"
     ```
   - Safe `[HOLD]` draft (when waiting on primary form submission, unresolved `[TODO:`, or final recipient verification): pass `--to ""` so the MIME `To:` header stays empty and cannot be accidentally dispatched.
4. **Send ONLY After Explicit User Confirmation:**
   - Run `AGY_ACCOUNT="<email>" gmail mutate send-draft <DRAFT_ID>` (or `send-with-attachment`) **only** after the user explicitly approves the exact `To`, `Subject`, body, and attachment in the active turn.
   - Never run `gmail mutate delete-draft` on a draft already shared with the user without checking `readonly drafts` and `readonly search "in:sent ..."` first (prefer `update-draft`).
   - **Unattended Sidecars:** Scheduled sidecars execute with `AGY_UNATTENDED=1` and must **never** call `send`, `send-draft`, `send-with-attachment`, `reply`, or `forward`; they stop strictly at `create-draft` / `update-draft`.

### Path B — No Gmail Plugin Connected (`email_plugin: none` or External Mail Client)

If the user has not connected `gmail` or prefers Outlook, Proton Mail, Apple Mail, or Fastmail:

1. Write the complete dossier to `applications/<company-slug>/cold_email.md`.
2. Output a clean, copy-paste-ready Markdown block directly in chat containing **`To`**, **`Subject`**, **`Attachment Path`**, **`Body`**, and **`Follow-up (Day +5 to +7)`** so the user can send manually without needing any Gmail plugin.

---

## Step 5: State Logging & Single-Writer Merge

1. Record recipient verification, `Source URL`, delivery channel (`gmail` or `copy_paste_dossier`), `Draft ID` (if applicable), and unresolved blockers inside `applications/<company-slug>/application_state.md`.
2. The root coordinator merges finalized statuses (`Drafted — Pending HITL Review`, `Gmail Draft Saved`, `Copy-Paste Dossier Ready`, `Submitted (HITL Confirmed)`, or `Follow-up Sent`) into `applications/tracker.md` and `GLOBAL_REFERENCE.md`.
