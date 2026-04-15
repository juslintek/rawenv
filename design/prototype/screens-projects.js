// PROJECT DISCOVERY + SETUP
function renderProjectScan() {
  const os=currentOS();
  return `<div class="screen active"><div class="window ${os}-chrome" style="max-width:900px">${titlebar(os,'rawenv — Project Discovery')}
    ${breadcrumb([{label:'Home',screen:'gui-dashboard'},{label:'Project Discovery'}])}
    <div style="padding:32px">
      <h1 style="font-size:20px;margin-bottom:4px">🔍 Scanning for projects...</h1>
      <div style="color:var(--text-muted);font-size:13px;margin-bottom:24px">rawenv scans common locations for source code. Cached results are reused — only new paths are scanned.</div>
      <div class="scan-locations">
        <div class="scan-loc done"><span class="check-done">✓</span> ~/Projects/ <span class="t-muted">(8 projects) · <span style="color:var(--success)">cached</span></span></div>
        <div class="scan-loc done"><span class="check-done">✓</span> ~/Developer/ <span class="t-muted">(2 projects) · <span style="color:var(--success)">cached</span></span></div>
        <div class="scan-loc done"><span class="check-done">✓</span> ~/Code/ <span class="t-muted">(0 projects) · <span style="color:var(--success)">cached</span></span></div>
        <div class="scan-loc active"><span style="color:var(--accent)">⟳</span> /Volumes/Projects/ <span class="t-muted">(scanning... 4 found so far)</span></div>
        <div class="scan-loc pending"><span class="check-pending">○</span> ~/Desktop/ <span class="t-muted">queued</span></div>
        <div class="scan-loc pending"><span class="check-pending">○</span> ~/Documents/ <span class="t-muted">queued</span></div>
      </div>
      <div style="margin:16px 0;display:flex;gap:8px;align-items:center;flex-wrap:wrap">
        <button class="btn btn-secondary btn-sm">+ Add custom path</button>
        <button class="btn btn-secondary btn-sm">Scan full disk</button>
        <button class="btn btn-secondary btn-sm" style="color:var(--warning)" title="Ignores cache, rescans everything">↻ Force rescan all</button>
        <span style="flex:1"></span>
        <span class="t-muted" style="font-size:12px">14 projects (10 cached, 4 new) · Last full scan: 2 min ago</span>
      </div>
      <div style="margin-top:16px;display:flex;justify-content:space-between">
        <button class="back-btn" onclick="navigate('installer-done')">← Back to installer</button>
        <button class="btn btn-primary" data-testid="scan-view-projects" onclick="navigate('project-list')">View Projects →</button>
      </div>
    </div></div></div>`;
}

function renderProjectList() {
  const os=currentOS();
  const projects=[
    {name:'utilio',path:'~/Projects/GOTAS/utilio',stack:['Node.js','Qwik','PostgreSQL','Redis','Meilisearch','SQL Server'],deps:'14 deps',managed:false},
    {name:'vialietuva-legacy',path:'~/Projects/GOTAS/vialietuva-legacy',stack:['PHP','Laravel','MySQL','Redis'],deps:'8 deps',managed:false},
    {name:'rawenv',path:'~/Projects/rawenv',stack:['Zig'],deps:'1 dep',managed:false},
    {name:'mcp-for-page-builders',path:'/Volumes/Projects/mcp-for-page-builders',stack:['Rust','Cargo'],deps:'2 deps',managed:false},
    {name:'my-saas',path:'~/Projects/my-saas',stack:['Node.js','Next.js','PostgreSQL','Redis','S3'],deps:'10 deps',managed:false},
    {name:'blog',path:'~/Projects/blog',stack:['Ruby','Jekyll'],deps:'3 deps',managed:false},
    {name:'data-pipeline',path:'~/Projects/data-pipeline',stack:['Python','PostgreSQL','Redis'],deps:'6 deps',managed:false},
    {name:'mobile-app',path:'~/Developer/mobile-app',stack:['Node.js','React Native','Firebase'],deps:'5 deps',managed:false},
  ];
  const rows=projects.map(p=>`
    <div class="project-row" data-testid="project-row" onclick="navigate('project-setup')">
      <div class="project-row-info"><div class="project-row-name">${p.name}</div><div class="project-row-path mono">${p.path}</div></div>
      <div class="project-row-stack">${p.stack.map(s=>`<span class="stack-tag">${s}</span>`).join('')}</div>
      <div class="project-row-meta">${p.deps}</div>
      <button class="btn btn-primary btn-sm" data-testid="project-setup-btn">Set Up →</button>
    </div>`).join('');

  return `<div class="screen active"><div class="window ${os}-chrome" style="max-width:1000px">${titlebar(os,'rawenv — Projects')}
    ${breadcrumb([{label:'Home',screen:'gui-dashboard'},{label:'Discovery',screen:'project-scan'},{label:'Projects'}])}
    <div style="padding:24px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
        <div><h1 style="font-size:20px">📁 Discovered Projects</h1><div class="t-muted" style="font-size:13px">Select a project to set up its environment</div></div>
        <div style="display:flex;gap:8px">
          <input class="setting-input" placeholder="Filter..." style="width:200px">
          <button class="btn btn-secondary btn-sm" onclick="navigate('project-scan')" title="Scan new paths only (cached results preserved)">↻ Scan new</button>
          <button class="btn btn-secondary btn-sm" style="color:var(--warning)" title="Ignore cache, rescan everything">↻ Full rescan</button>
        </div>
      </div>
      <div class="project-list">${rows}</div>
      <div style="margin-top:16px;display:flex;justify-content:space-between;align-items:center">
        <span class="t-muted" style="font-size:12px">14 projects · Monitoring for changes · Cache: 2 min old</span>
        <button class="btn btn-secondary btn-sm">+ Add project manually</button>
      </div>
    </div></div></div>`;
}

