// TUI with all tab views
window._tuiTab = 0;
const TUI_TABS = ['Services','Logs','Config','Resources','AI Chat'];

function tuiTabContent() {
  const s = SERVICES[window._selectedSvc];
  if(window._tuiTab===0) return tuiServicesTab();
  if(window._tuiTab===1) return tuiLogsTab();
  if(window._tuiTab===2) return tuiConfigTab();
  if(window._tuiTab===3) return tuiResourcesTab();
  if(window._tuiTab===4) return tuiAIChatTab();
  return tuiServicesTab();
}

function tuiServicesTab() {
  const rows=SERVICES.map((s,i)=>{
    const sel=i===window._selectedSvc?'selected':'';
    const cls=s.status==='stopped'?'style="color:var(--text-disabled)"':'';
    return `<tr class="${sel}" ${cls} onclick="selectService(${i})"><td>${svcDot(s.status)}</td><td style="font-weight:600">${s.name}</td><td>${s.version}</td><td style="color:var(--info)">${s.port}</td><td>${s.pid||'—'}</td><td>${s.cpu}</td><td>${s.mem}</td><td>${s.uptime}</td></tr>`;
  }).join('');
  return `<table class="tui-table"><tr><th>STATUS</th><th>SERVICE</th><th>VERSION</th><th>PORT</th><th>PID</th><th>CPU</th><th>MEM</th><th>UPTIME</th></tr>${rows}</table>
    <div class="tui-logpanel"><div class="tui-logpanel-header">Logs — ${SERVICES[window._selectedSvc].name} <span style="float:right;font-weight:400">l: full logs</span></div>${LOGS.slice(0,4).map(l=>`<div style="font-size:11px"><span class="log-time">${l.time}</span> <span class="log-msg ${l.level}">${l.msg}</span></div>`).join('')}</div>`;
}

function tuiLogsTab() {
  return `<div style="padding:8px 16px">
    <div style="display:flex;justify-content:space-between;margin-bottom:8px;font-size:11px">
      <span style="color:var(--text-muted);font-weight:600">Logs — ${SERVICES[window._selectedSvc].name}</span>
      <span style="color:var(--text-muted)">f:filter  /: search  c:clear  w:wrap  ↑↓:scroll</span>
    </div>
    <div style="border:1px solid var(--border);border-radius:4px;padding:8px;background:var(--bg-primary);min-height:200px;font-size:11px;line-height:18px">
      ${LOGS.map(l=>`<div><span class="log-time">${l.time}</span> <span class="log-msg ${l.level}">${l.msg}</span></div>`).join('')}
      <div><span class="log-time">14:50:01</span> <span class="log-msg normal">LOG:  checkpoint starting: time</span></div>
      <div><span class="log-time">14:50:02</span> <span class="log-msg normal">LOG:  checkpoint complete: wrote 18 buffers (0.1%)</span></div>
      <div><span class="log-time">14:55:00</span> <span class="log-msg active">LOG:  connection received: host=127.0.0.1 port=52401</span></div>
      <div><span class="log-time">14:55:00</span> <span class="log-msg active">LOG:  connection authorized: user=myapp database=myapp_dev</span></div>
      <div><span class="log-time">14:55:03</span> <span class="log-msg warn">WARNING:  worker process 48295 was terminated by signal 9</span></div>
      <div><span class="log-time">14:55:03</span> <span class="log-msg err">ERROR:  terminating connection due to administrator command</span></div>
      <div style="margin-top:4px"><span style="color:var(--accent)">█</span></div>
    </div>
    <div style="display:flex;justify-content:space-between;margin-top:4px;font-size:10px;color:var(--text-disabled)">
      <span>Showing last 100 lines</span><span>Auto-scroll: ON</span>
    </div>
  </div>`;
}

window._tuiConfigMode = window._tuiConfigMode || 'view';

