// Extended settings pages — theme preview, extensions, config editor

function settingsThemePage() {
  return `<div class="settings-page-title">Theme</div><div class="settings-page-desc">Customize appearance. All changes preview live below.</div>
    <div style="display:flex;gap:24px">
      <div style="flex:1">
        <div class="settings-section"><h3>Mode</h3>
          <div class="setting-row"><div><div class="setting-label">Color mode</div></div><select class="setting-input" style="width:120px" onchange="setTheme(this.value)"><option value="dark" ${window._theme==='dark'?'selected':''}>Dark</option><option value="light" ${window._theme==='light'?'selected':''}>Light</option><option value="system">System</option></select></div>
        </div>
        <div class="settings-section"><h3>Colors</h3>
          <div class="setting-row"><div><div class="setting-label">Accent</div></div><input type="color" value="#6366f1" class="color-picker" oninput="applyThemeColor('--accent',this.value)"></div>
          <div class="setting-row"><div><div class="setting-label">Success</div></div><input type="color" value="#34d399" class="color-picker" oninput="applyThemeColor('--success',this.value)"></div>
          <div class="setting-row"><div><div class="setting-label">Error</div></div><input type="color" value="#f87171" class="color-picker" oninput="applyThemeColor('--error',this.value)"></div>
          <div class="setting-row"><div><div class="setting-label">Warning</div></div><input type="color" value="#fbbf24" class="color-picker" oninput="applyThemeColor('--warning',this.value)"></div>
          <div class="setting-row"><div><div class="setting-label">Info</div></div><input type="color" value="#60a5fa" class="color-picker" oninput="applyThemeColor('--info',this.value)"></div>
          <div class="setting-row"><div><div class="setting-label">Background</div></div><input type="color" value="#0f0f14" class="color-picker" oninput="applyThemeColor('--bg-primary',this.value)"></div>
        </div>
        <div class="settings-section"><h3>Accessibility</h3>
        <div id="contrast-warnings" class="contrast-warnings"></div>
        <script>setTimeout(updateContrastWarnings,100)</script>
      </div>
      <div class="settings-section"><h3>Layout</h3>
          <div class="setting-row"><div><div class="setting-label">Border radius</div></div><input type="range" min="0" max="16" value="8" class="range-input" oninput="applyThemeVar('--radius-md',this.value+'px');applyThemeVar('--radius-lg',(parseInt(this.value)+4)+'px');applyThemeVar('--radius-sm',Math.max(0,this.value-4)+'px');this.nextElementSibling.textContent=this.value+'px';updatePreview()"><span class="mono" style="font-size:11px;width:40px">8px</span></div>
          <div class="setting-row"><div><div class="setting-label">Font size</div></div><input type="range" min="11" max="16" value="13" class="range-input" oninput="document.documentElement.style.setProperty('--font-size',this.value+'px');this.nextElementSibling.textContent=this.value+'px';updatePreview()"><span class="mono" style="font-size:11px;width:40px">13px</span></div>
        </div>
        <div class="settings-section"><h3>Theme File</h3>
          <div style="padding:10px;background:var(--bg-secondary);border-radius:8px;font-family:'JetBrains Mono',monospace;font-size:10px;color:var(--text-muted);line-height:1.6">
            <span style="color:var(--text-disabled)"># .rawenv/theme.toml</span><br>
            [mode]<br>scheme = "${window._theme}"<br><br>
            [colors]<br>accent = "<span id="tv-accent">#6366f1</span>"<br>success = "<span id="tv-success">#34d399</span>"<br>error = "<span id="tv-error">#f87171</span>"<br><br>
            [layout]<br>border_radius = <span id="tv-radius">8</span><br>font_size = <span id="tv-fontsize">13</span>
          </div>
          <div style="margin-top:8px;display:flex;gap:6px"><button class="btn btn-sm btn-secondary">Export</button><button class="btn btn-sm btn-secondary">Import</button><button class="btn btn-sm btn-secondary">Reset</button></div>
        </div>
      </div>
      <div style="width:320px">
        <div class="theme-preview" id="theme-preview" style="transition:all .15s">
          <div class="theme-preview-title">Live Preview</div>
          <div class="preview-card" style="border-radius:var(--radius-md);transition:all .15s">
            ${svcDot('running')}
            <div style="flex:1"><div style="font-weight:600;font-size:13px">PostgreSQL</div><div class="mono" style="font-size:10px;color:var(--text-muted)">:5432 · 84MB</div></div>
            <span style="font-size:10px;color:var(--success)">running</span>
          </div>
          <div class="preview-card" style="border-radius:var(--radius-md);transition:all .15s">
            ${svcDot('stopped')}
            <div style="flex:1"><div style="font-weight:600;font-size:13px;color:var(--text-disabled)">SQL Server</div><div class="mono" style="font-size:10px;color:var(--text-disabled)">:1433</div></div>
            <span style="font-size:10px;color:var(--error)">stopped</span>
          </div>
          <div style="display:flex;gap:6px;margin:8px 0">
            <button class="preview-btn" style="background:var(--accent);color:#fff;border-radius:var(--radius-sm);transition:all .15s">Primary</button>
            <button class="preview-btn" style="background:var(--bg-tertiary);color:var(--text-muted);border-radius:var(--radius-sm);transition:all .15s">Secondary</button>
            <button class="preview-btn" style="background:var(--error);color:#fff;border-radius:var(--radius-sm);transition:all .15s">Danger</button>
          </div>
          <div style="margin:8px 0">
            <div style="height:6px;background:var(--bg-tertiary);border-radius:var(--radius-sm)"><div style="height:100%;width:45%;background:var(--accent);border-radius:var(--radius-sm)"></div></div>
          </div>
          <div style="display:flex;gap:6px;margin:8px 0">
            ${toggle(true)} ${toggle(false)}
          </div>
          <div style="margin:8px 0;padding:8px;background:var(--bg-tertiary);border-radius:var(--radius-md);font-family:'JetBrains Mono',monospace;font-size:var(--font-size,10px);transition:all .15s">
            <span class="log-time">14:23:01</span> <span style="color:var(--text-muted)">LOG: ready</span><br>
            <span class="log-time">14:30:44</span> <span style="color:var(--warning)">WARN: slow query</span><br>
            <span class="log-time">14:35:02</span> <span style="color:var(--error)">ERR: connection refused</span>
          </div>
          <div class="preview-swatch">
            <div class="swatch" style="background:var(--accent);border-radius:var(--radius-sm);transition:all .15s"></div>
            <div class="swatch" style="background:var(--success)"></div>
            <div class="swatch" style="background:var(--warning)"></div>
            <div class="swatch" style="background:var(--error)"></div>
            <div class="swatch" style="background:var(--info)"></div>
            <div class="swatch" style="background:var(--bg-primary)"></div>
            <div class="swatch" style="background:var(--bg-secondary)"></div>
            <div class="swatch" style="background:var(--text)"></div>
          </div>
        </div>
      </div>
    </div>`;
}