function renderProjectSetup() {
  const os=currentOS();
  const redisExisting={path:'/opt/homebrew/bin/redis-server',version:'7.4.2',data:'/opt/homebrew/var/db/redis/',mem:'32MB',port:'6379',optimization:'maxmemory 64mb, no-appendfsync-on-rewrite yes',optimizedMem:'12MB'};
  const phpExisting={path:'/opt/homebrew/bin/php',version:'8.4.6',data:'/opt/homebrew/etc/php/',mem:'—',port:'—',optimization:'opcache tuning, memory_limit=128M',optimizedMem:'—'};

  return `<div class="screen active"><div class="window ${os}-chrome" style="max-width:1000px">${titlebar(os,'rawenv — Set Up: utilio')}
    ${breadcrumb([{label:'Home',screen:'gui-dashboard'},{label:'Projects',screen:'project-list'},{label:'utilio Setup'}])}
    <div style="padding:24px">
      <h1 style="font-size:20px;margin-bottom:4px">⚙️ Environment Setup — utilio</h1>
      <div class="t-muted" style="font-size:13px;margin-bottom:20px">~/Projects/GOTAS/utilio</div>

      <div class="section-label" style="padding-left:0">DETECTED RUNTIMES</div>
      <div class="setup-grid">
        <div class="setup-card">
          <div class="setup-card-header"><span>💚 Node.js</span><span class="badge badge-local">Install new</span></div>
          <div class="setup-card-detail">Source: package.json → engines.node: ">=22"</div>
          <div class="setup-card-detail">Version: <select class="setting-input" style="width:100px;font-size:11px;padding:2px 6px"><option>22.15.0</option><option>20.18.0</option></select></div>
          <div class="setup-card-detail t-muted">~45MB · Not currently installed</div>
        </div>
        <div class="setup-card">
          <div class="setup-card-header"><span>🐘 PHP</span><span class="badge badge-existing">Found existing</span></div>
          <div class="setup-card-detail">Source: composer.json → require.php: "^8.4"</div>
          <div class="setup-card-detail">Found: /opt/homebrew/bin/php 8.4.6</div>
          <div class="setup-card-action">
            <button class="btn btn-sm btn-secondary" onclick="showKeepExisting('PHP',${JSON.stringify(phpExisting).replace(/"/g,'&quot;')})">Keep existing</button>
            <button class="btn btn-sm btn-primary" onclick="showMigrate('PHP',${JSON.stringify(phpExisting).replace(/"/g,'&quot;')})">Migrate to rawenv</button>
          </div>
        </div>
      </div>

      <div class="section-label" style="padding-left:0;margin-top:16px">DETECTED SERVICES</div>
      <div class="setup-grid">
        <div class="setup-card">
          <div class="setup-card-header"><span>🐘 PostgreSQL</span><span class="badge badge-local">Install new</span></div>
          <div class="setup-card-detail">Source: .env → DATABASE_URL=postgres://...@localhost:5432</div>
          <div class="setup-card-detail">Optimized: max_connections=20, shared_buffers=64MB</div>
          <div class="setup-card-detail t-muted">~84MB RAM (vs ~256MB default) · Cell: isolated</div>
        </div>
        <div class="setup-card">
          <div class="setup-card-header"><span>🔴 Redis</span><span class="badge badge-existing">Found existing</span></div>
          <div class="setup-card-detail">Source: .env → REDIS_URL=redis://localhost:6379</div>
          <div class="setup-card-detail">Found: /opt/homebrew/bin/redis-server 7.4.2 (running)</div>
          <div class="setup-card-action">
            <button class="btn btn-sm btn-secondary" onclick="showKeepExisting('Redis',${JSON.stringify(redisExisting).replace(/"/g,'&quot;')})">Keep existing</button>
            <button class="btn btn-sm btn-primary" onclick="showMigrate('Redis',${JSON.stringify(redisExisting).replace(/"/g,'&quot;')})">Migrate to rawenv</button>
          </div>
          <div class="setup-card-detail t-muted" style="margin-top:4px">💡 Migration saves 32MB → 12MB with optimized config</div>
        </div>
        <div class="setup-card">
          <div class="setup-card-header"><span>🔍 Meilisearch</span><span class="badge badge-local">Replace container</span></div>
          <div class="setup-card-detail">Source: docker-compose.yml → getmeili/meilisearch:v1.14</div>
          <div class="setup-card-detail t-muted">Native install saves ~1.2GB (no Docker overhead)</div>
        </div>
        <div class="setup-card">
          <div class="setup-card-header"><span>🗄️ SQL Server</span><span class="badge badge-local">Replace container</span></div>
          <div class="setup-card-detail">Source: docker-compose.yml → mssql/server:2025</div>
          <div class="setup-card-detail t-muted">⚠️ No native macOS — using Azure SQL Edge (lighter, ARM)</div>
        </div>
      </div>

      <div class="section-label" style="padding-left:0;margin-top:16px">DETECTED CONNECTIONS</div>
      <div class="setup-grid">
        <div class="setup-card">
          <div class="setup-card-header"><span>☁️ S3_ENDPOINT</span><span class="badge badge-remote">Remote</span></div>
          <div class="setup-card-detail">s3.amazonaws.com — file uploads</div>
          <div class="setup-card-action">
            <button class="btn btn-sm btn-primary">Keep remote ✓</button>
            <button class="btn btn-sm btn-secondary" onclick="showInstallMinIO()">Install MinIO locally</button>
          </div>
        </div>
      </div>

      <div style="margin-top:24px;padding:16px;background:var(--bg-secondary);border-radius:10px;border:1px solid var(--border)">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div><div style="font-weight:600">Summary</div><div class="t-muted" style="font-size:12px">Install 4 · Migrate 0 · Keep 2 existing · Footprint: ~462MB (vs ~2.7GB Docker)</div></div>
          <button class="btn btn-primary" data-testid="setup-apply-btn" onclick="navigate('project-installing')">Apply & Start →</button>
        </div>
      </div>
    </div></div></div>`;
}