function tuiConfigTab() {
  const s=SERVICES[window._selectedSvc];
  const mode = window._tuiConfigMode;
  const defaults = {port:'5432',max_connections:'100',shared_buffers:'128MB',work_mem:'4MB',maintenance_work_mem:'64MB',effective_cache_size:'4GB',data_directory:'/var/lib/postgresql/data',log_destination:'stderr',logging_collector:'off',log_directory:'log',listen_addresses:'localhost',unix_socket_directories:'/tmp',bind:'0.0.0.0',maxmemory:'0',appendonly:'no',save:'3600 1 300 100 60 10000',databases:'16'};
  const configs = {
    'PostgreSQL':[['port','5432'],['max_connections','20'],['shared_buffers','64MB'],['work_mem','4MB'],['maintenance_work_mem','64MB'],['effective_cache_size','256MB'],['data_directory','.rawenv/data/postgresql/'],['log_destination','stderr'],['logging_collector','on'],['log_directory','.rawenv/logs/postgresql/'],['listen_addresses','127.0.0.1'],['unix_socket_directories','.rawenv/run/']],
    'Redis':[['port','6379'],['bind','127.0.0.1'],['maxmemory','64mb'],['maxmemory-policy','allkeys-lru'],['appendonly','no'],['save','""'],['dir','.rawenv/data/redis/'],['logfile','.rawenv/logs/redis/redis.log'],['databases','4'],['tcp-keepalive','300']],
    'Meilisearch':[['http-addr','127.0.0.1:7700'],['db-path','.rawenv/data/meilisearch/'],['env','development'],['max-indexing-memory','100MB'],['log-level','INFO']],
    'Node.js':[['version','22.15.0'],['binary','.rawenv/bin/node'],['npm','.rawenv/bin/npm'],['NODE_ENV','development']],
    'SQL Server':[['port','1433'],['accept-eula','Y'],['memory-limit','512MB'],['data-dir','.rawenv/data/sqlserver/']],
  };
  const cfg = configs[s.name]||[['status','no config']];
  const modeBar = `<div style="display:flex;justify-content:space-between;margin-bottom:8px;font-size:11px">
      <span style="color:var(--text-muted);font-weight:600">Config — ${s.name}</span>
      <div style="display:flex;gap:4px">
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${mode==='view'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._tuiConfigMode='view';render()">view</span>
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${mode==='edit'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._tuiConfigMode='edit';render()">e:edit</span>
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${mode==='diff'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._tuiConfigMode='diff';render()">d:diff</span>
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;background:var(--bg-tertiary);color:var(--text-muted)" onclick="window._tuiConfigMode='reset';render()">r:reset</span>
      </div>
    </div>`;

  if (mode==='edit') {
    return `<div class="tui-config-panel">${modeBar}
      <div style="border:1px solid var(--accent);border-radius:4px;padding:8px;background:var(--bg-primary)">
        ${cfg.map(([k,v])=>`<div class="tui-config-row" style="border-bottom:1px solid var(--border);padding:4px 0">
          <span class="tui-config-key">${k}</span>
          <span style="display:flex;align-items:center;gap:4px"><input style="background:var(--bg-tertiary);border:1px solid var(--border);border-radius:3px;padding:2px 6px;color:var(--text);font-family:'JetBrains Mono',monospace;font-size:11px;width:${v.length>20?'200px':'100px'}" value="${v}"><span style="font-size:9px;color:var(--text-disabled)">default: ${defaults[k]||v}</span></span>
        </div>`).join('')}
      </div>
      <div style="margin-top:8px;display:flex;justify-content:space-between;font-size:10px">
        <span style="color:var(--text-disabled)">Tab/Shift+Tab: navigate · Enter: save · Esc: cancel</span>
        <div style="display:flex;gap:4px">
          <span style="padding:2px 8px;border-radius:3px;background:var(--accent);color:#fff;cursor:pointer" onclick="window._tuiConfigMode='view';render()">Save</span>
          <span style="padding:2px 8px;border-radius:3px;background:var(--bg-tertiary);color:var(--text-muted);cursor:pointer" onclick="window._tuiConfigMode='view';render()">Cancel</span>
        </div>
      </div>
    </div>`;
  }

  if (mode==='diff') {
    const diffs = [
      {key:'max_connections',old:'100',new:'20',type:'changed'},
      {key:'shared_buffers',old:'128MB',new:'64MB',type:'changed'},
      {key:'effective_cache_size',old:'4GB',new:'256MB',type:'changed'},
      {key:'data_directory',old:'/var/lib/postgresql/data',new:'.rawenv/data/postgresql/',type:'changed'},
      {key:'log_directory',old:'log',new:'.rawenv/logs/postgresql/',type:'changed'},
      {key:'unix_socket_directories',old:'/tmp',new:'.rawenv/run/',type:'changed'},
    ];
    return `<div class="tui-config-panel">${modeBar}
      <div style="font-size:10px;color:var(--text-muted);margin-bottom:6px">Showing differences from ${s.name} defaults → rawenv optimized</div>
      <div style="border:1px solid var(--border);border-radius:4px;padding:8px;background:var(--bg-primary)">
        ${diffs.map(d=>`<div style="padding:4px 0;border-bottom:1px solid var(--border);font-size:11px">
          <div style="color:var(--accent);font-weight:600">${d.key}</div>
          <div style="display:flex;gap:8px;margin-top:2px">
            <span style="color:var(--error)">- ${d.old}</span>
            <span style="color:var(--success)">+ ${d.new}</span>
          </div>
        </div>`).join('')}
      </div>
      <div style="margin-top:8px;font-size:10px;color:var(--text-disabled)">${diffs.length} values changed from defaults · rawenv optimized for dev workload</div>
    </div>`;
  }

  if (mode==='reset') {
    return `<div class="tui-config-panel">${modeBar}
      <div style="border:1px solid var(--warning);border-radius:4px;padding:12px;background:rgba(251,191,36,.05)">
        <div style="color:var(--warning);font-weight:600;font-size:12px;margin-bottom:8px">⚠️ Reset to defaults?</div>
        <div style="font-size:11px;color:var(--text-muted);margin-bottom:12px">This will replace rawenv's optimized config with ${s.name} defaults. Your current optimizations (lower memory, fewer connections) will be lost.</div>
        <div style="font-size:11px;margin-bottom:8px">Changes that will be reverted:</div>
        <div style="font-size:11px;padding:4px 0"><span style="color:var(--accent)">max_connections</span>: 20 → <span style="color:var(--text-muted)">100</span></div>
        <div style="font-size:11px;padding:4px 0"><span style="color:var(--accent)">shared_buffers</span>: 64MB → <span style="color:var(--text-muted)">128MB</span></div>
        <div style="font-size:11px;padding:4px 0"><span style="color:var(--accent)">effective_cache_size</span>: 256MB → <span style="color:var(--text-muted)">4GB</span></div>
        <div style="margin-top:12px;display:flex;gap:6px">
          <span style="padding:4px 12px;border-radius:3px;background:var(--warning);color:#000;cursor:pointer;font-size:11px;font-weight:600" onclick="window._tuiConfigMode='view';render()">Reset & Restart</span>
          <span style="padding:4px 12px;border-radius:3px;background:var(--bg-tertiary);color:var(--text-muted);cursor:pointer;font-size:11px" onclick="window._tuiConfigMode='view';render()">Cancel</span>
        </div>
      </div>
    </div>`;
  }

  // Default: view mode
  return `<div class="tui-config-panel">${modeBar}
    <div style="border:1px solid var(--border);border-radius:4px;padding:8px;background:var(--bg-primary)">
      ${cfg.map(([k,v])=>`<div class="tui-config-row"><span class="tui-config-key">${k}</span><span class="tui-config-val">${v}</span></div>`).join('')}
    </div>
    <div style="margin-top:8px;font-size:10px;color:var(--text-disabled)">Config file: .rawenv/config/${s.name.toLowerCase().replace(/\s/g,'')}.conf · Cell: ${s.status==='running'?'isolated':'—'}</div>
  </div>`;
}

