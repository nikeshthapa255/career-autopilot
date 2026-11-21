(() => {
  const POLL_MS = 3000;
  const STORAGE_KEY = 'career-autopilot-workspace';
  const THEME_STORAGE_KEY = 'career-autopilot-theme-mode';
  const $ = (id) => document.getElementById(id);

  const state = {
    tab: 'pipeline',
    workspace: '',
    fallbackWorkspace: '',
    hostWorkspaces: [],
    themeMode: 'auto', // auto | dark | light
    etag: '',
    snap: null,
    search: '',
    statusFilter: '',
    tierFilter: '',
    showResolved: false,
    configFormOpen: null, // null = auto (open when 0 active sidecars), boolean = user override
    configDirty: false,
    configFocusRole: '',
    automationNotice: '',
    automationError: '',
  };

  try {
    const savedTheme = localStorage.getItem(THEME_STORAGE_KEY);
    if (savedTheme === 'auto' || savedTheme === 'dark' || savedTheme === 'light') {
      state.themeMode = savedTheme;
    }
  } catch {}

  const params = new URLSearchParams(location.search);
  const urlWs = params.get('workspace');
  if (urlWs) {
    state.workspace = urlWs;
  } else {
    try {
      state.fallbackWorkspace = localStorage.getItem(STORAGE_KEY) || '';
    } catch {
      state.fallbackWorkspace = '';
    }
  }

  function detectHostTheme() {
    const hostBg = getComputedStyle(document.documentElement).getPropertyValue('--background').trim();
    if (hostBg) {
      const probe = document.createElement('span');
      probe.style.cssText = 'position:absolute;visibility:hidden;color:var(--background)';
      document.documentElement.appendChild(probe);
      const c = getComputedStyle(probe).color;
      probe.remove();
      const nums = (c.match(/[\d.]+/g) || []).map(Number);
      if (nums.length >= 3) {
        const scale = c.startsWith('color(') ? 1 : 255;
        const [r, g, b] = nums.slice(0, 3).map((v) => v / scale);
        const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        return lum < 0.5 ? 'dark' : 'light';
      }
    }
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme() {
    const root = document.documentElement;
    if (state.themeMode === 'dark' || state.themeMode === 'light') {
      root.dataset.theme = state.themeMode;
      root.dataset.themeMode = state.themeMode;
    } else {
      delete root.dataset.themeMode;
      root.dataset.theme = detectHostTheme();
    }
    const btn = $('btn-theme');
    if (btn) {
      const label = state.themeMode === 'auto' ? 'Auto' : state.themeMode === 'dark' ? 'Dark' : 'Light';
      btn.textContent = `Theme: ${label}`;
    }
  }

  applyTheme();
  new MutationObserver(applyTheme).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['style'],
  });
  if (window.matchMedia) {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    if (mq.addEventListener) mq.addEventListener('change', applyTheme);
  }

  const esc = (s) =>
    String(s ?? '').replace(/[&<>"']/g, (ch) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
    }[ch]));

  const safeHref = (url) => (/^https?:\/\//i.test(String(url || '')) ? url : '');

  function apiFetch(url, options = {}) {
    const f = window.sidecar?.fetch ? window.sidecar.fetch.bind(window.sidecar) : fetch;
    return f(url, options);
  }

  function openWorkspaceFile(uri) {
    if (!uri) return;
    if (window.sidecar?.ui?.toggleAuxPane) {
      window.sidecar.ui.toggleAuxPane({ tabType: 'fileView', uri });
      return;
    }
    window.open(uri, '_blank', 'noopener,noreferrer');
  }

  async function resolveInitialHostWorkspaces() {
    if (!window.sidecar?.getWorkspaceUris) return [];
    try {
      const uris = await Promise.race([
        window.sidecar.getWorkspaceUris(),
        new Promise((resolve) => setTimeout(() => resolve([]), 250)),
      ]);
      return Array.isArray(uris) ? uris : [];
    } catch {
      return [];
    }
  }

  async function fetchDashboard(force = false) {
    const q = new URLSearchParams();
    if (state.workspace) q.set('workspace', state.workspace);
    else if (state.fallbackWorkspace) q.set('fallbackWorkspace', state.fallbackWorkspace);
    if (state.hostWorkspaces.length) q.set('hostWorkspaces', JSON.stringify(state.hostWorkspaces));
    if (!force && state.etag) q.set('etag', state.etag);
    const res = await apiFetch(`/api/dashboard?${q.toString()}`, { method: 'GET' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  function setTab(next) {
    state.tab = next;
    document.querySelectorAll('.tab').forEach((btn) => {
      const active = btn.dataset.tab === next;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', String(active));
      btn.tabIndex = active ? 0 : -1;
    });
    document.querySelectorAll('.tab-panel').forEach((panel) => {
      panel.classList.toggle('active', panel.id === `tab-${next}`);
    });
  }

  function renderHeader(snap) {
    const select = $('ws-select');
    const list = snap.workspaces || [];
    const activePath = snap.workspace?.path || '';

    select.innerHTML = list.length
      ? list
          .map(
            (w) =>
              `<option value="${esc(w.path)}" ${w.path === activePath ? 'selected' : ''}>${esc(w.name)} (${esc(w.source)})</option>`
          )
          .join('')
      : '<option value="">No workspace loaded</option>';

    const quick = $('quick-files');
    const files = snap.workspace?.files || {};
    const pills = [
      ['Tracker', files.trackerUri],
      ['Ref', files.globalRefUri],
      ['Profile', files.profileUri],
      ['Fit', files.requirementsUri],
    ].filter(([, uri]) => Boolean(uri));

    quick.innerHTML = pills
      .map(
        ([label, uri]) =>
          `<button type="button" class="link-chip" data-file-uri="${esc(uri)}">${esc(label)}</button>`
      )
      .join('');

    const errBanner = $('error-banner');
    if (snap.workspaceError) {
      errBanner.textContent = snap.workspaceError;
      errBanner.classList.remove('hidden');
    } else {
      errBanner.classList.add('hidden');
    }
  }

  function renderPipeline(snap) {
    const counts = snap.tracker?.counts || {};
    $('count-pipeline').textContent = String(counts.total || 0);

    $('kpi-strip').innerHTML = [
      ['Total', counts.total || 0],
      ['Submitted', counts.submitted || 0],
      ['Email Sent', counts.partial || 0],
      ['Ready', counts.ready || 0],
      ['Blocked', counts.blocked || 0],
      ['Queued', counts.queued || 0],
    ]
      .map(
        ([label, num]) =>
          `<div class="kpi"><span class="kpi-num">${num}</span><span class="kpi-label">${esc(label)}</span></div>`
      )
      .join('');

    const term = state.search.trim().toLowerCase();
    const rows = (snap.tracker?.rows || []).filter((r) => {
      if (state.statusFilter && r.bucket !== state.statusFilter) return false;
      if (!term) return true;
      return `${r.company} ${r.role} ${r.status} ${r.comp} ${r.notes}`.toLowerCase().includes(term);
    });

    if (!rows.length) {
      $('pipeline-list').innerHTML = '<div class="empty-inline">No matching applications in tracker.md.</div>';
      return;
    }

    $('pipeline-list').innerHTML = rows
      .map((r) => {
        const actions = [];
        if (r.pdfUri) actions.push(`<button type="button" class="link-chip" data-file-uri="${esc(r.pdfUri)}">PDF</button>`);
        if (r.stateUri) actions.push(`<button type="button" class="link-chip" data-file-uri="${esc(r.stateUri)}">State</button>`);
        if (r.coldEmailUri) actions.push(`<button type="button" class="link-chip" data-file-uri="${esc(r.coldEmailUri)}">Email</button>`);
        const href = safeHref(r.applyUrl);
        if (href) actions.push(`<a class="link-chip" href="${esc(href)}" target="_blank" rel="noopener noreferrer">Job URL</a>`);

        return `
          <article class="card">
            <div class="card-head">
              <div>
                <h3 class="card-title">${esc(r.company)}</h3>
                <p class="card-sub">${esc(r.role)}</p>
              </div>
              <span class="badge badge-${esc(r.bucket)}">${esc(r.status || r.bucket)}</span>
            </div>
            ${r.comp ? `<div class="meta-line">${esc(r.comp)}${r.updated ? ` · ${esc(r.updated)}` : ''}</div>` : ''}
            ${r.notes ? `<p class="card-notes">${esc(r.notes)}</p>` : ''}
            ${actions.length ? `<div class="card-actions">${actions.join('')}</div>` : ''}
          </article>
        `;
      })
      .join('');
  }

  function renderBlockers(snap) {
    const qs = snap.globalRef?.questions || [];
    const openCount = snap.globalRef?.openCount || 0;
    const countEl = $('count-blockers');
    countEl.textContent = String(openCount);
    countEl.classList.toggle('alert', openCount > 0);

    $('blockers-summary').textContent = `${openCount} open · ${qs.length - openCount} resolved`;
    const visible = state.showResolved ? qs : qs.filter((q) => q.isOpen);

    if (!visible.length) {
      $('blockers-list').innerHTML = '<div class="empty-inline">No open HITL blockers in GLOBAL_REFERENCE.md.</div>';
      return;
    }

    $('blockers-list').innerHTML = visible
      .map(
        (q) => `
        <article class="card">
          <div class="card-head">
            <div>
              <h3 class="card-title">${esc(q.id)} · ${esc(q.question)}</h3>
              ${q.affects ? `<p class="card-sub">Affects: ${esc(q.affects)}</p>` : ''}
            </div>
            <span class="badge ${q.isOpen ? 'badge-err' : 'badge-ok'}">${esc(q.status)}</span>
          </div>
          ${q.details ? `<p class="card-notes">${esc(q.details)}</p>` : ''}
          ${q.answer ? `<div class="meta-line"><strong>Answer:</strong> ${esc(q.answer)}</div>` : ''}
        </article>
      `
      )
      .join('');
  }

  function renderLeads(snap) {
    const all = snap.newLeads?.leads || [];
    $('count-leads').textContent = String(all.length);
    $('leads-meta').textContent = snap.newLeads?.latestRun ? `Latest run: ${snap.newLeads.latestRun}` : 'Scout discovery log';

    const filtered = state.tierFilter ? all.filter((l) => l.tier === state.tierFilter) : all;
    if (!filtered.length) {
      $('leads-list').innerHTML = '<div class="empty-inline">No leads recorded for this filter yet. Run <code>career-autopilot-scout</code>.</div>';
      return;
    }

    $('leads-list').innerHTML = filtered
      .map((l) => {
        const href = safeHref(l.url);
        const badgeCls = l.tier === 'Tier A' ? 'badge-ok' : l.tier === 'Tier B1' ? 'badge-info' : 'badge-warn';
        return `
          <article class="card">
            <div class="card-head">
              <div>
                <h3 class="card-title">${esc(l.company)}</h3>
                <p class="card-sub">${esc(l.role)}</p>
              </div>
              <span class="badge ${badgeCls}">${esc(l.tier)}</span>
            </div>
            <div class="meta-line">${esc([l.comp, l.geo, l.fit ? `Fit: ${l.fit}` : ''].filter(Boolean).join(' · '))}</div>
            ${l.gates ? `<p class="card-notes">${esc(l.gates)}</p>` : ''}
            ${href ? `<div class="card-actions"><a class="link-chip" href="${esc(href)}" target="_blank" rel="noopener noreferrer">Open posting</a></div>` : ''}
          </article>
        `;
      })
      .join('');
  }

  function renderFit(snap) {
    const req = snap.requirements || { exists: false, tracks: [], prepItems: [] };
    $('count-fit').textContent = String(req.tracks.length);

    if (!req.exists) {
      $('fit-content').innerHTML = `
        <div class="empty-inline">
          <p><strong>Optional role-fit rubric not created yet.</strong></p>
          <p>Ask Antigravity to run <code>career-autopilot-fit</code> to build <code>requirements/README.md</code>, a dual-track 80%+ rubric, instant-skip mismatch filters, and an interview prep queue.</p>
        </div>
      `;
      return;
    }

    const trackCards = req.tracks
      .map(
        (t) => `
        <article class="card">
          <div class="card-head">
            <div>
              <h3 class="card-title">${esc(t.name)}</h3>
              <p class="card-sub">${esc(t.policyTrack)}</p>
            </div>
            <span class="badge ${t.isSkip ? 'badge-err' : 'badge-ok'}">${esc(t.fit || (t.isSkip ? 'Skip' : 'Pass'))}</span>
          </div>
          ${t.anchors ? `<div class="meta-line"><strong>Anchors:</strong> ${esc(t.anchors)}</div>` : ''}
          ${t.notes ? `<p class="card-notes">${esc(t.notes)}</p>` : ''}
          ${t.guideUri ? `<div class="card-actions"><button type="button" class="link-chip" data-file-uri="${esc(t.guideUri)}">Open track guide</button></div>` : ''}
        </article>
      `
      )
      .join('');

    const prepHtml = req.prepItems.length
      ? `
        <h2 class="subheading">High-ROI prep queue</h2>
        <div class="card">
          <ol class="prep-list">${req.prepItems.map((item) => `<li>${esc(item)}</li>`).join('')}</ol>
        </div>
      `
      : '';

    $('fit-content').innerHTML = `<div class="card-list">${trackCards || '<div class="empty-inline">No tracks parsed in requirements/README.md.</div>'}</div>${prepHtml}`;
  }

  // ---------------------------------------------------------------------------
  // Automations View & Inline Sidecar Configurator
  // ---------------------------------------------------------------------------

  function syncPresetToInput(selectEl, inputEl) {
    if (!selectEl || !inputEl) return;
    const val = inputEl.value.trim().replace(/\s+/g, ' ');
    const match = [...selectEl.options].find((o) => o.value !== 'custom' && o.value === val);
    selectEl.value = match ? match.value : 'custom';
  }

  function resolveTargetSidecarIds(snap, prefix) {
    const roles = snap?.automationPanel?.roles || [];
    const targetIds = {};
    for (const r of roles) {
      const sc = r.sidecar;
      if (r.configured && sc?.id && (!sc.prefix || sc.prefix === prefix)) {
        targetIds[r.role] = sc.id;
      }
    }
    return targetIds;
  }

  function updateConfigFormControls() {
    const findChecked = $('cfg-role-find').checked;
    const applyChecked = $('cfg-role-apply').checked;
    $('cfg-scout-group').classList.toggle('hidden', !findChecked);
    $('cfg-apply-group').classList.toggle('hidden', !applyChecked);

    const prefix = $('cfg-prefix').value.trim();
    const previewEl = $('cfg-prefix-preview');
    if (!prefix) {
      previewEl.textContent = 'Enter a lowercase prefix (e.g. my-jobs)';
    } else if (!/^[a-z0-9][a-z0-9-]{0,30}$/.test(prefix)) {
      previewEl.textContent = 'Use lowercase letters, numbers, and hyphens only (start with letter/number).';
    } else {
      const existingTargets = resolveTargetSidecarIds(state.snap, prefix);
      const ids = [];
      if (findChecked) ids.push(existingTargets['find-jobs'] || `${prefix}-find-jobs`);
      if (applyChecked) ids.push(existingTargets['auto-apply'] || `${prefix}-auto-apply`);
      previewEl.textContent = ids.length ? `Sidecars: ${ids.join(', ')}` : 'Select at least one automation above.';
    }

    const emailMode = $('cfg-email-mode').value;
    $('cfg-email').classList.toggle('hidden', emailMode !== 'gmail');
  }

  function populateConfigForm(snap, focusRole = '') {
    const panel = snap?.automationPanel || {};
    const defaults = panel.suggestedDefaults || {};
    const roles = panel.roles || [];
    const findSidecar = roles.find((r) => r.role === 'find-jobs')?.sidecar || null;
    const applySidecar = roles.find((r) => r.role === 'auto-apply')?.sidecar || null;

    if (focusRole === 'find-jobs') {
      $('cfg-role-find').checked = true;
      $('cfg-role-apply').checked = Boolean(applySidecar);
    } else if (focusRole === 'auto-apply') {
      $('cfg-role-find').checked = Boolean(findSidecar);
      $('cfg-role-apply').checked = true;
    } else if (findSidecar || applySidecar) {
      $('cfg-role-find').checked = Boolean(findSidecar);
      $('cfg-role-apply').checked = Boolean(applySidecar);
    } else {
      $('cfg-role-find').checked = true;
      $('cfg-role-apply').checked = true;
    }

    const prefix =
      (focusRole === 'find-jobs' && findSidecar?.prefix) ||
      (focusRole === 'auto-apply' && applySidecar?.prefix) ||
      findSidecar?.prefix ||
      applySidecar?.prefix ||
      defaults.prefix ||
      'career';
    $('cfg-prefix').value = prefix;

    const tz =
      (focusRole === 'find-jobs' && findSidecar?.tz) ||
      (focusRole === 'auto-apply' && applySidecar?.tz) ||
      findSidecar?.tz ||
      applySidecar?.tz ||
      defaults.timezone ||
      'UTC';
    $('cfg-tz').value = tz;

    $('cfg-scout-cron').value = findSidecar?.cron || defaults.scoutCron || '0 8 * * *';
    $('cfg-apply-cron').value = applySidecar?.cron || defaults.applyCron || '0 9 * * *';
    syncPresetToInput($('cfg-scout-preset'), $('cfg-scout-cron'));
    syncPresetToInput($('cfg-apply-preset'), $('cfg-apply-cron'));

    const existingEmail =
      applySidecar && applySidecar.emailAccount && applySidecar.emailAccount !== 'none' && applySidecar.emailAccount !== 'configured'
        ? applySidecar.emailAccount
        : defaults.emailAccount && defaults.emailAccount !== 'none'
          ? defaults.emailAccount
          : '';
    if (existingEmail) {
      $('cfg-email-mode').value = 'gmail';
      $('cfg-email').value = existingEmail;
    } else {
      $('cfg-email-mode').value = 'none';
      $('cfg-email').value = '';
    }

    $('cfg-form-title').textContent =
      panel.activeWorkspaceCount > 0
        ? `Reconfigure automations for ${snap.workspace?.name || 'workspace'}`
        : `Configure automations for ${snap.workspace?.name || 'workspace'}`;

    $('cfg-cli-fallback').classList.add('hidden');
    updateConfigFormControls();
  }

  function shellQuote(val) {
    return `'${String(val ?? '').replace(/'/g, `'\\''`)}'`;
  }

  function buildCliCommand(snap) {
    const wsPath = snap?.workspace?.path || state.workspace || '/path/to/workspace';
    const installer = snap?.automationPanel?.cliInstallerPath || '';
    if (!installer) return '';
    const prefix = $('cfg-prefix').value.trim() || 'career';
    const tz = $('cfg-tz').value.trim() || 'UTC';
    const scoutCron = $('cfg-scout-cron').value.trim() || '0 8 * * *';
    const applyCron = $('cfg-apply-cron').value.trim() || '0 9 * * *';
    const emailMode = $('cfg-email-mode').value;
    const emailVal = emailMode === 'gmail' ? $('cfg-email').value.trim() : '';

    const parts = [
      shellQuote(installer),
      '--workspace', shellQuote(wsPath),
      '--prefix', shellQuote(prefix),
      '--tz', shellQuote(tz),
      '--scout-cron', shellQuote(scoutCron),
      '--apply-cron', shellQuote(applyCron),
    ];
    if (emailVal) {
      parts.push('--email', shellQuote(emailVal));
    } else {
      parts.push('--no-gmail');
    }
    parts.push('--non-interactive');
    return parts.join(' ');
  }

  function renderAutomations(snap) {
    const p = snap.globalRef?.policy || {};
    $('policy-card').innerHTML = `
      <div class="card-head">
        <h3 class="card-title">Active workspace guardrails</h3>
        <span class="badge badge-info">${esc(p.timezone || 'UTC')}</span>
      </div>
      <div class="policy-grid">
        <div class="policy-item"><span class="policy-key">Web apply mode</span><span class="policy-val">${esc(p.webApplyMode || 'hitl_pre_submit')}</span></div>
        <div class="policy-item"><span class="policy-key">Cold email</span><span class="policy-val">${esc(p.outreachMode || 'hitl_strict')}</span></div>
        <div class="policy-item"><span class="policy-key">Phone policy</span><span class="policy-val">${esc(p.phonePolicy || 'omit_optional')}</span></div>
        <div class="policy-item"><span class="policy-key">Comp floor</span><span class="policy-val">${esc(p.compFloor || 'Not set')}</span></div>
      </div>
    `;

    const panel = snap.automationPanel || { activeWorkspaceCount: 0, roles: [], otherWorkspaceSidecars: [] };
    const activeCount = panel.activeWorkspaceCount || 0;
    $('count-automations').textContent = String(activeCount);

    const formOpen = state.configFormOpen === null ? activeCount === 0 : state.configFormOpen;
    $('automation-config-card').classList.toggle('hidden', !formOpen);
    $('btn-toggle-configure').textContent = formOpen ? 'Hide Form' : activeCount > 0 ? 'Reconfigure' : 'Configure';
    $('btn-copy-cli').classList.toggle('hidden', !panel.cliInstallerPath);

    const noticeEl = $('automation-notice');
    if (state.automationNotice) {
      noticeEl.textContent = state.automationNotice;
      noticeEl.classList.remove('hidden');
    } else {
      noticeEl.classList.add('hidden');
    }

    const errEl = $('cfg-form-error');
    if (state.automationError) {
      errEl.textContent = state.automationError;
      errEl.classList.remove('hidden');
    } else {
      errEl.classList.add('hidden');
    }

    if (!state.configDirty) {
      populateConfigForm(snap, state.configFocusRole);
    }

    const roles = panel.roles || [];
    const wsName = snap.workspace?.name || 'this workspace';
    $('automations-list').innerHTML = roles
      .map((r) => {
        if (r.configured && r.sidecar) {
          const s = r.sidecar;
          const badgeCls = s.statusCode === 'enabled' ? 'badge-ok' : 'badge-warn';
          const rendererName = s.rendererPath ? s.rendererPath.split(/[\\/]/).pop() : '';
          const outreachLabel =
            s.role === 'auto-apply'
              ? s.emailAccount && s.emailAccount !== 'none'
                ? `Gmail draft (${s.emailAccount})`
                : 'Markdown dossier only (no Gmail)'
              : '';
          return `
            <article class="card">
              <div class="card-head">
                <div>
                  <h3 class="card-title">${esc(s.displayName || r.title)}</h3>
                  <p class="card-sub"><code>${esc(s.id)}</code></p>
                </div>
                <span class="badge ${badgeCls}">${esc(s.status)}</span>
              </div>
              <div class="kv-list">
                <div class="kv-row"><span class="kv-key">Schedule</span><span><code>${esc(s.cron || s.schedule)}</code>${s.tz ? ` · ${esc(s.tz)}` : ''}</span></div>
                ${outreachLabel ? `<div class="kv-row"><span class="kv-key">Outreach</span><span>${esc(outreachLabel)}</span></div>` : ''}
                ${rendererName ? `<div class="kv-row"><span class="kv-key">Renderer</span><span><code>${esc(rendererName)}</code></span></div>` : ''}
              </div>
              ${r.additionalCount > 0 ? `<div class="meta-line">Warning: ${r.additionalCount} additional sidecar(s) for this role target this workspace.</div>` : ''}
              <div class="card-actions">
                <button type="button" class="icon-btn" data-configure-role="${esc(r.role)}">Reconfigure</button>
                ${s.configUri ? `<button type="button" class="link-chip" data-file-uri="${esc(s.configUri)}">Inspect sidecar.json</button>` : ''}
              </div>
            </article>
          `;
        }

        const otherHint =
          r.otherWorkspaces && r.otherWorkspaces.length
            ? `Existing config targets another workspace (${r.otherWorkspaces.map((o) => o.workspaceName).join(', ')}).`
            : `No scheduled sidecar configured for ${wsName} yet.`;
        return `
          <article class="card card-unconfigured">
            <div class="card-head">
              <div>
                <h3 class="card-title">${esc(r.title)}</h3>
                <p class="card-sub">${esc(r.subtitle)}</p>
              </div>
              <span class="badge badge-skipped">Not Configured</span>
            </div>
            <p class="card-notes">${esc(otherHint)}</p>
            <div class="card-actions">
              <button type="button" class="icon-btn" data-configure-role="${esc(r.role)}">Configure</button>
            </div>
          </article>
        `;
      })
      .join('');

    const others = panel.otherWorkspaceSidecars || [];
    const otherWrap = $('other-automations-wrap');
    otherWrap.classList.toggle('hidden', others.length === 0);
    if (others.length) {
      $('other-automations-list').innerHTML = others
        .map(
          (o) => `
          <article class="card">
            <div class="card-head">
              <div>
                <h3 class="card-title">${esc(o.displayName)}</h3>
                <p class="card-sub"><code>${esc(o.id)}</code> · ${esc(o.otherWorkspaceName)}</p>
              </div>
              <span class="badge badge-info">Other Workspace</span>
            </div>
            <div class="kv-list">
              <div class="kv-row"><span class="kv-key">Target</span><span>${esc(o.otherWorkspacePath)}</span></div>
              ${o.cron || o.schedule ? `<div class="kv-row"><span class="kv-key">Schedule</span><span><code>${esc(o.cron || o.schedule)}</code>${o.tz ? ` · ${esc(o.tz)}` : ''}</span></div>` : ''}
            </div>
            ${o.configUri ? `<div class="card-actions"><button type="button" class="link-chip" data-file-uri="${esc(o.configUri)}">Inspect sidecar.json</button></div>` : ''}
          </article>
        `
        )
        .join('');
    }
  }

  function renderAll(snap) {
    renderHeader(snap);
    const hasWs = Boolean(snap.workspace);
    $('empty-state').classList.toggle('hidden', hasWs);
    document.querySelectorAll('.tab-panel').forEach((el) => {
      el.classList.toggle('hidden', !hasWs);
    });
    if (!hasWs) {
      $('count-automations').textContent = String((snap.automations || []).length);
      return;
    }
    renderPipeline(snap);
    renderBlockers(snap);
    renderLeads(snap);
    renderFit(snap);
    renderAutomations(snap);
  }

  async function poll(force = false) {
    try {
      const data = await fetchDashboard(force);
      $('live-label').textContent = 'Live';
      if (data.unchanged) return;
      state.etag = data.etag || '';
      state.snap = data;
      if (data.workspace?.path && !state.workspace) {
        state.workspace = data.workspace.path;
      }
      renderAll(data);
    } catch (err) {
      $('live-label').textContent = 'Offline';
      console.error('[career-autopilot-dashboard]', err);
    }
  }

  // Event wiring
  document.querySelector('.tabs').addEventListener('click', (e) => {
    const btn = e.target.closest('.tab');
    if (btn?.dataset.tab) setTab(btn.dataset.tab);
  });

  document.querySelector('.tabs').addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
    const tabs = [...document.querySelectorAll('.tab')];
    const idx = tabs.findIndex((t) => t.dataset.tab === state.tab);
    if (idx < 0) return;
    const nextIdx = (idx + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length;
    setTab(tabs[nextIdx].dataset.tab);
    tabs[nextIdx].focus();
  });

  document.body.addEventListener('click', (e) => {
    const fileBtn = e.target.closest('[data-file-uri]');
    if (fileBtn) {
      openWorkspaceFile(fileBtn.dataset.fileUri);
      return;
    }
    const cfgBtn = e.target.closest('[data-configure-role]');
    if (cfgBtn) {
      const role = cfgBtn.dataset.configureRole;
      state.configFormOpen = true;
      state.configDirty = false;
      state.configFocusRole = role;
      state.automationError = '';
      if (state.snap) {
        renderAutomations(state.snap);
      }
      $('cfg-prefix').focus();
    }
  });

  $('ws-select').addEventListener('change', (e) => {
    state.workspace = e.target.value;
    state.etag = '';
    state.configFormOpen = null;
    state.configDirty = false;
    state.configFocusRole = '';
    state.automationNotice = '';
    state.automationError = '';
    try { localStorage.setItem(STORAGE_KEY, state.workspace); } catch {}
    poll(true);
  });

  $('btn-path').addEventListener('click', () => {
    const drawer = $('path-drawer');
    const open = drawer.classList.toggle('hidden');
    $('btn-path').setAttribute('aria-expanded', String(!open));
    if (!open) {
      $('ws-input').value = state.workspace || state.snap?.workspace?.path || '';
      $('ws-input').focus();
    }
  });

  $('path-drawer').addEventListener('submit', (e) => {
    e.preventDefault();
    const val = $('ws-input').value.trim();
    if (!val) return;
    state.workspace = val;
    state.etag = '';
    state.configFormOpen = null;
    state.configDirty = false;
    state.configFocusRole = '';
    state.automationNotice = '';
    state.automationError = '';
    try { localStorage.setItem(STORAGE_KEY, val); } catch {}
    $('path-drawer').classList.add('hidden');
    $('btn-path').setAttribute('aria-expanded', 'false');
    poll(true);
  });

  $('btn-theme').addEventListener('click', () => {
    const order = ['auto', 'dark', 'light'];
    state.themeMode = order[(order.indexOf(state.themeMode) + 1) % order.length];
    try { localStorage.setItem(THEME_STORAGE_KEY, state.themeMode); } catch {}
    applyTheme();
  });

  $('btn-refresh').addEventListener('click', () => poll(true));
  $('pipeline-search').addEventListener('input', (e) => {
    state.search = e.target.value;
    if (state.snap) renderPipeline(state.snap);
  });
  $('pipeline-filter').addEventListener('change', (e) => {
    state.statusFilter = e.target.value;
    if (state.snap) renderPipeline(state.snap);
  });
  $('show-resolved').addEventListener('change', (e) => {
    state.showResolved = e.target.checked;
    if (state.snap) renderBlockers(state.snap);
  });
  $('leads-tier-filter').addEventListener('change', (e) => {
    state.tierFilter = e.target.value;
    if (state.snap) renderLeads(state.snap);
  });

  // Configurator event wiring
  $('btn-toggle-configure').addEventListener('click', () => {
    const currentlyOpen = !$('automation-config-card').classList.contains('hidden');
    state.configFormOpen = !currentlyOpen;
    state.automationError = '';
    if (!currentlyOpen) {
      state.configDirty = false;
      state.configFocusRole = '';
    }
    if (state.snap) renderAutomations(state.snap);
  });

  $('btn-cancel-config').addEventListener('click', () => {
    state.configFormOpen = false;
    state.configDirty = false;
    state.configFocusRole = '';
    state.automationError = '';
    if (state.snap) renderAutomations(state.snap);
  });

  $('cfg-scout-preset').addEventListener('change', (e) => {
    if (e.target.value !== 'custom') {
      $('cfg-scout-cron').value = e.target.value;
    }
    state.configDirty = true;
  });

  $('cfg-apply-preset').addEventListener('change', (e) => {
    if (e.target.value !== 'custom') {
      $('cfg-apply-cron').value = e.target.value;
    }
    state.configDirty = true;
  });

  $('cfg-scout-cron').addEventListener('input', () => {
    syncPresetToInput($('cfg-scout-preset'), $('cfg-scout-cron'));
    state.configDirty = true;
  });

  $('cfg-apply-cron').addEventListener('input', () => {
    syncPresetToInput($('cfg-apply-preset'), $('cfg-apply-cron'));
    state.configDirty = true;
  });

  ['cfg-role-find', 'cfg-role-apply', 'cfg-prefix', 'cfg-tz', 'cfg-email-mode', 'cfg-email'].forEach((id) => {
    const el = $(id);
    if (!el) return;
    const evt = el.tagName === 'SELECT' || el.type === 'checkbox' ? 'change' : 'input';
    el.addEventListener(evt, () => {
      state.configDirty = true;
      state.automationError = '';
      $('cfg-form-error').classList.add('hidden');
      updateConfigFormControls();
    });
  });

  $('cfg-email-mode').addEventListener('change', (e) => {
    if (e.target.value === 'gmail' && !$('cfg-email').value) {
      const suggested = state.snap?.automationPanel?.suggestedDefaults?.emailAccount;
      if (suggested && suggested !== 'none') $('cfg-email').value = suggested;
      $('cfg-email').focus();
    }
  });

  $('btn-copy-cli').addEventListener('click', async () => {
    const cmd = buildCliCommand(state.snap);
    if (!cmd) return;
    const btn = $('btn-copy-cli');
    const fallback = $('cfg-cli-fallback');
    let copied = false;
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(cmd);
        copied = true;
      }
    } catch {
      copied = false;
    }
    if (!copied) {
      const ta = document.createElement('textarea');
      ta.value = cmd;
      ta.setAttribute('readonly', '');
      ta.style.cssText = 'position:fixed;opacity:0';
      document.body.appendChild(ta);
      ta.select();
      try {
        copied = document.execCommand('copy');
      } catch {
        copied = false;
      }
      ta.remove();
    }
    fallback.textContent = cmd;
    fallback.classList.remove('hidden');
    if (copied) {
      btn.textContent = 'Copied CLI Command';
      setTimeout(() => { btn.textContent = 'Copy CLI Install Command'; }, 2000);
    }
  });

  $('automation-config-card').addEventListener('submit', async (e) => {
    e.preventDefault();
    const wsPath = state.snap?.workspace?.path || state.workspace;
    const roles = [];
    if ($('cfg-role-find').checked) roles.push('find-jobs');
    if ($('cfg-role-apply').checked) roles.push('auto-apply');

    const prefix = $('cfg-prefix').value.trim().toLowerCase();
    const existingTargets = resolveTargetSidecarIds(state.snap, prefix);
    const targetIds = {};
    for (const role of roles) {
      if (existingTargets[role]) targetIds[role] = existingTargets[role];
    }

    const payload = {
      workspace: wsPath,
      prefix,
      roles,
      timezone: $('cfg-tz').value.trim(),
      scoutCron: $('cfg-scout-cron').value.trim(),
      applyCron: $('cfg-apply-cron').value.trim(),
      emailAccount: $('cfg-email-mode').value === 'gmail' ? $('cfg-email').value.trim() : 'none',
    };
    if (Object.keys(targetIds).length) {
      payload.targetIds = targetIds;
    }

    const saveBtn = $('btn-save-config');
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving...';
    state.automationError = '';

    try {
      const res = await apiFetch('/api/automations/configure', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        state.automationError = data?.error || `Failed with HTTP ${res.status}`;
        if (state.snap) renderAutomations(state.snap);
        return;
      }

      const names = (data.written || []).map((w) => w.displayName).join(' and ');
      state.configDirty = false;
      state.configFormOpen = false;
      state.configFocusRole = '';
      state.automationError = '';
      state.automationNotice = `Saved ${names}. Enable the new sidecar(s) in Antigravity Extensions / Sidecars to run them on schedule.`;
      if (data.snapshot) {
        state.snap = data.snapshot;
        state.etag = data.snapshot.etag || '';
        renderAll(data.snapshot);
      } else {
        await poll(true);
      }
    } catch (err) {
      state.automationError = err?.message || 'Unable to save sidecar configs.';
      if (state.snap) renderAutomations(state.snap);
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save Sidecar Configs';
    }
  });

  if (window.sidecar?.onWorkspaceChange) {
    window.sidecar.onWorkspaceChange((uris) => {
      state.hostWorkspaces = Array.isArray(uris) ? uris : [];
      state.etag = '';
      poll(true);
    });
  }

  (async () => {
    state.hostWorkspaces = await resolveInitialHostWorkspaces();
    await poll(true);
    setInterval(() => poll(false), POLL_MS);
  })();
})();
