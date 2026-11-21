# Antigravity Plugin and Scheduled Sidecar Specification (`career-autopilot`)

> **Scope:** Exact packaging, manifest, lifecycle hook, rule-budget, installation, and scheduled sidecar specification for the `career-autopilot` Antigravity plugin. Every schema field, path rule, and permission boundary below reflects Antigravity's plugin, hook, rule, skill, Gmail, and automation specifications.

---

## 1. Plugin Directory Layout (`plugin/`)

The distributable plugin lives under `plugin/` in this repository and ships with zero personal candidate data:

```text
plugin/
├── plugin.json                         # Required manifest (JSONC supported)
├── README.md                           # User-facing documentation (never read by the agent)
├── hooks.json                          # MUST sit directly at plugin root
├── hooks/                              # Portable POSIX sh scripts called by hooks.json
├── assets/
│   └── logo.svg                        # High-contrast square SVG (>= 128x128, ~10% margin)
├── rules/
│   └── AGENTS.md                       # Plain markdown (no frontmatter), capped at 24,000 bytes
├── agents/
│   ├── career-autopilot-scout.md       # Read-only Phase 1 discovery scout
│   └── career-autopilot-worker.md      # Isolated Phase 2 per-application worker
└── skills/
    ├── career-autopilot-onboard/       # Phase 0 intake, preferences, workspace init
    │   ├── SKILL.md
    │   ├── references/
    │   │   └── intake-question-tree.md
    │   └── scripts/
    │       └── init-workspace.sh
    ├── career-autopilot-scout/         # Phase 1 multi-source discovery & screening
    │   ├── SKILL.md
    │   └── references/
    │       ├── ats-api-endpoints.md
    │       └── screening-gates.md
    ├── career-autopilot-apply/         # Phase 2 tailoring, browser apply, & outreach
    │   ├── SKILL.md
    │   ├── references/
    │   │   ├── workflow-1-tailor.md
    │   │   ├── workflow-2-browser-apply.md
    │   │   └── workflow-3-cold-email.md
    │   ├── resources/
    │   │   ├── resume_template.html
    │   │   └── application_state_template.md
    │   └── scripts/
    │       ├── render_resume_pdf.sh
    │       └── render_resume_pdf.ps1
    └── clear-natural-english/          # Prose clarity & anti-AI-slop writing standard
        ├── SKILL.md
        └── references/
            └── patterns-and-examples.md
```

---

## 2. Manifest (`plugin/plugin.json`) Contract

Antigravity parses `plugin.json` as JSONC (comments and trailing commas allowed). **Only documented top-level keys are kept; any unknown top-level field is silently discarded** (it neither takes effect nor errors).

| Field | Type | Contract for `career-autopilot` |
| :--- | :--- | :--- |
| `name` | `string` | `"career-autopilot"` — lowercase `kebab-case` global identifier. Two plugins sharing `name` collide and the later one is dropped silently. Distinct from the install directory `<dir>` if installed under another folder name. |
| `displayName` | `string` | `"Career Autopilot"` — human-readable title shown in UI cards, headers, and slash-command menus. |
| `version` | `string` | Semantic version string (e.g., `"0.1.0"`). |
| `description` | `string` | One or two concise sentences describing what the plugin does and who it is for (indexed by search). |
| `author` | `string \| object` | Maintainer string or `{"name": "...", "url": "https://..."}`. |
| `homepage` | `string` | Optional `https://` documentation URL. |
| `repository` | `string \| object` | Optional `https://` repo URL or `{"type": "git", "url": "https://..."}`. |
| `logo` | `string` | `"assets/logo.svg"` — relative path ending in `.png`, `.svg`, `.jpg`, `.jpeg`, or `.webp`. Absolute paths and remote URLs are silently rejected. |
| `suggestedPrompts` | `string[]` | Exactly 3 concise starter prompts for card/detail views (empty strings are skipped; entries past 3 are ignored). |
| `disabled` | `boolean` | Optional (`false` by default; omitted when shipped enabled). A user toggle stored in `config.json` always overrides `plugin.json`. |

---

## 3. Rules, Agents, and Skills Constraints

