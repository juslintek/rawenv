// Shared UI components
function svcDot(s) { return `<span class="svc-dot ${s}"></span>`; }
function logHTML(logs) { return (logs||LOGS).map(l=>`<div><span class="log-time">${l.time}</span> <span class="log-msg ${l.level}">${l.msg}</span></div>`).join(''); }

function titlebar(os, title) {
  if (os==='windows') return `<div class="titlebar"><span class="titlebar-text" style="text-align:left;padding-left:12px">${title}</span><div style="display:flex"><span class="win-btn">─</span><span class="win-btn">□</span><span class="win-btn close">✕</span></div></div>`;
  if (os==='linux') return `<div class="titlebar"><span class="titlebar-text">${title}</span><div class="dots"><span class="dot dot-r"></span><span class="dot dot-y"></span><span class="dot dot-g"></span></div></div>`;
  return `<div class="titlebar"><div class="dots"><span class="dot dot-r"></span><span class="dot dot-y"></span><span class="dot dot-g"></span></div><span class="titlebar-text">${title}</span><div style="width:52px"></div></div>`;
}

function sidebar() {
  const items = SERVICES.map((s,i) => {
    const sel = i===window._selectedSvc?'selected':'';
    const txt = s.status==='stopped'?'stopped-text':'';
    return `<div class="svc-item ${sel}" data-testid="svc-item-${i}" onclick="selectService(${i})">${svcDot(s.status)}<div class="svc-info"><div class="svc-name ${txt}">${s.name}</div><div class="svc-port ${txt}">:${s.port}</div></div><span class="svc-status ${s.status}">${s.status}</span></div>`;
  }).join('');
  return `<div class="sidebar">
    <div class="sidebar-header"><div class="project-select" onclick="this.classList.toggle('open')"><div class="project-name">my-app ▾</div><div class="project-path">~/projects/my-app</div></div></div>
    <div class="section-label">Services</div><div class="service-list">${items}</div>
    <div class="section-label">Runtimes</div>
    <div style="padding:4px 16px;font-size:13px;display:flex;justify-content:space-between"><span>Node.js</span><span class="mono" style="color:var(--text-muted);font-size:11px">22.15</span></div>
    <div style="padding:4px 16px 12px;font-size:13px;display:flex;justify-content:space-between"><span>PHP</span><span class="mono" style="color:var(--text-muted);font-size:11px">8.4</span></div>
    <div class="sidebar-actions"><button class="btn btn-primary btn-sm" data-testid="start-all" onclick="toggleAll('start')">▶ Start All</button><button class="btn btn-secondary btn-sm" data-testid="stop-all" onclick="toggleAll('stop')">⏹ Stop All</button></div>
  </div>`;
}

function statsCards() {
  const s = SERVICES[window._selectedSvc];
  return `<div class="stats-row">
    <div class="stat-card"><div class="stat-label">CPU</div><div class="stat-value">${s.cpu}</div><div class="stat-bar"><div class="stat-fill" style="width:${parseFloat(s.cpu)||0}%;background:var(--success)"></div></div></div>
    <div class="stat-card"><div class="stat-label">Memory</div><div class="stat-value">${s.mem}</div><div class="stat-bar"><div class="stat-fill" style="width:${parseInt(s.mem)||0}%;background:var(--accent-hover)"></div></div></div>
    <div class="stat-card"><div class="stat-label">Connections</div><div class="stat-value">3<span style="font-size:14px;color:var(--text-muted)"> / 100</span></div></div>
    <div class="stat-card"><div class="stat-label">Disk</div><div class="stat-value">245 MB</div><div class="stat-bar"><div class="stat-fill" style="width:5%;background:var(--info)"></div></div></div>
  </div>`;
}

function tabBar(tabs, activeIdx) {
  return `<div class="tab-bar">${tabs.map((t,i)=>`<div class="tab ${i===activeIdx?'active':''}" data-testid="tab-${t.toLowerCase().replace(/\s+/g,'-')}" onclick="switchTab(this)">${t}</div>`).join('')}</div>`;
}

function toggle(on) {
  return `<div class="toggle ${on?'on':'off'}" onclick="toggleSvc(this)"><div class="toggle-knob"></div></div>`;
}

// Modal system
function showModal(title, bodyHTML, actions) {
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';
  overlay.onclick = e => { if(e.target===overlay) overlay.remove(); };
  overlay.innerHTML = `<div class="modal">
    <div class="modal-header"><h2>${title}</h2><button class="modal-close" onclick="this.closest('.modal-overlay').remove()">✕</button></div>
    <div class="modal-body">${bodyHTML}</div>
    <div class="modal-actions">${actions||''}</div>
  </div>`;
  document.body.appendChild(overlay);
}

