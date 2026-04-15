function renderConnections() {
  const os=currentOS();
  return `<div class="screen active"><div class="window ${os}-chrome">${titlebar(os,'rawenv — Connections')}<div class="gui-layout">${sidebar()}
    <div class="main-content">
      <div class="content-header"><h1>🔌 Connection Manager</h1><div class="content-meta">Detected connections from .env and config files</div></div>
      <div style="padding:16px 24px">
        <div class="conn-card">
          <div class="conn-header"><span class="svc-name">DATABASE_URL</span><span class="badge badge-local">Local replacement</span></div>
          <div class="conn-detail"><span class="t-muted">Original:</span> <span class="mono">postgres://user:pass@rds.amazonaws.com:5432/prod</span></div>
          <div class="conn-detail"><span class="t-muted">Local:</span> <span class="mono" style="color:var(--success)">postgres://myapp:****@localhost:5432/myapp_dev</span></div>
          <div class="conn-actions"><button class="btn btn-sm btn-secondary" data-testid="conn-remote-db">Use Remote</button><button class="btn btn-sm btn-primary" data-testid="conn-local-db">Use Local ✓</button><button class="btn btn-sm btn-secondary" data-testid="conn-proxy-db">Proxy Remote</button></div>
        </div>
        <div class="conn-card">
          <div class="conn-header"><span class="svc-name">REDIS_URL</span><span class="badge badge-local">Local replacement</span></div>
          <div class="conn-detail"><span class="t-muted">Original:</span> <span class="mono">redis://elasticache.amazonaws.com:6379</span></div>
          <div class="conn-detail"><span class="t-muted">Local:</span> <span class="mono" style="color:var(--success)">redis://localhost:6379</span></div>
          <div class="conn-actions"><button class="btn btn-sm btn-secondary">Use Remote</button><button class="btn btn-sm btn-primary">Use Local ✓</button></div>
        </div>
        <div class="conn-card">
          <div class="conn-header"><span class="svc-name">MEILISEARCH_URL</span><span class="badge badge-remote">Remote (proxied)</span></div>
          <div class="conn-detail"><span class="t-muted">Remote:</span> <span class="mono">https://ms.myapp.com:7700</span></div>
          <div class="conn-detail"><span class="t-muted">Proxy:</span> <span class="mono" style="color:var(--info)">localhost:7700 → ms.myapp.com:7700</span></div>
          <div class="conn-actions"><button class="btn btn-sm btn-primary">Proxy ✓</button><button class="btn btn-sm btn-secondary">Use Local</button></div>
        </div>
        <div class="conn-card">
          <div class="conn-header"><span class="svc-name">S3_ENDPOINT</span><span class="badge badge-remote">Remote</span></div>
          <div class="conn-detail"><span class="t-muted">Remote:</span> <span class="mono">s3.amazonaws.com</span></div>
          <div class="conn-detail"><span class="t-muted">Alternative:</span> <span class="mono" style="color:var(--text-muted)">MinIO (local S3-compatible)</span></div>
          <div class="conn-actions"><button class="btn btn-sm btn-primary">Keep Remote ✓</button><button class="btn btn-sm btn-secondary">Install MinIO</button></div>
        </div>
      </div>
    </div></div></div></div>`;
}

function renderUninstall() {
  const os=currentOS();
  return `<div class="screen active"><div class="installer-window" style="width:500px">${titlebar(os,'rawenv — Uninstall')}<div class="installer-body">
    <div class="installer-logo">👋</div>
    <div class="installer-title">Uninstall rawenv</div>
    <div class="installer-sub">Choose what to remove. Your project files are never touched.</div>
    <div class="installer-content" style="text-align:left">
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(true)}<div><div class="setting-label">Remove rawenv binary</div><div class="setting-desc">~/.rawenv/bin/rawenv (10MB)</div></div></div>
      </div>
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(true)}<div><div class="setting-label">Remove installed packages</div><div class="setting-desc">~/.rawenv/store/ (1.2GB)</div></div></div>
      </div>
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(true)}<div><div class="setting-label">Stop and remove services</div><div class="setting-desc">${os==='macos'?'launchd plists':os==='linux'?'systemd units':'Windows Services'}</div></div></div>
      </div>
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(true)}<div><div class="setting-label">Remove service data</div><div class="setting-desc">.rawenv/data/ in each project (databases, caches)</div></div></div>
      </div>
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(false)}<div><div class="setting-label">Remove configuration</div><div class="setting-desc">rawenv.toml, .rawenv/theme.toml (keep for reinstall)</div></div></div>
      </div>
      <div class="uninstall-option" onclick="this.classList.toggle('selected')">
        <div style="display:flex;align-items:center;gap:12px">${toggle(true)}<div><div class="setting-label">Remove DNS and proxy</div><div class="setting-desc">${os==='macos'?'dnsmasq config':os==='linux'?'resolved config':'Acrylic DNS config'}, .test domains</div></div></div>
      </div>
    </div>
    <div class="installer-actions"><button class="btn btn-secondary" data-testid="uninstall-cancel" onclick="navigate('gui-settings')">Cancel</button><button class="btn btn-primary" data-testid="uninstall-confirm" style="background:var(--error)">Uninstall Selected</button></div>
  </div></div>`;
}