### 3.1 Always-On Rules (`plugin/rules/AGENTS.md`)
- **Format:** Plain Markdown with **no YAML frontmatter** (`rules/AGENTS.md` is merged into the active rule set whenever the plugin is enabled).
- **Hard Size Cap:** **24,000 bytes (`24 KB`)** per file after expanding any `@[label](path)` includes; content over the limit is truncated on line boundaries.
- **Aggregate Budget:** Always-on and global rules share Antigravity's **20,000-token** `defaultRulesBudget`. Keeping `AGENTS.md` crisp and focused avoids demotion to path pointers.
- **Core Invariants Enforced:** Zero metric/employer fabrication, strict `master_profile.md` baseline lock, `hitl_pre_submit` safe default for web applications unless explicitly set to `yolo_with_guardrails`, unconditional anti-bot/CAPTCHA/email-code stops, indirect prompt-injection & honeypot defense, shady legal clause escalation, and mandatory HITL gate on cold emails (blocking `current_employer` and `->` in subject lines).

### 3.2 Agent Definitions (`plugin/agents/*.md`)
Agent markdown files use YAML frontmatter specifying `name`, `description`, `tools`, `mainAgent`, `subagent`, and execution policies, followed by strict isolation rules:
- `career-autopilot-scout.md`: Phase 1 read-only discovery scout (returns structured leads and exclusions; never edits shared state files directly if delegated under coordinator merge).
- `career-autopilot-worker.md`: Phase 2 isolated worker bound to one `applications/<company-slug>/` folder; reads `GLOBAL_REFERENCE.md` and `master_profile.md` read-only and never edits `applications/tracker.md` or `GLOBAL_REFERENCE.md` concurrently.

### 3.3 Skills (`plugin/skills/*/SKILL.md`)
- Every `SKILL.md` begins with YAML frontmatter containing lowercase hyphenated `name` (`career-autopilot-onboard`, `career-autopilot-scout`, `career-autopilot-apply`, `clear-natural-english`) and third-person `description` triggers.
- Bulk runbooks, endpoint guides, HTML templates, and helper scripts reside in `./references/`, `./resources/`, and `./scripts/` linked via relative markdown links so Antigravity loads only metadata until a skill activates (progressive disclosure).

---

## 4. Lifecycle Hooks (`plugin/hooks.json`)

### 4.1 Placement & Execution Environment
- **Root Placement Requirement:** Antigravity runtime plugin discovery loads `hooks.json` **strictly from the plugin root** (`<plugin_dir>/hooks.json`). While `agy plugin install` copies `hooks/hooks.json` for pure Gemini CLI (`gemini-extension.json`) or Claude Code (`.claude-plugin/plugin.json`) imports, **native plugins (`plugin.json`) do not run extension staging** and must keep `hooks.json` directly at the plugin root.
- **Runtime Working Directory & Env Vars:** Hook commands execute synchronously via `sh -c` on Unix (`cmd /c` on Windows) with the working directory set to the folder containing `hooks.json` (`PLUGIN_ROOT` and `PLUGIN_DATA` are also injected into the environment). Commands must refer to bundled scripts with relative paths such as `./hooks/<script>.sh`.
- **Supported Event Types:** `SessionStart`, `PreToolUse` (grouped by tool `matcher` regex + `hooks` list), `PostToolUse` (grouped), `PreInvocation`, `PostInvocation`, and `Stop`. Tool names equal the lowercased step type with `CORTEX_STEP_TYPE_` stripped (e.g., `run_command`, `write_file`).