function settingsServiceDetailPage() {
  const s=SERVICES[window._selectedSvc];
  window._svcConfigTab = window._svcConfigTab||'visual';
  window._svcConfigCat = window._svcConfigCat||'connection';

  const phpExts=[
    {name:'opcache',desc:'Bytecode caching for performance',installed:true,icon:'⚡'},
    {name:'pdo_pgsql',desc:'PostgreSQL driver for PDO',installed:true,icon:'🐘'},
    {name:'redis',desc:'PHP Redis extension (phpredis)',installed:true,icon:'🔴'},
    {name:'imagick',desc:'ImageMagick image processing',installed:false,icon:'🖼️'},
    {name:'xdebug',desc:'Debugging and profiling',installed:false,icon:'🐛'},
    {name:'memcached',desc:'Memcached client library',installed:false,icon:'💾'},
    {name:'mongodb',desc:'MongoDB driver',installed:false,icon:'🍃'},
    {name:'grpc',desc:'gRPC PHP extension',installed:false,icon:'📡'},
    {name:'swoole',desc:'Async I/O and coroutines',installed:false,icon:'🚀'},
    {name:'apcu',desc:'User-land data cache',installed:false,icon:'📦'},
  ];

  const pgConfigs = {
    connection:[
      {key:'listen_addresses',type:'string',val:'127.0.0.1',default:'localhost',range:'IP addresses or *',desc:'Specifies the TCP/IP address(es) on which the server is to listen for connections.',doc:'https://www.postgresql.org/docs/18/runtime-config-connection.html#GUC-LISTEN-ADDRESSES'},
      {key:'port',type:'integer',val:'5432',default:'5432',range:'1-65535',desc:'The TCP port the server listens on.',doc:'https://www.postgresql.org/docs/18/runtime-config-connection.html#GUC-PORT'},
      {key:'max_connections',type:'integer',val:'20',default:'100',range:'1-262143',desc:'Maximum number of concurrent connections. rawenv optimized this from 100 to 20 based on your usage.',doc:'https://www.postgresql.org/docs/18/runtime-config-connection.html#GUC-MAX-CONNECTIONS'},
      {key:'unix_socket_directories',type:'string',val:'.rawenv/run/',default:'/tmp',range:'directory path',desc:'Directory for Unix-domain socket connections.',doc:'https://www.postgresql.org/docs/18/runtime-config-connection.html#GUC-UNIX-SOCKET-DIRECTORIES'},
    ],
    memory:[
      {key:'shared_buffers',type:'size',val:'64MB',default:'128MB',range:'128kB-8GB',desc:'Amount of memory for shared memory buffers. rawenv set this to 64MB for dev workloads.',doc:'https://www.postgresql.org/docs/18/runtime-config-resource.html#GUC-SHARED-BUFFERS'},
      {key:'work_mem',type:'size',val:'4MB',default:'4MB',range:'64kB-2GB',desc:'Memory for internal sort operations and hash tables before writing to temp files.',doc:'https://www.postgresql.org/docs/18/runtime-config-resource.html#GUC-WORK-MEM'},
      {key:'maintenance_work_mem',type:'size',val:'64MB',default:'64MB',range:'1MB-2GB',desc:'Maximum memory for maintenance operations like VACUUM and CREATE INDEX.',doc:'https://www.postgresql.org/docs/18/runtime-config-resource.html#GUC-MAINTENANCE-WORK-MEM'},
      {key:'effective_cache_size',type:'size',val:'256MB',default:'4GB',range:'8kB-8TB',desc:'Planner estimate of effective OS cache size. Affects query planning.',doc:'https://www.postgresql.org/docs/18/runtime-config-query.html#GUC-EFFECTIVE-CACHE-SIZE'},
    ],
    logging:[
      {key:'log_destination',type:'enum',val:'stderr',default:'stderr',range:'stderr, csvlog, jsonlog, syslog',desc:'Where to send server log output.',doc:'https://www.postgresql.org/docs/18/runtime-config-logging.html#GUC-LOG-DESTINATION'},
      {key:'logging_collector',type:'boolean',val:'on',default:'off',range:'on/off',desc:'Enable log collection into files.',doc:'https://www.postgresql.org/docs/18/runtime-config-logging.html#GUC-LOGGING-COLLECTOR'},
      {key:'log_directory',type:'string',val:'.rawenv/logs/postgresql/',default:'log',range:'directory path',desc:'Directory for log files when logging_collector is on.',doc:'https://www.postgresql.org/docs/18/runtime-config-logging.html#GUC-LOG-DIRECTORY'},
      {key:'log_min_duration_statement',type:'integer',val:'-1',default:'-1',range:'-1 (disabled) to INT_MAX ms',desc:'Log statements running longer than this. -1 disables.',doc:'https://www.postgresql.org/docs/18/runtime-config-logging.html#GUC-LOG-MIN-DURATION-STATEMENT'},
    ],
    storage:[
      {key:'data_directory',type:'string',val:'.rawenv/data/postgresql/',default:'/var/lib/postgresql/data',range:'directory path',desc:'Location of the database cluster data.',doc:'https://www.postgresql.org/docs/18/runtime-config-file-locations.html#GUC-DATA-DIRECTORY'},
    ],
  };

  const cats=Object.keys(pgConfigs);
  const catLabels={connection:'Connection',memory:'Memory',logging:'Logging',storage:'Storage'};
  const currentConfigs=pgConfigs[window._svcConfigCat]||pgConfigs.connection;

  const configVisual=currentConfigs.map(c=>{
    let control='';
    if(c.type==='integer') control=`<input class="setting-input" value="${c.val}" style="width:80px"><span class="config-range-info">${c.range} · default: ${c.default}</span>`;
    else if(c.type==='size') control=`<input class="setting-input" value="${c.val}" style="width:80px"><span class="config-range-info">${c.range} · default: ${c.default}</span>`;
    else if(c.type==='boolean') control=`${toggle(c.val==='on')}<span class="config-range-info">default: ${c.default}</span>`;
    else if(c.type==='enum') control=`<select class="setting-input" style="width:140px">${c.range.split(', ').map(o=>`<option ${o===c.val?'selected':''}>${o}</option>`).join('')}</select><span class="config-range-info">default: ${c.default}</span>`;
    else control=`<input class="setting-input" value="${c.val}" style="width:200px"><span class="config-range-info">default: ${c.default}</span>`;
    return `<div class="config-item">
      <div class="config-item-header"><span class="config-key">${c.key}</span><span class="config-type">${c.type}</span></div>
      <div class="config-desc">${c.desc}</div>
      <a class="config-doc-link" href="${c.doc}" target="_blank">📖 PostgreSQL docs →</a>
      <div class="config-control">${control}</div>
    </div>`;
  }).join('');

  const rawConfig=Object.values(pgConfigs).flat().map(c=>`${c.key} = ${c.val}`).join('\n');

  const configContent = window._svcConfigTab==='raw'
    ? `<textarea class="config-raw"># postgresql.conf — rawenv managed\n# Edit directly. Changes apply on service restart.\n\n${rawConfig}</textarea><div style="margin-top:8px;display:flex;gap:6px"><button class="btn btn-sm btn-primary">Save & Restart</button><button class="btn btn-sm btn-secondary">Validate</button><button class="btn btn-sm btn-secondary">Reset to rawenv defaults</button></div>`
    : `<div class="config-editor">
        <div class="config-sidebar">${cats.map(c=>`<div class="config-cat ${window._svcConfigCat===c?'active':''}" onclick="window._svcConfigCat='${c}';render()">${catLabels[c]} (${pgConfigs[c].length})</div>`).join('')}</div>
        <div class="config-main">${configVisual}</div>
      </div>`;

  const extContent=phpExts.map(e=>`<div class="ext-card ${e.installed?'installed':''}">
    <span class="ext-icon">${e.icon}</span>
    <div class="ext-info">
      <div class="ext-name">${e.name}</div>
      <div class="ext-desc">${e.desc}</div>
      <div class="ext-actions">${e.installed
        ?'<button class="btn btn-sm btn-secondary" style="color:var(--error)">Remove</button><button class="btn btn-sm btn-secondary">Config</button>'
        :'<button class="btn btn-sm btn-primary">Install</button>'}</div>
    </div>
  </div>`).join('');

  return `<div class="settings-page-title">${s.icon} ${s.name} ${s.version}</div>
    <div class="settings-page-desc">Port ${s.port} · ${s.status} · Cell: ${s.status==='running'?'isolated':'—'}</div>
    <div class="config-tab-bar">
      <div class="config-tab ${window._svcDetailTab==='config'||!window._svcDetailTab?'active':''}" onclick="window._svcDetailTab='config';window._svcConfigTab='visual';render()">⚙️ Configuration</div>
      <div class="config-tab ${window._svcDetailTab==='extensions'?'active':''}" onclick="window._svcDetailTab='extensions';render()">🧩 Extensions</div>
      <div class="config-tab ${window._svcDetailTab==='logs'?'active':''}" onclick="window._svcDetailTab='logs';render()">📋 Logs</div>
    </div>
    ${window._svcDetailTab==='extensions'?`
      <div class="ext-search"><input class="setting-input" placeholder="Search extensions..." style="flex:1"><button class="btn btn-sm btn-secondary" onclick="showBrowsePECL()">Browse PECL</button></div>
      <div class="ext-filter">
        <span class="ext-filter-btn active">All</span>
        <span class="ext-filter-btn">Installed (3)</span>
        <span class="ext-filter-btn">Available</span>
        <span class="ext-filter-btn">Database</span>
        <span class="ext-filter-btn">Cache</span>
        <span class="ext-filter-btn">Debug</span>
      </div>
      <div class="ext-grid">${extContent}</div>
    `:window._svcDetailTab==='logs'?`
      <div class="log-viewer" style="height:400px">${logHTML()}</div>
    `:`
      <div class="config-tab-bar" style="margin-top:0">
        <div class="config-tab ${window._svcConfigTab!=='raw'?'active':''}" onclick="window._svcConfigTab='visual';render()">Visual Editor</div>
        <div class="config-tab ${window._svcConfigTab==='raw'?'active':''}" onclick="window._svcConfigTab='raw';render()">Raw Config File</div>
      </div>
      ${configContent}
    `}`;
}