window._resMode = window._resMode || 'table';

function tuiResourcesTab() {
  const modeBar = `<div style="display:flex;justify-content:space-between;margin-bottom:8px;font-size:11px;padding:8px 16px">
    <span style="color:var(--text-muted);font-weight:600">Resources</span>
    <div style="display:flex;gap:4px">
      <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${window._resMode==='table'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._resMode='table';render()">s:table</span>
      <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${window._resMode==='graph'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._resMode='graph';render()">g:graph</span>
      <span style="padding:2px 8px;border-radius:3px;cursor:pointer;${window._resMode==='tree'?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._resMode='tree';render()">p:tree</span>
    </div>
  </div>`;

  if (window._resMode==='graph') {
    // ASCII-style bar chart
    return `<div style="padding:0 16px">${modeBar}
      <div style="border:1px solid var(--border);border-radius:4px;padding:12px;background:var(--bg-primary);font-size:11px;font-family:'JetBrains Mono',monospace">
        <div style="color:var(--text-muted);margin-bottom:8px">CPU Usage (last 5 min)</div>
        <div style="display:flex;align-items:flex-end;gap:2px;height:80px;margin-bottom:4px">
          ${[3,5,4,8,12,7,9,15,11,8,6,4,5,7,12,10,8,6,5,4,3,5,8,11,14,12,9,7,5,4].map(v=>
            `<div style="width:100%;background:${v>10?'var(--warning)':'var(--accent-hover)'};height:${v*5}px;border-radius:2px 2px 0 0;transition:height .2s"></div>`
          ).join('')}
        </div>
        <div style="display:flex;justify-content:space-between;color:var(--text-disabled);font-size:9px"><span>5m ago</span><span>now</span></div>
        <div style="margin-top:16px;color:var(--text-muted)">Memory Usage (per service)</div>
        <div style="margin-top:8px">
          <div style="display:flex;align-items:center;gap:8px;margin:4px 0"><span style="width:100px;text-align:right">Node.js</span><div style="flex:1;height:14px;background:var(--bg-tertiary);border-radius:2px"><div style="height:100%;width:45%;background:var(--accent-hover);border-radius:2px"></div></div><span style="width:50px">210MB</span></div>
          <div style="display:flex;align-items:center;gap:8px;margin:4px 0"><span style="width:100px;text-align:right">Meilisearch</span><div style="flex:1;height:14px;background:var(--bg-tertiary);border-radius:2px"><div style="height:100%;width:34%;background:var(--accent-hover);border-radius:2px"></div></div><span style="width:50px">156MB</span></div>
          <div style="display:flex;align-items:center;gap:8px;margin:4px 0"><span style="width:100px;text-align:right">PostgreSQL</span><div style="flex:1;height:14px;background:var(--bg-tertiary);border-radius:2px"><div style="height:100%;width:18%;background:var(--success);border-radius:2px"></div></div><span style="width:50px">84MB</span></div>
          <div style="display:flex;align-items:center;gap:8px;margin:4px 0"><span style="width:100px;text-align:right">Redis</span><div style="flex:1;height:14px;background:var(--bg-tertiary);border-radius:2px"><div style="height:100%;width:3%;background:var(--success);border-radius:2px"></div></div><span style="width:50px">12MB</span></div>
        </div>
      </div>
    </div>`;
  }

  if (window._resMode==='tree') {
    return `<div style="padding:0 16px">${modeBar}
      <div style="border:1px solid var(--border);border-radius:4px;padding:12px;background:var(--bg-primary);font-size:11px;font-family:'JetBrains Mono',monospace;line-height:1.8">
        <div style="color:var(--text-muted)">rawenv (PID 1200) — manager</div>
        <div>├─ <span style="color:var(--success)">●</span> <span style="color:var(--accent)">postgresql</span> (PID 48291) CPU 2.1% MEM 84MB</div>
        <div>│  ├─ postgres: checkpointer (48293)</div>
        <div>│  ├─ postgres: background writer (48294)</div>
        <div>│  ├─ postgres: walwriter (48295)</div>
        <div>│  ├─ postgres: autovacuum launcher (48296)</div>
        <div>│  └─ postgres: myapp myapp_dev 127.0.0.1 (48310)</div>
        <div>├─ <span style="color:var(--success)">●</span> <span style="color:var(--accent)">redis</span> (PID 48305) CPU 0.3% MEM 12MB</div>
        <div>│  └─ (no children)</div>
        <div>├─ <span style="color:var(--success)">●</span> <span style="color:var(--accent)">meilisearch</span> (PID 48312) CPU 1.8% MEM 156MB</div>
        <div>│  ├─ meilisearch: indexer (48314)</div>
        <div>│  └─ meilisearch: scheduler (48315)</div>
        <div>├─ <span style="color:var(--success)">●</span> <span style="color:var(--accent)">node</span> (PID 48320) CPU 7.4% MEM 210MB</div>
        <div>│  ├─ node: qwik dev server (48322)</div>
        <div>│  └─ node: vite hmr (48323)</div>
        <div>└─ <span style="color:var(--error)">●</span> <span style="color:var(--text-disabled)">sqlserver</span> (stopped)</div>
        <div style="margin-top:8px;color:var(--text-disabled)">Total: 5 services · 12 processes · CPU 11.6% · MEM 462MB</div>
      </div>
    </div>`;
  }

  // Table mode (default) — fixed alignment
  return `<div style="padding:0 16px">${modeBar}
    <div class="tui-resource" style="margin-bottom:4px"><span style="width:40px;color:var(--text-muted)">CPU</span><div class="tui-bar" style="max-width:400px"><div class="tui-bar-fill" style="width:12%"></div></div><span style="width:120px;text-align:right">12% (4 cores)</span></div>
    <div class="tui-resource" style="margin-bottom:4px"><span style="width:40px;color:var(--text-muted)">MEM</span><div class="tui-bar" style="max-width:400px"><div class="tui-bar-fill" style="width:14%"></div></div><span style="width:120px;text-align:right">462MB / 32GB</span></div>
    <div class="tui-resource" style="margin-bottom:4px"><span style="width:40px;color:var(--text-muted)">DSK</span><div class="tui-bar" style="max-width:400px"><div class="tui-bar-fill" style="width:3%"></div></div><span style="width:120px;text-align:right">2.0GB total</span></div>
    <div class="tui-resource" style="margin-bottom:8px"><span style="width:40px;color:var(--text-muted)">NET</span><div class="tui-bar" style="max-width:400px"><div class="tui-bar-fill" style="width:1%"></div></div><span style="width:120px;text-align:right">↑12KB/s ↓45KB/s</span></div>

    <div style="font-size:11px;color:var(--text-muted);font-weight:600;margin:8px 0 4px">Per-Service</div>
    <table style="width:100%;font-size:11px;font-family:'JetBrains Mono',monospace;border-collapse:collapse">
      <tr style="color:var(--text-disabled);font-size:10px;text-transform:uppercase"><td style="padding:4px 8px;width:120px">SERVICE</td><td style="width:60px;text-align:right;padding:4px 8px">CPU</td><td style="width:70px;text-align:right;padding:4px 8px">MEM</td><td style="width:70px;text-align:right;padding:4px 8px">DISK</td><td style="width:50px;text-align:center;padding:4px 8px">CELL</td><td style="width:50px;text-align:center;padding:4px 8px">PROCS</td></tr>
      <tr style="border-top:1px solid var(--border)"><td style="padding:4px 8px;font-weight:600">PostgreSQL</td><td style="text-align:right;padding:4px 8px">2.1%</td><td style="text-align:right;padding:4px 8px">84MB</td><td style="text-align:right;padding:4px 8px">180MB</td><td style="text-align:center;padding:4px 8px;color:var(--success)">●</td><td style="text-align:center;padding:4px 8px">5</td></tr>
      <tr style="border-top:1px solid var(--border)"><td style="padding:4px 8px;font-weight:600">Redis</td><td style="text-align:right;padding:4px 8px">0.3%</td><td style="text-align:right;padding:4px 8px">12MB</td><td style="text-align:right;padding:4px 8px">2MB</td><td style="text-align:center;padding:4px 8px;color:var(--success)">●</td><td style="text-align:center;padding:4px 8px">1</td></tr>
      <tr style="border-top:1px solid var(--border)"><td style="padding:4px 8px;font-weight:600">Meilisearch</td><td style="text-align:right;padding:4px 8px">1.8%</td><td style="text-align:right;padding:4px 8px">156MB</td><td style="text-align:right;padding:4px 8px">45MB</td><td style="text-align:center;padding:4px 8px;color:var(--success)">●</td><td style="text-align:center;padding:4px 8px">3</td></tr>
      <tr style="border-top:1px solid var(--border)"><td style="padding:4px 8px;font-weight:600">Node.js</td><td style="text-align:right;padding:4px 8px">7.4%</td><td style="text-align:right;padding:4px 8px">210MB</td><td style="text-align:right;padding:4px 8px">18MB</td><td style="text-align:center;padding:4px 8px;color:var(--text-disabled)">○</td><td style="text-align:center;padding:4px 8px">3</td></tr>
      <tr style="border-top:1px solid var(--border);color:var(--text-disabled)"><td style="padding:4px 8px;font-weight:600">SQL Server</td><td style="text-align:right;padding:4px 8px">—</td><td style="text-align:right;padding:4px 8px">—</td><td style="text-align:right;padding:4px 8px">—</td><td style="text-align:center;padding:4px 8px">—</td><td style="text-align:center;padding:4px 8px">—</td></tr>
    </table>
  </div>`;
}