### 4.2 `PreToolUse` I/O Contract & Safety Gates
- **Stdin:** CamelCase JSON containing common metadata (`conversationId`, `workspacePaths`, `cwd`, `hookEventName`) plus `toolCall` (`id`, `name`, `args`).
- **Stdout:** JSON object with required `"decision"` (`"allow"`, `"deny"`, `"ask"`, `"force_ask"`) and optional `"reason"`, `"permissionOverrides"`, or `"overwrite"`.
- **Portable POSIX Implementation (`plugin/hooks/pre_tool_safety.sh`):** Hook `"career-autopilot-safety-gate"` matches `run_command` and executes `./hooks/pre_tool_safety.sh` (`timeout: 10`), avoiding non-guaranteed runtimes (`jq`, Python, Node) by parsing `stdin` JSON with POSIX `sh` / `awk` / `grep` and defaulting gracefully to `"allow"` on benign commands.
- **Safety Gates Enforced by `pre_tool_safety.sh`:**
  1. **Unattended & HITL Outbound Email Gate:** Inspects `gmail mutate` commands (`send`, `send-draft`, `send-with-attachment`, `reply`, `forward`, `react`, `create-reaction`). Whenever `AGY_UNATTENDED` is non-empty, returns `"decision": "deny"`. In interactive mode, returns `"decision": "force_ask"` so outbound sends always prompt explicitly.
  2. **Anti-Human-Verification-Code Read Gate:** Returns `"decision": "deny"` if a `gmail readonly` query searches for ATS human-verification security codes (`"confirm you're a human"` or Greenhouse/Ashby verification code queries).
  3. **Subject Arrow & `[TODO:` Attachment Gate:** Returns `"decision": "deny"` if a `Job Application` email subject contains `->`, or if a Gmail draft/send attaches a PDF rendered with `--allow-todo` or backed by `resume_tailored.html` / `backup_resume.html` containing `[TODO:` or `[USER INPUT NEEDED`.

---

## 5. Installation, Loading Priority & Lifecycle Links

### 5.1 Installation Options (Zero `config.json` Edits)
- **Global User Install (Recommended for Personal Use):** Copy `plugin/` to `~/.gemini/config/plugins/career-autopilot/` (first verify `career-autopilot` does not collide with an existing directory or `name` in `~/.gemini/config/plugins/`).
- **Workspace Project Registration:** Register via `<project>/.agents/plugins.json` using a workspace-relative or home-relative `path` to the parent directory containing `career-autopilot/`:
  ```json
  {
    "entries": [
      {
        "path": "/path/to/plugins-parent-dir",
        "include_only": ["career-autopilot"]
      }
    ]
  }
  ```
  Each entry directory is scanned **one level deep**, so `entries[].path` must point to the parent folder containing `career-autopilot/`, or `plugin/` may live directly at `.agents/plugins/career-autopilot/`.
- **Marketplace vs. Repo Distribution:** Published Marketplace entries install via `search_marketplace` and `<plugin-card catalog-id="...">`. Self-hosted repository plugins are installed directly into `~/.gemini/config/plugins/career-autopilot/` or `.agents/plugins.json` (remembering that `agy plugin install` extension staging is for Gemini CLI / Claude Code formats rather than native `plugin.json` bundles).

### 5.2 Loading Priority & State Integrity
When duplicate names exist across customization roots, higher priority overrides lower priority in this exact order:
1. **Workspace Project:** `.agents/` directories walking up from CWD to the repository root.
2. **Workspace Declared Configs:** `.agents/plugins.json` and `.agents/skills.json`.
3. **Global Discovery:** `~/.gemini/config/` (where `~/.gemini/config/plugins/career-autopilot/` lives).
4. **Built-in Customizations:** Bundled application skills and plugins.
5. **Global Declared Configs:** `~/.gemini/config/plugins.json` / `skills.json`.

**Operational Rules:**
- **Never edit `~/.gemini/config/config.json` manually** (mode `0600` atomic state holding `userSettings` and permission grants) and never call `JetboxWriteState`, `DeletePlugin`, or `InstallCustomization` from `run_command`.
- **UI Links:** Direct users to `[Career Autopilot](customization://<dir>)` keyed by the **install folder name (`<dir>`)**, never `plugin.json`'s `name` if they differ, and never emit `plugin://` or `plugins://` links.

---

## 6. Scheduled Sidecars (`"builtin": "schedule"`) & Permission Contracts

Scheduled automations under `automations/` instantiate `~/.gemini/config/sidecars/<sidecar-id>/sidecar.json` using Antigravity's `"builtin": "schedule"` schema.

