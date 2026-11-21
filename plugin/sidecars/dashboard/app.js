(() => {
  const POLL_MS = 3000;
  const STORAGE_KEY = 'career-autopilot-workspace';
  const THEME_STORAGE_KEY = 'career-autopilot-theme-mode';
  const $ = (id) => document.getElementById(id);

  const state = {
    tab: 'pipeline',
    workspace: '',
    themeMode: 'auto', // auto | dark | light
    etag: '',
    snap: null,
    search: '',
    statusFilter: '',
    tierFilter: '',
    showResolved: false,
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
      state.workspace = localStorage.getItem(STORAGE_KEY) || '';
    } catch {
      state.workspace = '';
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

  function openWorkspaceFile(uri) {
    if (!uri) return;
    if (window.sidecar?.ui?.toggleAuxPane) {
      window.sidecar.ui.toggleAuxPane({ tabType: 'fileView', uri });
      return;
    }
    window.open(uri, '_blank', 'noopener,noreferrer');
  }

  async function fetchDashboard(force = false) {
    const q = new URLSearchParams();
    if (state.workspace) q.set('workspace', state.workspace);
    if (!force && state.etag) q.set('etag', state.etag);
    const f = window.sidecar?.fetch ? window.sidecar.fetch.bind(window.sidecar) : fetch;
    const res = await f(`/api/dashboard?${q.toString()}`, { method: 'GET' });
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

  function renderAutomations(snap) {
    const p = snap.globalRef?.policy || {};
    $('policy-card').innerHTML = `
      <div class="card-head">
        <h3 class="card-title">Active workspace guardrails</h3>
        <span class="badge badge-info">${esc(p.timezone || 'Asia/Kolkata')}</span>
      </div>
      <div class="policy-grid">
        <div class="policy-item"><span class="policy-key">Web apply mode</span><span class="policy-val">${esc(p.webApplyMode || 'hitl_pre_submit')}</span></div>
        <div class="policy-item"><span class="policy-key">Cold email</span><span class="policy-val">${esc(p.outreachMode || 'hitl_strict')}</span></div>
        <div class="policy-item"><span class="policy-key">Phone policy</span><span class="policy-val">${esc(p.phonePolicy || 'omit_optional')}</span></div>
        <div class="policy-item"><span class="policy-key">Comp floor</span><span class="policy-val">${esc(p.compFloor || 'Not set')}</span></div>
      </div>
    `;

    const autos = snap.automations || [];
    $('count-automations').textContent = String(autos.length);
    if (!autos.length) {
      $('automations-list').innerHTML = `
        <div class="empty-inline">
          No scheduled Career Autopilot sidecars installed yet.<br>
          Run <code>automations/install-sidecars.sh --workspace &lt;dir&gt;</code>, then enable them from Antigravity Automations.
        </div>
      `;
      return;
    }

    $('automations-list').innerHTML = autos
      .map((a) => {
        const stateLabel = a.enabled === true ? 'Enabled' : a.enabled === false ? 'Disabled' : 'Configured';
        const badgeCls = a.enabled === true ? 'badge-ok' : a.enabled === false ? 'badge-warn' : 'badge-info';
        return `
          <article class="card">
            <div class="card-head">
              <div>
                <h3 class="card-title">${esc(a.displayName)}</h3>
                <p class="card-sub"><code>${esc(a.id)}</code></p>
              </div>
              <span class="badge ${badgeCls}">${esc(stateLabel)}</span>
            </div>
            ${a.schedule ? `<div class="meta-line">Schedule: <code>${esc(a.schedule)}</code></div>` : ''}
            ${a.description ? `<p class="card-notes">${esc(a.description)}</p>` : ''}
            ${a.configUri ? `<div class="card-actions"><button type="button" class="link-chip" data-file-uri="${esc(a.configUri)}">Inspect sidecar.json</button></div>` : ''}
          </article>
        `;
      })
      .join('');
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
    const btn = e.target.closest('[data-file-uri]');
    if (btn) openWorkspaceFile(btn.dataset.fileUri);
  });

  $('ws-select').addEventListener('change', (e) => {
    state.workspace = e.target.value;
    state.etag = '';
    try { localStorage.setItem(STORAGE_KEY, state.workspace); } catch {}
    poll(true);
  });

  $('btn-path').addEventListener('click', () => {
    const drawer = $('path-drawer');
    const open = drawer.classList.toggle('hidden');
    $('btn-path').setAttribute('aria-expanded', String(!open));
    if (!open) {
      $('ws-input').value = state.workspace || '';
      $('ws-input').focus();
    }
  });

  $('path-drawer').addEventListener('submit', (e) => {
    e.preventDefault();
    const val = $('ws-input').value.trim();
    if (!val) return;
    state.workspace = val;
    state.etag = '';
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

  poll(true);
  setInterval(() => poll(false), POLL_MS);
})();
