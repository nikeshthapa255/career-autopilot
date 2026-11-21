/**
 * Career Autopilot UI Extension sidecar backend (read-only).
 *
 * Discovers private Career Autopilot workspaces automatically from scheduled
 * sidecar configs (~/.gemini/config/sidecars/*/sidecar.json) or an explicit
 * ?workspace= path, parses tracker.md, new_leads.md, GLOBAL_REFERENCE.md,
 * and optional requirements/README.md, and serves a live Antigravity Aux Pane UI.
 */
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, dirname, isAbsolute, join, resolve as resolvePath, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { SidecarApp, Response } from 'sidecar_sdk';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STATIC = {
  '/styles.css': ['styles.css', 'text/css; charset=utf-8'],
  '/app.js': ['app.js', 'application/javascript; charset=utf-8'],
};
const MAX_READ_BYTES = 512 * 1024;

function safeReaddir(dir) {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

function safeStat(filePath) {
  try {
    const s = statSync(filePath);
    return { exists: true, isDir: s.isDirectory(), isFile: s.isFile(), mtime: s.mtimeMs, size: s.size };
  } catch {
    return { exists: false, isDir: false, isFile: false, mtime: 0, size: 0 };
  }
}

function readTextSafe(filePath) {
  const st = safeStat(filePath);
  if (!st.isFile || st.size > MAX_READ_BYTES) return { text: '', mtime: st.mtime, exists: st.isFile };
  try {
    return { text: readFileSync(filePath, 'utf-8'), mtime: st.mtime, exists: true };
  } catch {
    return { text: '', mtime: 0, exists: false };
  }
}

function expandHome(raw) {
  const s = String(raw || '').trim();
  if (!s) return '';
  if (s === '~') return homedir();
  if (s.startsWith('~/') || s.startsWith('~\\')) return join(homedir(), s.slice(2));
  return s;
}

function fileUriToPath(uri) {
  const s = String(uri || '').trim();
  if (!s) return '';
  if (s.startsWith('file://')) {
    try {
      return fileURLToPath(s);
    } catch {
      return decodeURIComponent(s.replace(/^file:\/\//, ''));
    }
  }
  return expandHome(s);
}

function isCareerWorkspace(dirPath) {
  if (!dirPath || !safeStat(dirPath).isDir) return false;
  return (
    safeStat(join(dirPath, 'GLOBAL_REFERENCE.md')).isFile ||
    safeStat(join(dirPath, 'applications', 'tracker.md')).isFile ||
    safeStat(join(dirPath, 'resume', 'master_profile.md')).isFile
  );
}

function safeWorkspaceUri(workspaceReal, relOrAbs) {
  if (!workspaceReal || !relOrAbs) return null;
  const candidate = isAbsolute(relOrAbs) ? relOrAbs : resolvePath(workspaceReal, relOrAbs);
  try {
    const real = realpathSync(candidate);
    const prefix = workspaceReal.endsWith(sep) ? workspaceReal : workspaceReal + sep;
    if (real !== workspaceReal && !real.startsWith(prefix)) return null;
    if (!safeStat(real).isFile) return null;
    return pathToFileURL(real).href;
  } catch {
    return null;
  }
}

function readSidecarEnabledMap() {
  const candidates = [
    join(homedir(), '.gemini', 'config', 'sidecars', 'user_config.json'),
    join(homedir(), '.gemini', 'config', 'user_config.json'),
  ];
  for (const p of candidates) {
    const { text } = readTextSafe(p);
    if (!text) continue;
    try {
      const parsed = JSON.parse(text);
      if (parsed && typeof parsed === 'object') {
        return parsed.sidecars && typeof parsed.sidecars === 'object' ? parsed.sidecars : parsed;
      }
    } catch {
      // Ignore unreadable user_config
    }
  }
  return {};
}

function scanSidecars() {
  const sidecarsRoot = join(homedir(), '.gemini', 'config', 'sidecars');
  const enabledMap = readSidecarEnabledMap();
  const discoveredWorkspaces = new Map();
  const automations = [];

  for (const id of safeReaddir(sidecarsRoot).sort()) {
    const cfgPath = join(sidecarsRoot, id, 'sidecar.json');
    const { text, mtime } = readTextSafe(cfgPath);
    if (!text) continue;
    let cfg;
    try {
      cfg = JSON.parse(text);
    } catch {
      continue;
    }
    if (cfg?.builtin !== 'schedule') continue;

    const args = Array.isArray(cfg.args) ? cfg.args : [];
    const promptText = String(args[args.length - 1] || '');
    const uris = Array.isArray(cfg?.agent_permissions?.workspace_uris)
      ? cfg.agent_permissions.workspace_uris
      : [];

    const matchedWorkspaces = [];
    for (const u of uris) {
      const p = fileUriToPath(u);
      if (p && isCareerWorkspace(p)) {
        try {
          const real = realpathSync(p);
          matchedWorkspaces.push(real);
          if (!discoveredWorkspaces.has(real)) {
            discoveredWorkspaces.set(real, { path: real, name: basename(real), source: `sidecar:${id}` });
          }
        } catch {
          // Ignore invalid symlink
        }
      }
    }

    const looksCareerRelated =
      matchedWorkspaces.length > 0 ||
      /career-autopilot|find-jobs|auto-apply|find-new-.*jobs|tracker\.md|GLOBAL_REFERENCE\.md/i.test(
        `${id} ${cfg.display_name || ''} ${promptText}`
      );
    if (!looksCareerRelated) continue;

    const entry = enabledMap?.[id];
    const enabled = typeof entry === 'boolean' ? entry : typeof entry?.enabled === 'boolean' ? entry.enabled : null;

    automations.push({
      id,
      displayName: String(cfg.display_name || id),
      description: String(cfg.description || ''),
      schedule: String(args[0] || ''),
      workspaces: matchedWorkspaces,
      enabled,
      configUri: pathToFileURL(cfgPath).href,
      mtime,
    });
  }

  return { workspaces: [...discoveredWorkspaces.values()], automations };
}

// ---------------------------------------------------------------------------
// Markdown helpers (resilient pipe-table & metadata extractors)
// ---------------------------------------------------------------------------

function stripMdFormatting(raw) {
  return String(raw || '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_`~]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractMdLinks(cell) {
  const links = [];
  const re = /\[([^\]]+)\]\(([^)]+)\)/g;
  let m;
  while ((m = re.exec(String(cell || ''))) !== null) {
    links.push({ label: stripMdFormatting(m[1]), href: m[2].trim() });
  }
  return links;
}

function splitPipeRow(line) {
  const trimmed = line.trim().replace(/^\|/, '').replace(/\|$/, '');
  const cells = [];
  let cur = '';
  for (let i = 0; i < trimmed.length; i++) {
    if (trimmed[i] === '\\' && trimmed[i + 1] === '|') {
      cur += '|';
      i++;
    } else if (trimmed[i] === '|') {
      cells.push(cur.trim());
      cur = '';
    } else {
      cur += trimmed[i];
    }
  }
  cells.push(cur.trim());
  return cells;
}

function isSeparatorRow(line) {
  const cells = splitPipeRow(line);
  return cells.length >= 2 && cells.every((c) => /^:?-{2,}:?$/.test(c.replace(/\s+/g, '')));
}

function parseMarkdownTables(md) {
  const lines = String(md || '').split(/\r?\n/);
  const tables = [];
  let heading = '';
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const h = /^#{1,6}\s+(.+)$/.exec(line);
    if (h) {
      heading = stripMdFormatting(h[1]);
      i++;
      continue;
    }
    if (line.trim().startsWith('|') && i + 1 < lines.length && isSeparatorRow(lines[i + 1])) {
      const headers = splitPipeRow(line).map((c) => stripMdFormatting(c));
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        const rawCells = splitPipeRow(lines[i]);
        const row = {};
        headers.forEach((col, idx) => {
          row[col] = rawCells[idx] || '';
        });
        rows.push({ raw: rawCells, byHeader: row });
        i++;
      }
      tables.push({ heading, headers, rows });
      continue;
    }
    i++;
  }
  return tables;
}