### 6.1 Required Schema Rules
- **Top-Level Fields (strictly `snake_case`):**
  - `"builtin": "schedule"`
  - `"args"`: array starting with `args[0]` = `"CRON_TZ=<IANA_Zone> <5-field-cron>"`, followed by `"agentapi"`, `"new-conversation"`, `"--"`, and the self-contained prompt string (`"--"` separates flags from prompt).
  - `"restart_policy": "always"` (lowercase string literal required for `"builtin": "schedule"`).
  - `"display_name"` and `"description"`.
  - `"agent_permissions"`: `"workspace_uris"` (`["file://<abs-workspace-path>"]`) and `"access_grants"`.
- **Timezone Default (`CRON_TZ`):** Pre-configured with `CRON_TZ=Asia/Kolkata` (configurable to any IANA zone during installation; never use abbreviations such as `IST` or raw offsets such as `+05:30`).
- **Least-Privilege Grants (No Wildcards):** Never emit `command(*)`, `read_file(*)`, `read_file(/)`, `write_file(*)`, `mcp(*)`, or `read_url(*)`. Use explicit paths and binary/subcommand prefixes.

### 6.2 Sidecar Permission Profiles

| Sidecar | Purpose | Required `access_grants` (Scoped) | Prohibited Grants |
| :--- | :--- | :--- | :--- |
| **`<prefix>-find-jobs`** | Phase 1 scheduled discovery & trap screening (`career-autopilot-scout`) | `read_file(<workspace>)`, `write_file(<workspace>)`, `command(curl)`, and explicit `read_url(<host>)` grants (`jobs.ashbyhq.com`, `api.ashbyhq.com`, `job-boards.greenhouse.io`, `boards-api.greenhouse.io`, `api.lever.co`, `jobs.lever.co`, `www.ycombinator.com`, `www.workatastartup.com`, `news.ycombinator.com`, `hn.algolia.com`) | Wildcard `read_url(*)`, `command(*)`, any email send grant |
| **`<prefix>-auto-apply`** | Phase 2 tailoring, pre-stage & draft creation (`career-autopilot-apply`) | `read_file(<workspace>)`, `write_file(<workspace>)`, `command(<abs_path>/render_resume_pdf.sh)`, `command(gmail readonly)`, `command(gmail mutate create-draft)`, `command(gmail mutate update-draft)`, plus explicit ATS `read_url(<host>)` grants (`jobs.ashbyhq.com`, `api.ashbyhq.com`, `job-boards.greenhouse.io`, `boards-api.greenhouse.io`, `api.lever.co`, `jobs.lever.co`) | `gmail mutate send`, `gmail mutate send-draft`, `gmail mutate send-with-attachment`, `gmail mutate reply`, `gmail mutate forward`, `gmail mutate trash`, `gmail mutate delete-draft` |

### 6.3 Gmail `AGY_UNATTENDED` Draft-Only Boundary
- When Antigravity runs an unattended automation with `AGY_UNATTENDED` set to any non-empty value, the `gmail` CLI enforces a hard CLI-level block on all outbound send operations (`mutate send`, `mutate reply`, `mutate react`, `mutate forward`, `mutate send-with-attachment`, `mutate send-draft`).
- `gmail mutate create-draft` and `gmail mutate update-draft` remain allowed so scheduled runs can prepare reviewable drafts (or `--to ""` hold drafts) without ever transmitting email autonomously.

### 6.4 Idempotent Installer & Manual Dashboard Activation Rule
- `automations/install-sidecars.sh` renders `*.sidecar.json.template` into `~/.gemini/config/sidecars/<prefix>-find-jobs/sidecar.json` and `<prefix>-auto-apply/sidecar.json` (and supports `--dry-run <dir>` for validation without touching `~/.gemini/config/`).
- **Hard Rule on Activation:** `install-sidecars.sh` and agents must **never** modify `user_config.json` to set `"enabled": true` or invoke commands/RPCs to start a sidecar. After writing `sidecar.json`, guide the user to enable each automation by its `display_name` via `[Open Automations Dashboard](sidecar://dashboard)` and offer a live interactive test run first so permissions are verified before unattended runs auto-deny unapproved commands.