function showInstallMinIO() {
  showModal('Install MinIO Locally', `
    <p style="color:var(--text-muted);font-size:13px;margin-bottom:16px">MinIO is an S3-compatible object storage server. rawenv will install and configure it as a local replacement for AWS S3.</p>
    <div class="migrate-step"><span class="migrate-num">1</span><div><div style="font-weight:500">Download MinIO</div><div class="migrate-detail">~90MB binary → ~/.rawenv/store/minio-2024.01/</div></div></div>
    <div class="migrate-step"><span class="migrate-num">2</span><div><div style="font-weight:500">Configure storage</div><div class="migrate-detail">Data dir: .rawenv/data/minio/ · Port: 9000 (API) + 9001 (Console)</div></div></div>
    <div class="migrate-step"><span class="migrate-num">3</span><div><div style="font-weight:500">Create default bucket</div><div class="migrate-detail">Bucket name from S3_BUCKET env var · Access key: minioadmin</div></div></div>
    <div class="migrate-step"><span class="migrate-num">4</span><div><div style="font-weight:500">Update .env</div><div class="migrate-detail">S3_ENDPOINT=http://localhost:9000 · S3_ACCESS_KEY=minioadmin</div></div></div>
    <div class="migrate-step"><span class="migrate-num">5</span><div><div style="font-weight:500">Start in isolation cell</div><div class="migrate-detail">Restricted to .rawenv/data/minio/ only · ~50MB RAM</div></div></div>
    <div style="margin-top:12px;padding:12px;background:var(--bg-secondary);border-radius:8px;font-size:12px">
      <div style="font-weight:600;margin-bottom:4px">After install:</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Console: http://minio.myapp.test:9001</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">API: http://minio.myapp.test:9000</div>
    </div>
  `, `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
     <button class="btn btn-primary" onclick="this.textContent='Installing...';this.disabled=true;setTimeout(()=>{this.textContent='✓ Installed';this.style.background='var(--success)'},1500)">Install MinIO</button>`);
}

function showMigrate(name, existing) {
  showModal('Migrate ' + name + ' to rawenv', `
    <p style="color:var(--text-muted);font-size:13px;margin-bottom:16px">rawenv will take over management of your existing ${name} installation for better performance and isolation.</p>
    <div style="padding:12px;background:var(--bg-secondary);border-radius:8px;margin-bottom:16px">
      <div style="font-size:12px;font-weight:600;margin-bottom:8px">Current installation</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Binary: ${existing.path}</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Version: ${existing.version}</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Data: ${existing.data}</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Memory: ${existing.mem}</div>
    </div>
    <div class="migrate-step"><span class="migrate-num">1</span><div><div style="font-weight:500">Stop existing service</div><div class="migrate-detail">Graceful shutdown of current ${name}</div></div></div>
    <div class="migrate-step"><span class="migrate-num">2</span><div><div style="font-weight:500">Copy data to rawenv store</div><div class="migrate-detail">${existing.data} → .rawenv/data/${name.toLowerCase()}/</div></div></div>
    <div class="migrate-step"><span class="migrate-num">3</span><div><div style="font-weight:500">Apply optimized config</div><div class="migrate-detail">${existing.optimization}</div></div></div>
    <div class="migrate-step"><span class="migrate-num">4</span><div><div style="font-weight:500">Start in isolation cell</div><div class="migrate-detail">Restricted filesystem + resource limits</div></div></div>
    <div class="migrate-step"><span class="migrate-num">5</span><div><div style="font-weight:500">Verify & update PATH</div><div class="migrate-detail">rawenv binary takes priority, original untouched as fallback</div></div></div>
    <div style="margin-top:12px;padding:10px;background:rgba(52,211,153,.1);border:1px solid var(--success);border-radius:8px;font-size:12px;color:var(--success)">
      💡 Expected improvement: Memory ${existing.mem} → ${existing.optimizedMem} · Original installation preserved as fallback
    </div>
  `, `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
     <button class="btn btn-primary" onclick="this.textContent='Migrating...';this.disabled=true;setTimeout(()=>{this.textContent='✓ Migrated';this.style.background='var(--success)'},2000)">Migrate to rawenv</button>`);
}