function renderProjectInstalling() {
  const os=currentOS();
  return `<div class="screen active"><div class="window ${os}-chrome" style="max-width:900px">${titlebar(os,'rawenv — Setting Up: utilio')}
    ${breadcrumb([{label:'Home',screen:'gui-dashboard'},{label:'Projects',screen:'project-list'},{label:'utilio',screen:'project-setup'},{label:'Installing'}])}
    <div style="padding:32px">
      <h1 style="font-size:20px;margin-bottom:16px">⚙️ Setting up environment...</h1>
      <div class="progress-bar"><div class="progress-fill" id="setup-progress" style="width:0%"></div></div>
      <div id="setup-steps" style="margin-top:16px">
        <div class="check-item"><span class="check-pending" id="p0">○</span> Creating rawenv.toml</div>
        <div class="check-item"><span class="check-pending" id="p1">○</span> Installing Node.js 22.15.0</div>
        <div class="check-item"><span class="check-pending" id="p2">○</span> Installing PostgreSQL 18.2</div>
        <div class="check-item"><span class="check-pending" id="p3">○</span> Installing Meilisearch 1.14</div>
        <div class="check-item"><span class="check-pending" id="p4">○</span> Installing Azure SQL Edge</div>
        <div class="check-item"><span class="check-pending" id="p5">○</span> Applying optimized configs</div>
        <div class="check-item"><span class="check-pending" id="p6">○</span> Creating isolation cells</div>
        <div class="check-item"><span class="check-pending" id="p7">○</span> Setting up DNS (utilio.test)</div>
        <div class="check-item"><span class="check-pending" id="p8">○</span> Starting services</div>
        <div class="check-item"><span class="check-pending" id="p9">○</span> Verifying connections</div>
      </div>
      <div style="margin-top:24px;display:flex;justify-content:space-between">
        <button class="back-btn" onclick="navigate('project-setup')">← Back</button>
        <button class="btn btn-secondary" id="setup-btn" disabled>Setting up...</button>
      </div>
    </div></div></div>
    <script>if(!window._setupRan){window._setupRan=true;let i=0;const t=setInterval(()=>{const el=document.getElementById('p'+i);if(!el||i>9){clearInterval(t);window._setupRan=false;const b=document.getElementById('setup-btn');if(b)b.outerHTML='<button class="btn btn-primary" data-testid="setup-open-dashboard" onclick="navigate(\'gui-dashboard\')">Open Dashboard →</button>';return}el.className='check-done';el.textContent='✓';document.getElementById('setup-progress').style.width=((i+1)/10*100)+'%';i++},400)}</script>`;
}
