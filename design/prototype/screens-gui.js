// GUI screens with full settings
window._settingsPage = 'general';

window._dashTab=0;
function dashTabContent() {
  const s=SERVICES[window._selectedSvc];
  const t=window._dashTab;
  if(t===0) return `<div class="log-viewer">${logHTML()}</div>
    <div class="conn-bar"><span class="mono">postgresql://myapp:****@localhost:${s.port}/myapp_dev</span><button class="btn btn-primary btn-sm" onclick="this.textContent='Copied!';setTimeout(()=>this.textContent='Copy',1500)">Copy</button></div>`;

  if(t===1) { // Config
    const cfgs=[['port',s.port,'integer','1-65535'],['max_connections','20','integer','1-262143'],['shared_buffers','64MB','size','128kB-8GB'],['work_mem','4MB','size','64kB-2GB'],['effective_cache_size','256MB','size','8kB-8TB'],['log_destination','stderr','enum','stderr, csvlog, jsonlog'],['data_directory','.rawenv/data/'+s.name.toLowerCase()+'/','path','—']];
    return `<div style="padding:16px 24px">
      <div style="display:flex;justify-content:space-between;margin-bottom:12px">
        <span style="font-weight:600">Configuration — ${s.name}</span>
        <div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary" onclick="window._settingsPage='services';navigate('gui-settings')">Full Editor</button><button class="btn btn-sm btn-secondary">Edit Raw File</button></div>
      </div>
      ${cfgs.map(([k,v,type,range])=>`<div class="setting-row">
        <div><div class="setting-label mono" style="color:var(--accent)">${k}</div><div class="setting-desc">${type} · range: ${range}</div></div>
        <input class="setting-input" value="${v}" style="width:${type==='path'?'250px':'100px'}">
      </div>`).join('')}
      <div style="margin-top:12px;display:flex;gap:6px"><button class="btn btn-sm btn-primary">Save & Restart</button><button class="btn btn-sm btn-secondary">Reset to defaults</button></div>
    </div>`;
  }

  if(t===2) { // Connection
    const connStr=s.name==='PostgreSQL'?'postgresql://myapp:****@localhost:5432/myapp_dev':s.name==='Redis'?'redis://localhost:6379/0':s.name==='Meilisearch'?'http://localhost:7700':s.name==='Node.js'?'http://localhost:3000':'mssql://sa:****@localhost:1433/myapp';
    const envVar=s.name==='PostgreSQL'?'DATABASE_URL':s.name==='Redis'?'REDIS_URL':s.name==='Meilisearch'?'MEILISEARCH_URL':s.name==='Node.js'?'APP_URL':'MSSQL_URL';
    return `<div style="padding:16px 24px">
      <div style="font-weight:600;margin-bottom:12px">Connection Details — ${s.name}</div>
      <div class="setting-row"><div><div class="setting-label">Connection string</div><div class="setting-desc">Full URI for application config</div></div><div style="display:flex;gap:6px;align-items:center"><span class="mono" style="font-size:11px;color:var(--text-muted)">${connStr}</span><button class="btn btn-sm btn-primary" onclick="this.textContent='Copied!';setTimeout(()=>this.textContent='Copy',1000)">Copy</button></div></div>
      <div class="setting-row"><div><div class="setting-label">Environment variable</div><div class="setting-desc">Set in rawenv shell</div></div><span class="mono" style="font-size:12px">${envVar}=${connStr}</span></div>
      <div class="setting-row"><div><div class="setting-label">Host</div></div><span class="mono" style="font-size:12px">localhost (127.0.0.1)</span></div>
      <div class="setting-row"><div><div class="setting-label">Port</div></div><span class="mono" style="font-size:12px">${s.port}</span></div>
      <div class="setting-row"><div><div class="setting-label">DNS alias</div></div><span class="mono" style="font-size:12px">${s.name.toLowerCase().replace(/[. ]/g,'')}.utilio.test</span></div>
      <div class="setting-row"><div><div class="setting-label">Unix socket</div></div><span class="mono" style="font-size:12px">.rawenv/run/${s.name.toLowerCase()}.sock</span></div>
      <div class="setting-row"><div><div class="setting-label">Tunnel</div><div class="setting-desc">Expose to public URL</div></div><button class="btn btn-sm btn-secondary" onclick="navigate('tunnel')">🔗 Create tunnel</button></div>
      <div style="margin-top:16px;padding:12px;background:var(--bg-secondary);border-radius:8px">
        <div style="font-weight:600;font-size:12px;margin-bottom:8px">Quick test</div>
        <div class="terminal-block" style="font-size:11px;padding:10px">
          <div class="t-muted">$ rawenv run -- psql -h localhost -p ${s.port} -U myapp myapp_dev</div>
          <div style="color:var(--success)">psql (18.2)</div>
          <div style="color:var(--success)">Type "help" for help.</div>
          <div>myapp_dev=# </div>
        </div>
      </div>
    </div>`;
  }

  if(t===3) { // Cell
    const os=currentOS();
    const cellMech=os==='macos'?'Seatbelt (sandbox-exec)':os==='linux'?'Namespaces + Landlock':'AppContainer';
    const isRunning=s.status==='running';
    return `<div style="padding:16px 24px">
      <div style="font-weight:600;margin-bottom:4px">Isolation Cell — ${s.name}</div>
      <div class="t-muted" style="font-size:12px;margin-bottom:16px">Mechanism: ${cellMech}</div>
      ${isRunning?`
        <div class="cell-box active" style="width:100%;text-align:left;display:flex;gap:16px;padding:16px">
          <div style="flex:1">
            <div style="font-weight:600;margin-bottom:8px;color:var(--success)">● Cell active</div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">Filesystem</div><div class="setting-desc">Restricted to data directory only</div></div><span class="mono" style="font-size:11px">.rawenv/data/${s.name.toLowerCase()}/</span></div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">Network</div><div class="setting-desc">Bound to port only</div></div><span class="mono" style="font-size:11px">127.0.0.1:${s.port}</span></div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">Memory limit</div></div><input class="setting-input" value="256MB" style="width:80px"></div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">CPU limit</div></div><input class="setting-input" value="1 core" style="width:80px"></div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">PID</div></div><span class="mono" style="font-size:11px">${s.pid}</span></div>
            <div class="setting-row" style="margin:4px 0;padding:8px 12px"><div><div class="setting-label">Actual usage</div></div><span class="mono" style="font-size:11px">CPU ${s.cpu} · MEM ${s.mem}</span></div>
          </div>
        </div>
        <div style="margin-top:12px;display:flex;gap:6px">
          <button class="btn btn-sm btn-secondary">View sandbox profile</button>
          <button class="btn btn-sm btn-secondary">View process tree</button>
          <button class="btn btn-sm btn-secondary" style="color:var(--warning)">Disable cell</button>
        </div>
      `:`
        <div class="cell-box" style="width:100%;text-align:center;padding:24px;color:var(--text-disabled)">
          <div style="font-size:24px;margin-bottom:8px">🔓</div>
          <div style="font-weight:600">No active cell</div>
          <div style="font-size:12px;margin-top:4px">Service is ${s.status}. Cell activates when service starts.</div>
        </div>
      `}
    </div>`;
  }

  if(t===4) { // Backups
    return `<div style="padding:16px 24px">
      <div style="display:flex;justify-content:space-between;margin-bottom:12px">
        <div><div style="font-weight:600">Backups — ${s.name}</div><div class="t-muted" style="font-size:12px">Data directory: .rawenv/data/${s.name.toLowerCase()}/</div></div>
        <button class="btn btn-sm btn-primary">Create Backup Now</button>
      </div>
      <div class="setting-row"><div><div class="setting-label">Auto-backup</div><div class="setting-desc">Backup data before rawenv updates or migrations</div></div>${toggle(true)}</div>
      <div class="setting-row"><div><div class="setting-label">Backup location</div></div><input class="setting-input" value=".rawenv/backups/" style="width:200px"></div>
      <div class="setting-row"><div><div class="setting-label">Retention</div><div class="setting-desc">Number of backups to keep</div></div><input class="setting-input" value="5" style="width:60px"></div>
      <div style="margin-top:16px;font-weight:600;font-size:13px;margin-bottom:8px">Backup History</div>
      <div class="setting-row"><div><div class="setting-label">2026-04-14 14:00</div><div class="setting-desc">Auto · Before config change · 180MB</div></div><div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary">Restore</button><button class="btn btn-sm btn-secondary" style="color:var(--error)">Delete</button></div></div>
      <div class="setting-row"><div><div class="setting-label">2026-04-13 09:00</div><div class="setting-desc">Auto · Before rawenv update · 175MB</div></div><div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary">Restore</button><button class="btn btn-sm btn-secondary" style="color:var(--error)">Delete</button></div></div>
      <div class="setting-row"><div><div class="setting-label">2026-04-12 16:30</div><div class="setting-desc">Manual · 172MB</div></div><div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary">Restore</button><button class="btn btn-sm btn-secondary" style="color:var(--error)">Delete</button></div></div>
      <div class="t-muted" style="font-size:11px;margin-top:8px">Total backup size: 527MB · 3 of 5 slots used</div>
    </div>`;
  }
  return '';
}