function showKeepExisting(name, existing) {
  showModal('Keep Existing ' + name, `
    <p style="color:var(--text-muted);font-size:13px;margin-bottom:16px">rawenv will use your existing ${name} installation without modifying it.</p>
    <div style="padding:12px;background:var(--bg-secondary);border-radius:8px;margin-bottom:16px">
      <div style="font-size:12px;font-weight:600;margin-bottom:8px">Current installation</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Binary: ${existing.path}</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Version: ${existing.version}</div>
      <div class="mono" style="font-size:11px;color:var(--text-muted)">Port: ${existing.port}</div>
    </div>
    <div style="font-size:13px;margin-bottom:12px;font-weight:500">What rawenv will do:</div>
    <div class="check-item"><span class="check-done">✓</span> Map this service in rawenv.toml</div>
    <div class="check-item"><span class="check-done">✓</span> Monitor health and show in dashboard</div>
    <div class="check-item"><span class="check-done">✓</span> Include in <code>rawenv shell</code> environment</div>
    <div class="check-item" style="color:var(--text-disabled)"><span>✗</span> No isolation cell (managed externally)</div>
    <div class="check-item" style="color:var(--text-disabled)"><span>✗</span> No config optimization</div>
    <div class="check-item" style="color:var(--text-disabled)"><span>✗</span> No auto-start/stop with project</div>
    <div style="margin-top:12px;padding:10px;background:rgba(251,191,36,.1);border:1px solid var(--warning);border-radius:8px;font-size:12px;color:var(--warning)">
      ⚠️ You can migrate to rawenv later from Settings → Services
    </div>
  `, `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
     <button class="btn btn-primary" onclick="this.textContent='✓ Mapped';this.style.background='var(--success)';setTimeout(()=>this.closest('.modal-overlay').remove(),800)">Keep Existing</button>`);
}

function breadcrumb(parts) {
  return '<div class="breadcrumb">' + parts.map((p,i) => {
    if(i===parts.length-1) return `<span>${p.label}</span>`;
    return `<a onclick="navigate('${p.screen}')">${p.label}</a><span class="sep">›</span>`;
  }).join('') + '</div>';
}

function showSwitchVersion(name, current) {
  const versions = {
    'Node.js':['22.15.0','22.14.0','22.12.0','20.18.0','20.17.0','18.20.0'],
    'PHP':['8.4.6','8.4.5','8.3.12','8.2.25','8.1.30'],
    'Python':['3.13.0','3.12.8','3.11.10','3.10.15'],
    'Ruby':['3.4.1','3.3.6','3.2.6'],
    'Go':['1.23.4','1.22.10','1.21.13'],
  };
  const vers = (versions[name]||['latest']).map(v =>
    `<div class="setting-row" style="cursor:pointer" onclick="this.querySelector('input').checked=true">
      <div style="display:flex;align-items:center;gap:8px">
        <input type="radio" name="ver" ${v===current?'checked':''}>
        <div><div class="setting-label">${v} ${v===current?'<span style="color:var(--success);font-size:10px">● current</span>':''}</div>
        <div class="setting-desc">${v===current?'Currently active':'Available in rawenv store'}</div></div>
      </div>
    </div>`).join('');
  showModal('Switch '+name+' Version',`
    <p style="color:var(--text-muted);font-size:13px;margin-bottom:16px">Select a version. rawenv will download if not cached, then switch instantly.</p>
    ${vers}
    <div style="margin-top:12px;padding:10px;background:var(--bg-secondary);border-radius:8px;font-size:12px;color:var(--text-muted)">
      💡 Switching is instant — rawenv updates symlinks in .rawenv/bin/. Previous version stays cached.
    </div>`,
    `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
     <button class="btn btn-primary" onclick="this.textContent='Switching...';this.disabled=true;setTimeout(()=>{this.textContent='✓ Switched';this.style.background='var(--success)';setTimeout(()=>this.closest('.modal-overlay').remove(),800)},1000)">Switch Version</button>`);
}