function classifyStatus(statusText) {
  const s = statusText.toLowerCase();
  if (/submitted|sent\b|interview|offer/.test(s) && !/needs fresh|blocked|queued|pending/.test(s)) return 'submitted';
  if (/cold email sent/.test(s)) return 'partial';
  if (/blocked|needs fresh|paused|hold|timeout/.test(s)) return 'blocked';
  if (/ready|drafted|pre-filled|retry/.test(s)) return 'ready';
  if (/skipped|closed|excluded|rejected/.test(s)) return 'skipped';
  return 'queued';
}

function parseTracker(workspaceReal, text) {
  const tables = parseMarkdownTables(text);
  const appTable = tables.find((t) =>
    t.headers.some((h) => /^company$/i.test(h)) && t.headers.some((h) => /^status$/i.test(h))
  );
  if (!appTable) return { rows: [], counts: { total: 0, submitted: 0, partial: 0, ready: 0, blocked: 0, queued: 0, skipped: 0 } };

  const appsDir = join(workspaceReal, 'applications');
  const rows = [];
  const counts = { total: 0, submitted: 0, partial: 0, ready: 0, blocked: 0, queued: 0, skipped: 0 };

  for (const r of appTable.rows) {
    const get = (re) => {
      const key = appTable.headers.find((h) => re.test(h));
      return key ? r.byHeader[key] : '';
    };
    const companyRaw = get(/^company$/i);
    const company = stripMdFormatting(companyRaw);
    if (!company || /\{\{/.test(company)) continue;

    const role = stripMdFormatting(get(/^role$/i));
    const workflow = stripMdFormatting(get(/track|workflow/i));
    const status = stripMdFormatting(get(/^status$/i));
    const comp = stripMdFormatting(get(/comp|geo/i));
    const pdfCell = get(/resume|pdf/i);
    const linksCell = get(/email|apply|url|draft/i);
    const notes = stripMdFormatting(get(/notes|gate|recipient/i));
    const updated = stripMdFormatting(get(/updated/i));

    const pdfLinks = extractMdLinks(pdfCell);
    const actionLinks = extractMdLinks(linksCell);

    let pdfUri = null;
    for (const l of pdfLinks) {
      if (l.href.endsWith('.pdf')) {
        pdfUri = safeWorkspaceUri(workspaceReal, resolvePath(appsDir, l.href));
        if (pdfUri) break;
      }
    }

    let stateUri = null;
    let coldEmailUri = null;
    let applyUrl = null;
    for (const l of actionLinks) {
      if (/^https?:\/\//i.test(l.href)) {
        if (!applyUrl) applyUrl = l.href;
      } else if (/application_state\.md$/i.test(l.href)) {
        stateUri = safeWorkspaceUri(workspaceReal, resolvePath(appsDir, l.href));
      } else if (/cold_email\.md$/i.test(l.href)) {
        coldEmailUri = safeWorkspaceUri(workspaceReal, resolvePath(appsDir, l.href));
      }
    }

    const bucket = classifyStatus(status);
    counts.total += 1;
    counts[bucket] = (counts[bucket] || 0) + 1;

    rows.push({
      company,
      role,
      workflow,
      status,
      bucket,
      comp,
      notes,
      updated,
      pdfUri,
      stateUri,
      coldEmailUri,
      applyUrl,
    });
  }

  return { rows, counts };
}

function parseGlobalReference(text) {
  const policy = {};
  const yamlMatch = /```ya?ml\s*\n([\s\S]*?)```/i.exec(text);
  const src = yamlMatch ? yamlMatch[1] : text;

  const extractVal = (re) => {
    const m = re.exec(src);
    if (!m) return '';
    return m[1].replace(/\s+#.*$/, '').replace(/^["'`]+|["'`]+$/g, '').trim();
  };

  policy.webApplyMode =
    extractVal(/web_apply_mode:\s*([^\n]+)/i) ||
    (/YOLO\s*\/\s*Auto-Submit/i.test(text) ? 'yolo_with_guardrails' : 'hitl_pre_submit');
  policy.outreachMode =
    extractVal(/^\s*mode:\s*["']?(hitl_strict|[^\n"']+)["']?/im) ||
    (/Strict HITL/i.test(text) ? 'hitl_strict' : 'hitl_strict');
  policy.phonePolicy =
    extractVal(/phone_policy:\s*([^\n]+)/i) ||
    extractVal(/^\s*policy:\s*["']?(omit_[^\n"']+|always_include)["']?/im) ||
    'omit_on_pdf_and_optional_supply_if_req';
  policy.timezone =
    extractVal(/primary_iana:\s*([^\n]+)/i) ||
    extractVal(/IANA:\s*`?([A-Za-z0-9_/+.-]+)`?/i) ||
    'Asia/Kolkata';
  policy.compFloor =
    extractVal(/Compensation Floor:\*\*\s*`?([^`\n]+)`?/i) ||
    [extractVal(/^\s*amount:\s*([^\n]+)/im), extractVal(/^\s*currency:\s*([^\n]+)/im)].filter(Boolean).join(' ') ||
    'Configured in GLOBAL_REFERENCE.md';

  const tables = parseMarkdownTables(text);
  const qTable = tables.find((t) => t.headers.some((h) => /^q-?id$/i.test(h)));
  const questions = [];
  if (qTable) {
    for (const r of qTable.rows) {
      const get = (re) => {
        const key = qTable.headers.find((h) => re.test(h));
        return key ? stripMdFormatting(r.byHeader[key]) : '';
      };
      const id = get(/^q-?id$/i);
      const question = get(/question|missing/i);
      const affects = get(/affects/i);
      const status = get(/^status$/i);
      const details = get(/details|guidelines/i);
      const answer = get(/answer/i);
      if (!id || /\{\{/.test(id)) continue;

      const isOpen = /open|blocked|pending|needs fresh|awaiting|todo/i.test(status) && !/^resolved|^sent|^created/i.test(status);
      questions.push({ id, question, affects, status, details, answer, isOpen });
    }
  }

  return {
    policy,
    questions,
    openCount: questions.filter((q) => q.isOpen).length,
  };
}

function parseNewLeads(text) {
  const tables = parseMarkdownTables(text);
  const leads = [];
  let latestRun = '';
  const runMatches = [...String(text || '').matchAll(/^##\s+Run:\s*(.+)$/gm)];
  if (runMatches.length) latestRun = stripMdFormatting(runMatches[runMatches.length - 1][1]);

  for (const t of tables) {
    if (!t.headers.some((h) => /company/i.test(h)) || !t.headers.some((h) => /role/i.test(h))) continue;
    let tier = 'Other';
    if (/tier\s*a/i.test(t.heading)) tier = 'Tier A';
    else if (/tier\s*b1/i.test(t.heading)) tier = 'Tier B1';
    else if (/tier\s*b2/i.test(t.heading)) tier = 'Tier B2';
    else if (/pending/i.test(t.heading)) tier = 'Pending';

    for (const r of t.rows) {
      const get = (re) => {
        const key = t.headers.find((h) => re.test(h));
        return key ? r.byHeader[key] : '';
      };
      const company = stripMdFormatting(get(/company/i));
      const role = stripMdFormatting(get(/^role$/i));
      if (!company || /\{\{/.test(company)) continue;

      const comp = stripMdFormatting(get(/comp/i));
      const geo = stripMdFormatting(get(/geo|tz/i));
      const fit = stripMdFormatting(get(/^fit$/i));
      const gates = stripMdFormatting(get(/form|gate|trap/i));
      const urlCell = get(/url/i);
      const urlMatch = /https?:\/\/[^\s)<>|]+/i.exec(urlCell);

      leads.push({
        tier,
        company,
        role,
        comp,
        geo,
        fit,
        gates,
        url: urlMatch ? urlMatch[0] : null,
      });
    }
  }

  return { latestRun, leads };
}

function parseRequirements(workspaceReal, text) {
  if (!text) return { exists: false, tracks: [], prepItems: [] };
  const tables = parseMarkdownTables(text);
  const trackTable = tables.find(
    (t) => t.headers.some((h) => /track|guide/i.test(h)) && t.headers.some((h) => /fit/i.test(h))
  );
  const reqDir = join(workspaceReal, 'requirements');
  const tracks = [];

  if (trackTable) {
    for (const r of trackTable.rows) {
      const get = (re) => {
        const key = trackTable.headers.find((h) => re.test(h));
        return key ? r.byHeader[key] : '';
      };
      const guideCell = get(/track|guide/i);
      const name = stripMdFormatting(guideCell);
      if (!name || /\{\{/.test(name)) continue;
      const links = extractMdLinks(guideCell);
      let guideUri = null;
      if (links[0]?.href) {
        guideUri = safeWorkspaceUri(workspaceReal, resolvePath(reqDir, links[0].href));
      }
      const policyTrack = stripMdFormatting(get(/policy/i));
      const fit = stripMdFormatting(get(/fit/i));
      const anchors = stripMdFormatting(get(/anchor/i));
      const notes = stripMdFormatting(get(/strength|gap|takeaway/i));
      const isSkip = /reject|skip/i.test(policyTrack);

      tracks.push({ name, policyTrack, fit, anchors, notes, guideUri, isSkip });
    }
  }

  const prepItems = [];
  const prepSection = /##\s+6\.[^\n]*\n([\s\S]*)$/i.exec(text);
  if (prepSection) {
    for (const m of prepSection[1].matchAll(/^\s*\d+\.\s+(.+)$/gm)) {
      const cleaned = stripMdFormatting(m[1]);
      if (cleaned && !/\{\{/.test(cleaned)) prepItems.push(cleaned);
    }
  }

  return { exists: true, tracks, prepItems };
}

function buildSnapshot(requestedWorkspace) {
  const { workspaces, automations } = scanSidecars();
  const candidates = new Map(workspaces.map((w) => [w.path, w]));

  const extraPaths = [];
  if (requestedWorkspace) extraPaths.push(expandHome(requestedWorkspace));
  if (process.env.CAREER_AUTOPILOT_WORKSPACE) extraPaths.push(expandHome(process.env.CAREER_AUTOPILOT_WORKSPACE));

  let activePath = '';
  let workspaceError = '';

  if (requestedWorkspace) {
    const p = expandHome(requestedWorkspace);
    if (isCareerWorkspace(p)) {
      activePath = realpathSync(p);
      if (!candidates.has(activePath)) {
        candidates.set(activePath, { path: activePath, name: basename(activePath), source: 'manual' });
      }
    } else {
      workspaceError = `No Career Autopilot workspace found at "${requestedWorkspace}" (expected GLOBAL_REFERENCE.md or applications/tracker.md).`;
    }
  }

  if (!activePath) {
    for (const p of extraPaths) {
      if (p && isCareerWorkspace(p)) {
        activePath = realpathSync(p);
        if (!candidates.has(activePath)) {
          candidates.set(activePath, { path: activePath, name: basename(activePath), source: 'env' });
        }
        break;
      }
    }
  }

  if (!activePath && workspaces.length > 0) {
    activePath = workspaces[0].path;
  }

  if (!activePath) {
    return {
      workspace: null,
      workspaceError,
      workspaces: [...candidates.values()],
      automations,
      etag: `empty:${automations.map((a) => `${a.id}:${a.mtime}`).join(',')}`,
    };
  }

  const trackerFile = join(activePath, 'applications', 'tracker.md');
  const leadsFile = join(activePath, 'applications', 'new_leads.md');
  const refFile = join(activePath, 'GLOBAL_REFERENCE.md');
  const reqFile = join(activePath, 'requirements', 'README.md');
  const profileFile = join(activePath, 'resume', 'master_profile.md');

  const trackerRaw = readTextSafe(trackerFile);
  const leadsRaw = readTextSafe(leadsFile);
  const refRaw = readTextSafe(refFile);
  const reqRaw = readTextSafe(reqFile);

  const etag = [
    activePath,
    trackerRaw.mtime,
    leadsRaw.mtime,
    refRaw.mtime,
    reqRaw.mtime,
    automations.map((a) => `${a.id}:${a.mtime}:${a.enabled}`).join(','),
  ].join('|');

  const tracker = parseTracker(activePath, trackerRaw.text);
  const globalRef = parseGlobalReference(refRaw.text);
  const newLeads = parseNewLeads(leadsRaw.text);
  const requirements = parseRequirements(activePath, reqRaw.text);

  return {
    workspace: {
      path: activePath,
      name: basename(activePath),
      files: {
        trackerUri: safeWorkspaceUri(activePath, trackerFile),
        leadsUri: safeWorkspaceUri(activePath, leadsFile),
        globalRefUri: safeWorkspaceUri(activePath, refFile),
        requirementsUri: safeWorkspaceUri(activePath, reqFile),
        profileUri: safeWorkspaceUri(activePath, profileFile),
      },
    },
    workspaceError,
    workspaces: [...candidates.values()],
    tracker,
    globalRef,
    newLeads,
    requirements,
    automations,
    updatedAt: new Date().toISOString(),
    etag,
  };
}

// ---------------------------------------------------------------------------
// HTTP routes via Antigravity SidecarApp
// ---------------------------------------------------------------------------

const app = new SidecarApp();

app.page('/', () => readFileSync(join(__dirname, 'index.html'), 'utf-8'));

for (const [route, [file, type]] of Object.entries(STATIC)) {
  app.api(route, () => new Response(readFileSync(join(__dirname, file), 'utf-8'), { contentType: type }), 'GET');
}

app.api(
  '/api/dashboard',
  (data) => {
    const requested = typeof data?.workspace === 'string' ? data.workspace : '';
    const snap = buildSnapshot(requested);
    if (data?.etag && data.etag === snap.etag) {
      return { unchanged: true, etag: snap.etag };
    }
    return snap;
  },
  'GET'
);

app.run();