function renderGUIDashboard(os) {
  const s=SERVICES[window._selectedSvc];
  const tabs=['Logs','Config','Connection','Cell','Backups'];
  const tabHTML=tabs.map((t,i)=>`<div class="tab ${i===window._dashTab?'active':''}" data-testid="dash-tab-${t.toLowerCase()}" onclick="window._dashTab=${i};render()">${t}</div>`).join('');
  return `<div class="screen active"><div class="window ${os}-chrome">${titlebar(os,'rawenv — my-app')}<div class="gui-layout">${sidebar()}
    <div class="main-content">
      <div class="content-header">
        <div class="header-actions"><button class="btn btn-secondary btn-sm" style="color:var(--error)">⏹ Stop</button><button class="btn btn-secondary btn-sm" style="color:var(--warning)">↻ Restart</button><button class="btn btn-secondary btn-sm" onclick="navigate('tunnel')">🔗 Tunnel</button></div>
        <h1>${s.icon} ${s.name}</h1>
        <div class="content-meta">Version ${s.version} · Port ${s.port} · PID ${s.pid||'—'} · Uptime ${s.uptime} · Cell: ${s.status==='running'?'isolated':'—'}</div>
      </div>
      ${statsCards()}
      <div class="tab-bar">${tabHTML}</div>
      ${dashTabContent()}
    </div></div></div></div>`;
}