function showBrowsePECL() {
  const exts=[
    {name:'apcu',ver:'5.1.24',dl:'45M',desc:'APC User Cache — shared memory cache'},
    {name:'swoole',ver:'6.0.2',dl:'12M',desc:'Async I/O, coroutines, fiber-based server'},
    {name:'grpc',ver:'1.66.0',dl:'8M',desc:'gRPC PHP extension for RPC communication'},
    {name:'mongodb',ver:'2.0.0',dl:'3M',desc:'MongoDB driver for PHP'},
    {name:'imagick',ver:'3.7.0',dl:'2M',desc:'ImageMagick wrapper for image processing'},
    {name:'xdebug',ver:'3.4.0',dl:'1M',desc:'Step debugger and profiler'},
    {name:'memcached',ver:'3.3.0',dl:'1M',desc:'Memcached client using libmemcached'},
    {name:'protobuf',ver:'4.29.0',dl:'5M',desc:'Protocol Buffers serialization'},
    {name:'rdkafka',ver:'6.0.5',dl:'2M',desc:'Apache Kafka client'},
    {name:'igbinary',ver:'3.2.16',dl:'500K',desc:'Binary serializer, drop-in replacement for PHP serialize'},
    {name:'ds',ver:'1.5.0',dl:'300K',desc:'Efficient data structures: Vector, Deque, Map, Set'},
    {name:'ev',ver:'1.2.0',dl:'200K',desc:'libev event loop bindings'},
  ];
  showModal('Browse PECL Extensions',`
    <div class="ext-search" style="margin-bottom:12px"><input class="setting-input" placeholder="Search PECL..." style="flex:1" id="pecl-search" oninput="filterPECL(this.value)"></div>
    <div class="ext-filter" style="margin-bottom:12px">
      <span class="ext-filter-btn active">All (${exts.length})</span>
      <span class="ext-filter-btn">Cache</span>
      <span class="ext-filter-btn">Database</span>
      <span class="ext-filter-btn">Network</span>
      <span class="ext-filter-btn">Debug</span>
      <span class="ext-filter-btn">Serialization</span>
    </div>
    <div id="pecl-list" style="max-height:400px;overflow-y:auto">
      ${exts.map(e=>`<div class="setting-row pecl-item" data-name="${e.name}">
        <div style="flex:1"><div class="setting-label">${e.name} <span class="mono" style="font-size:10px;color:var(--text-muted)">${e.ver}</span></div>
        <div class="setting-desc">${e.desc}</div>
        <div style="font-size:10px;color:var(--text-disabled);margin-top:2px">Size: ${e.dl} · <a class="config-doc-link" href="https://pecl.php.net/package/${e.name}" target="_blank">pecl.php.net →</a></div></div>
        <button class="btn btn-sm btn-primary" onclick="this.textContent='Installing...';this.disabled=true;setTimeout(()=>{this.textContent='✓ Installed';this.style.background='var(--success)'},1500)">Install</button>
      </div>`).join('')}
    </div>`,
    `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Close</button>`);
}
function filterPECL(q) {
  document.querySelectorAll('.pecl-item').forEach(el=>{
    el.style.display=el.dataset.name.includes(q.toLowerCase())?'':'none';
  });
}

function showUpdateCheck() {
  showModal('Check for Updates', `
    <div style="text-align:center;padding:12px 0">
      <div style="font-size:32px;margin-bottom:12px" id="update-icon">⟳</div>
      <div style="font-weight:600;font-size:14px" id="update-title">Checking for updates...</div>
      <div style="color:var(--text-muted);font-size:12px;margin-top:4px" id="update-desc">Contacting rawenv.sh...</div>
    </div>
    <div id="update-result" style="display:none">
      <div style="padding:12px;background:var(--bg-secondary);border-radius:8px;margin-top:12px">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div><div style="font-weight:600">rawenv v0.2.0 available</div><div style="font-size:12px;color:var(--text-muted);margin-top:2px">Current: v0.1.0 · Size: 10.2MB</div></div>
          <span class="badge badge-local">New</span>
        </div>
        <div style="margin-top:12px;font-size:12px;color:var(--text-muted);line-height:1.6">
          <div style="font-weight:600;color:var(--text);margin-bottom:4px">What's new:</div>
          • Isolation Cells — OS-native process sandboxing<br>
          • DNS masking — .test domains for local services<br>
          • Tunnel support — expose services via bore<br>
          • AI assistant — built-in chat with Groq/Cerebras<br>
          • 12 bug fixes and performance improvements
        </div>
      </div>
      <div style="margin-top:12px;padding:10px;background:rgba(52,211,153,.1);border:1px solid var(--success);border-radius:8px;font-size:12px;color:var(--success)">
        💡 rawenv will auto-backup your configs before updating. Services will restart after update.
      </div>
    </div>
    <div id="update-uptodate" style="display:none;text-align:center;padding:12px 0">
      <div style="font-size:32px;margin-bottom:8px">✓</div>
      <div style="font-weight:600;color:var(--success)">You're up to date!</div>
      <div style="font-size:12px;color:var(--text-muted);margin-top:4px">rawenv v0.1.0 is the latest version.</div>
    </div>
    <script>setTimeout(()=>{
      document.getElementById('update-icon').textContent='🎉';
      document.getElementById('update-title').textContent='Update available!';
      document.getElementById('update-desc').style.display='none';
      document.getElementById('update-result').style.display='block';
    },1500)</script>
  `, `<button class="btn btn-secondary" onclick="this.closest('.modal-overlay').remove()">Later</button>
     <button class="btn btn-primary" id="update-btn" disabled onclick="this.textContent='Updating...';this.disabled=true;setTimeout(()=>{this.textContent='✓ Updated to v0.2.0';this.style.background='var(--success)'},2000)">Checking...</button>
     <script>setTimeout(()=>{document.getElementById('update-btn').disabled=false;document.getElementById('update-btn').textContent='Update Now'},1500)</script>`);
}