window._tuiAIProvider = window._tuiAIProvider || 0;
const TUI_AI_PROVIDERS = ['Groq (Llama 3.3 70B)','Cerebras (Qwen3 235B)','Cloudflare Workers AI','Ollama (local)'];

function tuiAIChatTab() {
  const provBar = `<div style="display:flex;gap:3px;margin-bottom:6px;font-size:10px">${TUI_AI_PROVIDERS.map((p,i)=>
    `<span style="padding:2px 6px;border-radius:3px;cursor:pointer;${i===window._tuiAIProvider?'background:var(--accent);color:#fff':'background:var(--bg-tertiary);color:var(--text-muted)'}" onclick="window._tuiAIProvider=${i};render()">${p}</span>`
  ).join('')}</div>`;

  return `<div class="tui-ai-panel">
    <div style="display:flex;justify-content:space-between;margin-bottom:4px;font-size:11px">
      <span style="color:var(--text-muted);font-weight:600">AI Assistant</span>
      <div style="display:flex;gap:4px">
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;background:var(--bg-tertiary);color:var(--text-muted)" onclick="window._tuiAIProvider=(window._tuiAIProvider+1)%4;render()">Tab:provider</span>
        <span style="padding:2px 8px;border-radius:3px;cursor:pointer;background:var(--bg-tertiary);color:var(--text-muted)" onclick="window._aiHistory=[{role:'assistant',content:'Chat cleared. How can I help?'}];render()">^L:clear</span>
      </div>
    </div>
    ${provBar}
    <div class="tui-ai-scroll" style="border:1px solid var(--border);border-radius:4px;padding:8px;background:var(--bg-primary);min-height:160px;max-height:250px;overflow-y:auto;font-size:11px">
      ${aiChatHTML(true)}
    </div>
    <div class="tui-ai-input">
      <span style="color:var(--accent);font-size:11px">></span>
      <input id="tui-ai-input" placeholder="Ask about your environment..." style="font-size:11px" onkeydown="if(event.key==='Enter'){sendAIMessage(this.value);this.value=''}">
    </div>
  </div>`;
}

function renderTUI() {
  const tabs=TUI_TABS.map((t,i)=>`<span class="tui-tab ${i===window._tuiTab?'active':''}" data-testid="tui-tab-${t.toLowerCase().replace(/\s+/g,'-')}" onclick="window._tuiTab=${i};render()">${t}</span>`).join('');
  return `<div class="screen active" style="max-width:960px"><div class="tui-window">
    <div class="tui-header"><span><b>⚡ rawenv</b> my-app</span><span>4/5 running · CPU 12% · MEM 462MB · q:quit</span></div>
    <div class="tui-tabs">${tabs}</div>
    ${tuiTabContent()}
    <div class="tui-statusbar"><span><b style="color:var(--accent)">rawenv v0.1.0</b> Tab:switch j/k:nav Enter:toggle 1-5:tabs ?:help</span><span style="color:var(--success)">● utilio.test</span></div>
  </div></div>`;
}