function renderMenuBar() {
  const svcs=SERVICES.map(s=>{
    const on=s.status==='running';
    return `<div class="popover-svc">${svcDot(s.status)}<div style="flex:1"><div class="svc-name ${on?'':'stopped-text'}">${s.name}</div><div class="mono" style="font-size:10px;color:var(--text-muted)">:${s.port} · ${on?s.mem+' · '+s.uptime:'stopped'}</div></div>${toggle(on)}</div>`;
  }).join('');
  return `<div class="screen active menubar-screen">
    <div class="fake-menubar"><span style="color:var(--text-muted)">Mon 14 Apr 13:00</span><span class="menubar-icon">🔋</span><span class="menubar-icon">📶</span><span class="menubar-icon" style="color:var(--accent);font-weight:700">⚡</span></div>
    <div class="popover">
      <div class="popover-header"><span style="font-size:15px;font-weight:700">⚡ rawenv</span><span style="font-size:11px;color:var(--success)">4/5 running</span></div>
      <div class="popover-project"><span style="font-weight:500">my-app</span> <span style="color:var(--text-muted)">▾</span></div>
      <div class="popover-divider"></div>${svcs}<div class="popover-divider"></div>
      <div class="popover-actions"><button class="btn btn-primary btn-sm" style="flex:1">▶ Start All</button><button class="btn btn-secondary btn-sm" style="flex:1" onclick="navigate('gui-dashboard')">Dashboard</button></div>
      <div class="popover-footer">rawenv v0.1.0 · utilio.test · 462MB</div>
    </div></div>`;
}

function settingsContent() {
  const os=currentOS();
  const p=window._settingsPage;
  const pages={
    general:`<div class="settings-page-title">General</div><div class="settings-page-desc">Core rawenv settings</div>
      <div class="setting-row"><div><div class="setting-label">Store location</div><div class="setting-desc">Where rawenv installs packages</div></div><input class="setting-input" value="~/.rawenv/store/"></div>
      <div class="setting-row"><div><div class="setting-label">Auto-start services</div><div class="setting-desc">Start services when entering project directory</div></div>${toggle(true)}</div>
      <div class="setting-row"><div><div class="setting-label">Auto-detect projects</div><div class="setting-desc">Scan for package.json, composer.json, etc.</div></div>${toggle(true)}</div>
      <div class="setting-row"><div><div class="setting-label">Launch at login</div><div class="setting-desc">Start rawenv background service at login</div></div>${toggle(false)}</div>
      <div class="setting-row"><div><div class="setting-label">File watcher</div><div class="setting-desc">Monitor project dirs for changes and auto-update</div></div>${toggle(true)}</div>
      <div class="setting-row"><div><div class="setting-label">Scan paths</div><div class="setting-desc">Directories to scan for projects</div></div><input class="setting-input" value="~/Projects, ~/Developer" style="width:250px"></div>`,

    services:settingsServiceDetailPage(),
    _services_unused:`<div class="settings-page-title">Services</div><div class="settings-page-desc">OLD
      ${SERVICES.map(s=>`<div class="svc-manage-row">
        ${svcDot(s.status)}
        <div class="svc-manage-info"><div style="font-weight:600">${s.name} ${s.version}</div><div style="font-size:11px;color:var(--text-muted)">Port ${s.port} · ${s.mem} · Cell: ${s.status==='running'?'isolated':'—'} · Store: ~/.rawenv/store/${s.name.toLowerCase()}-${s.version}/</div></div>
        <div class="svc-manage-actions">
          <button class="btn btn-sm btn-secondary">Config</button>
          <button class="btn btn-sm btn-secondary">Logs</button>
          <button class="btn btn-sm btn-secondary" style="color:var(--error)">Remove</button>
        </div>
      </div>`).join('')}
      <button class="btn btn-secondary" style="margin-top:12px">+ Add service</button>`,

    runtimes:`<div class="settings-page-title">Runtimes</div><div class="settings-page-desc">Installed language runtimes</div>
      <div class="runtime-row">${svcDot('running')}<div class="runtime-info"><div style="font-weight:600">Node.js</div><div class="runtime-ver">22.15.0 · ~/.rawenv/store/node-22.15.0/</div></div><div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary" onclick="showSwitchVersion('Node.js','22.15.0')">Switch version</button><button class="btn btn-sm btn-secondary" style="color:var(--error)">Remove</button></div></div>
      <div class="runtime-row">${svcDot('running')}<div class="runtime-info"><div style="font-weight:600">PHP</div><div class="runtime-ver">8.4.6 · /opt/homebrew/bin/php (external)</div></div><div style="display:flex;gap:6px"><button class="btn btn-sm btn-secondary" onclick="showMigrate('PHP',{path:'/opt/homebrew/bin/php',version:'8.4.6',data:'/opt/homebrew/etc/php/',mem:'—',port:'—',optimization:'opcache tuning',optimizedMem:'—'})">Migrate to rawenv</button></div></div>
      <div class="runtime-row" style="opacity:.5"><div class="runtime-info"><div style="font-weight:600;color:var(--text-disabled)">Python</div><div class="runtime-ver">Not installed</div></div><button class="btn btn-sm btn-secondary">+ Install</button></div>
      <div class="runtime-row" style="opacity:.5"><div class="runtime-info"><div style="font-weight:600;color:var(--text-disabled)">Ruby</div><div class="runtime-ver">Not installed</div></div><button class="btn btn-sm btn-secondary">+ Install</button></div>
      <div class="runtime-row" style="opacity:.5"><div class="runtime-info"><div style="font-weight:600;color:var(--text-disabled)">Go</div><div class="runtime-ver">Not installed</div></div><button class="btn btn-sm btn-secondary">+ Install</button></div>
      <button class="btn btn-secondary" style="margin-top:12px">Browse all runtimes</button>`,

    network:`<div class="settings-page-title">Network</div><div class="settings-page-desc">DNS, proxy, and tunneling configuration</div>
      <div class="settings-section"><h3>DNS Masking</h3>
        <div class="setting-row"><div><div class="setting-label">Local domain</div><div class="setting-desc">TLD for local services</div></div><input class="setting-input" value=".test" style="width:80px"></div>
        <div class="setting-row"><div><div class="setting-label">DNS provider</div><div class="setting-desc">${os==='macos'?'dnsmasq':os==='linux'?'systemd-resolved':'Acrylic DNS'}</div></div><span class="mono" style="font-size:12px;color:var(--success)">● active</span></div>
        <div class="setting-row"><div><div class="setting-label">Active domains</div><div class="setting-desc">Currently resolving</div></div><div class="mono" style="font-size:11px;color:var(--text-muted)">utilio.test, pg.utilio.test, redis.utilio.test</div></div>
      </div>
      <div class="settings-section"><h3>Reverse Proxy</h3>
        <div class="setting-row"><div><div class="setting-label">Auto-TLS</div><div class="setting-desc">Self-signed certs for .test domains</div></div>${toggle(true)}</div>
        <div class="setting-row"><div><div class="setting-label">Proxy port</div><div class="setting-desc">Main proxy listening port</div></div><input class="setting-input" value="80" style="width:60px"></div>
      </div>
      <div class="settings-section"><h3>Tunneling</h3>
        <div class="setting-row"><div><div class="setting-label">Tunnel provider</div><div class="setting-desc">For exposing local services publicly</div></div><select class="setting-input" style="width:160px"><option>bore (built-in)</option><option>cloudflared</option><option>ngrok</option><option>rathole</option></select></div>
        <div class="setting-row"><div><div class="setting-label">Relay server</div><div class="setting-desc">bore relay endpoint</div></div><input class="setting-input" value="bore.pub" style="width:160px"></div>
      </div>`,

    cells:`<div class="settings-page-title">Isolation Cells</div><div class="settings-page-desc">OS-native process isolation for services. ${os==='macos'?'Using Seatbelt (sandbox-exec)':os==='linux'?'Using Namespaces + Landlock LSM':'Using AppContainer + Job Objects'}</div>
      <div class="cell-visual">
        <div class="cell-box active"><div class="cell-name">postgresql</div><div class="cell-detail">fs: .rawenv/data/pg/<br>net: :5432 only<br>mem: 256MB limit<br>cpu: 1 core</div></div>
        <div class="cell-box active"><div class="cell-name">redis</div><div class="cell-detail">fs: .rawenv/data/redis/<br>net: :6379 only<br>mem: 64MB limit<br>cpu: 0.5 core</div></div>
        <div class="cell-box active"><div class="cell-name">meilisearch</div><div class="cell-detail">fs: .rawenv/data/meili/<br>net: :7700 only<br>mem: 256MB limit<br>cpu: 1 core</div></div>
        <div class="cell-box"><div class="cell-name" style="color:var(--text-disabled)">node</div><div class="cell-detail" style="color:var(--text-disabled)">no cell<br>(dev server)</div></div>
        <div class="cell-box" style="border-color:var(--error)"><div class="cell-name" style="color:var(--text-disabled)">sqlserver</div><div class="cell-detail" style="color:var(--text-disabled)">stopped</div></div>
      </div>
      <div class="settings-section" style="margin-top:20px"><h3>Cell Defaults</h3>
        <div class="setting-row"><div><div class="setting-label">Enable cells by default</div><div class="setting-desc">Isolate all new services automatically</div></div>${toggle(true)}</div>
        <div class="setting-row"><div><div class="setting-label">Default memory limit</div><div class="setting-desc">Per-cell memory cap</div></div><input class="setting-input" value="256MB" style="width:80px"></div>
        <div class="setting-row"><div><div class="setting-label">Default CPU limit</div><div class="setting-desc">Per-cell CPU cores</div></div><input class="setting-input" value="1" style="width:60px"></div>
        <div class="setting-row"><div><div class="setting-label">Network isolation</div><div class="setting-desc">Restrict each cell to its port only</div></div>${toggle(true)}</div>
      </div>`,

    deploy:`<div class="settings-page-title">Deploy</div><div class="settings-page-desc">Deployment and infrastructure settings</div>
      <div class="settings-section"><h3>Default Provider</h3>
        <div class="setting-row"><div><div class="setting-label">Provider</div><div class="setting-desc">Default deployment target</div></div><select class="setting-input" style="width:160px"><option>Hetzner</option><option>AWS</option><option>DigitalOcean</option><option>GCP</option><option>Azure</option><option>Custom SSH</option></select></div>
        <div class="setting-row"><div><div class="setting-label">Hetzner API token</div><div class="setting-desc">For automated provisioning</div></div><input class="setting-input" type="password" value="••••••••••" style="width:200px"></div>
        <div class="setting-row"><div><div class="setting-label">SSH key</div><div class="setting-desc">Key for server access</div></div><input class="setting-input" value="~/.ssh/id_ed25519.pub" style="width:250px"></div>
      </div>
      <div class="settings-section"><h3>IaC</h3>
        <div class="setting-row"><div><div class="setting-label">Terraform path</div><div class="setting-desc">Terraform binary location</div></div><input class="setting-input" value="terraform" style="width:160px"></div>
        <div class="setting-row"><div><div class="setting-label">Ansible path</div><div class="setting-desc">Ansible binary location</div></div><input class="setting-input" value="ansible-playbook" style="width:160px"></div>
        <div class="setting-row"><div><div class="setting-label">Auto-generate on setup</div><div class="setting-desc">Create deploy configs when setting up a project</div></div>${toggle(false)}</div>
      </div>
      <div class="settings-section"><h3>Image Building</h3>
        <div class="setting-row"><div><div class="setting-label">Container runtime</div><div class="setting-desc">For building OCI images</div></div><select class="setting-input" style="width:140px"><option>Podman</option><option>Docker</option><option>Buildah</option></select></div>
        <div class="setting-row"><div><div class="setting-label">Registry</div><div class="setting-desc">Default push target</div></div><input class="setting-input" value="ghcr.io/rawenv" style="width:200px"></div>
      </div>`,

    ai:`<div class="settings-page-title">AI Assistant</div><div class="settings-page-desc">Built-in AI for environment help and optimization</div>
      <div class="settings-section"><h3>Provider</h3>
        <div class="setting-row"><div><div class="setting-label">AI provider</div><div class="setting-desc">LLM API for the assistant</div></div><select class="setting-input" style="width:200px"><option>Auto (Groq → Cerebras → CF)</option><option>Groq (Llama 3.3 70B)</option><option>Cerebras (Qwen3 235B)</option><option>Cloudflare Workers AI</option><option>Google Gemini</option><option>Mistral AI</option><option>Ollama (local)</option><option>Custom OpenAI-compatible</option></select></div>
        <div class="setting-row"><div><div class="setting-label">API key</div><div class="setting-desc">Leave empty for free-tier providers</div></div><input class="setting-input" value="" placeholder="Optional" style="width:200px"></div>
        <div class="setting-row"><div><div class="setting-label">Ollama endpoint</div><div class="setting-desc">For local model inference</div></div><input class="setting-input" value="http://localhost:11434" style="width:200px"></div>
      </div>
      <div class="settings-section"><h3>Behavior</h3>
        <div class="setting-row"><div><div class="setting-label">Proactive suggestions</div><div class="setting-desc">AI detects issues and suggests fixes automatically</div></div>${toggle(true)}</div>
        <div class="setting-row"><div><div class="setting-label">Auto-apply safe fixes</div><div class="setting-desc">Apply non-destructive optimizations without asking</div></div>${toggle(false)}</div>
        <div class="setting-row"><div><div class="setting-label">Include logs in context</div><div class="setting-desc">Send recent service logs to AI for better answers</div></div>${toggle(true)}</div>
        <div class="setting-row"><div><div class="setting-label">Max context size</div><div class="setting-desc">Limit context sent to AI</div></div><input class="setting-input" value="4096" style="width:80px"> <span class="t-muted" style="font-size:11px">tokens</span></div>
      </div>`,

    theme:settingsThemePage(),
    _theme_unused:`<div class="settings-page-title">Theme</div><div class="settings-page-desc">Customize appearance. Changes apply in real-time.</div>
      <div class="settings-section"><h3>Mode</h3>
        <div class="setting-row"><div><div class="setting-label">Color mode</div><div class="setting-desc">Dark, Light, or follow system</div></div><select class="setting-input" style="width:120px" onchange="setTheme(this.value)"><option value="dark" ${window._theme==='dark'?'selected':''}>Dark</option><option value="light" ${window._theme==='light'?'selected':''}>Light</option><option value="system">System</option></select></div>
      </div>
      <div class="settings-section"><h3>Colors</h3>
        <div class="setting-row"><div><div class="setting-label">Accent color</div><div class="setting-desc">Primary accent for buttons and highlights</div></div><input type="color" value="#6366f1" class="color-picker" onchange="document.documentElement.style.setProperty('--accent',this.value)"></div>
        <div class="setting-row"><div><div class="setting-label">Success color</div><div class="setting-desc">Running/healthy indicators</div></div><input type="color" value="#34d399" class="color-picker" onchange="document.documentElement.style.setProperty('--success',this.value)"></div>
        <div class="setting-row"><div><div class="setting-label">Error color</div><div class="setting-desc">Stopped/error indicators</div></div><input type="color" value="#f87171" class="color-picker" onchange="document.documentElement.style.setProperty('--error',this.value)"></div>
      </div>
      <div class="settings-section"><h3>Layout</h3>
        <div class="setting-row"><div><div class="setting-label">Border radius</div><div class="setting-desc">Corner rounding (0-16px)</div></div><input type="range" min="0" max="16" value="8" class="range-input" oninput="document.documentElement.style.setProperty('--radius-md',this.value+'px');this.nextElementSibling.textContent=this.value+'px'"><span class="mono" style="font-size:11px;width:40px">8px</span></div>
        <div class="setting-row"><div><div class="setting-label">Font size</div><div class="setting-desc">Base UI font size</div></div><input type="range" min="11" max="16" value="13" class="range-input" oninput="document.body.style.fontSize=this.value+'px';this.nextElementSibling.textContent=this.value+'px'"><span class="mono" style="font-size:11px;width:40px">13px</span></div>
        <div class="setting-row"><div><div class="setting-label">Sidebar width</div><div class="setting-desc">Left sidebar width in pixels</div></div><input type="range" min="180" max="320" value="240" class="range-input" oninput="this.nextElementSibling.textContent=this.value+'px'"><span class="mono" style="font-size:11px;width:40px">240px</span></div>
      </div>
      <div class="settings-section"><h3>Theme File</h3>
        <div style="padding:12px;background:var(--bg-secondary);border-radius:8px;font-family:'JetBrains Mono',monospace;font-size:11px;color:var(--text-muted)">
          <div style="color:var(--text-disabled)"># .rawenv/theme.toml — auto-saved from UI</div>
          <div>[mode]</div><div>scheme = "dark"</div><div></div>
          <div>[colors]</div><div>accent = "#6366f1"</div><div>success = "#34d399"</div><div>error = "#f87171"</div><div></div>
          <div>[layout]</div><div>border_radius = 8</div><div>font_size = 13</div><div>sidebar_width = 240</div>
        </div>
        <div style="margin-top:8px;display:flex;gap:8px"><button class="btn btn-sm btn-secondary">Export theme</button><button class="btn btn-sm btn-secondary">Import theme</button><button class="btn btn-sm btn-secondary">Reset to defaults</button></div>
      </div>`,

    about:`<div class="settings-page-title">About</div><div class="settings-page-desc">rawenv — Raw native dev environments</div>
      <div style="text-align:center;padding:20px">
        <div style="font-size:48px;margin-bottom:12px">⚡</div>
        <div style="font-size:24px;font-weight:700">rawenv</div>
        <div style="color:var(--text-muted);margin:8px 0">Version 0.1.0 · Built with Zig 0.14</div>
        <div style="color:var(--text-muted);font-size:12px">MIT License · rawenv.com · github.com/rawenv/rawenv</div>
      </div>
      <div class="setting-row"><div><div class="setting-label">OS</div></div><span class="mono" style="font-size:12px">${os==='macos'?'macOS 26 (arm64)':os==='linux'?'Debian 13 (x86_64)':'Windows 11 (x86_64)'}</span></div>
      <div class="setting-row"><div><div class="setting-label">Service manager</div></div><span class="mono" style="font-size:12px">${os==='macos'?'launchd':os==='linux'?'systemd':'Windows Services'}</span></div>
      <div class="setting-row"><div><div class="setting-label">Isolation</div></div><span class="mono" style="font-size:12px">${os==='macos'?'Seatbelt (sandbox-exec)':os==='linux'?'Namespaces + Landlock LSM':'AppContainer + Job Objects'}</span></div>
      <div class="setting-row"><div><div class="setting-label">Store</div></div><span class="mono" style="font-size:12px">~/.rawenv/store/ (1.8GB used)</span></div>
      <div class="setting-row"><div><div class="setting-label">Projects</div></div><span class="mono" style="font-size:12px">14 discovered · 3 active</span></div>
      <div style="margin-top:16px;display:flex;gap:8px"><button class="btn btn-secondary btn-sm" onclick="showUpdateCheck()">Check for updates</button><button class="btn btn-secondary btn-sm" style="color:var(--error)" onclick="navigate('uninstall')">Uninstall rawenv</button></div>`
  };
  return pages[p]||pages.general;
}

function renderSettings(os) {
  const navItems=['general','services','runtimes','network','cells','deploy','ai','theme','about'];
  const labels={general:'General',services:'Services',runtimes:'Runtimes',network:'Network',cells:'Cells',deploy:'Deploy',ai:'AI',theme:'Theme',about:'About'};
  const nav=navItems.map(n=>`<div class="settings-nav-item ${window._settingsPage===n?'active':''}" data-testid="settings-nav-${n}" onclick="window._settingsPage='${n}';render()">${labels[n]}</div>`).join('');
  return `<div class="screen active"><div class="window ${os}-chrome">${titlebar(os,'rawenv — Settings')}
    ${breadcrumb([{label:'Dashboard',screen:'gui-dashboard'},{label:'Settings'}])}
    <div class="settings-layout"><div class="settings-nav">${nav}</div><div class="settings-content">${settingsContent()}</div></div></div></div>`;
}
