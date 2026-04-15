// INSTALLER — only installs rawenv itself
function renderInstaller(step) {
  const steps=['welcome','install','done'];
  const idx=steps.indexOf(step);
  const dots=steps.map((_,i)=>`<span class="step-dot ${i<idx?'done':''} ${i===idx?'active':''}"></span>`).join('');
  const os=currentOS();
  const o={macos:{icon:'🍎',name:'macOS',detail:'Apple Silicon · macOS 26',svc:'launchd',iso:'Seatbelt sandbox',dns:'dnsmasq'},linux:{icon:'🐧',name:'Linux',detail:'x86_64 · Debian 13',svc:'systemd',iso:'Namespaces + Landlock',dns:'systemd-resolved'},windows:{icon:'🪟',name:'Windows',detail:'x86_64 · Windows 11',svc:'Windows Services',iso:'AppContainer',dns:'Acrylic DNS'}}[os];

  const pages={
    welcome:`<div class="installer-body">
      <div class="installer-logo">⚡</div><div class="installer-title">Install rawenv</div>
      <div class="installer-sub">Raw native dev environments. Zero overhead.<br>One binary. No dependencies. No containers.</div>
      <div class="installer-steps">${dots}</div>
      <div class="installer-content" style="text-align:left">
        <div class="detect-item"><span class="detect-icon">${o.icon}</span><div><div class="detect-name">${o.name} detected</div><div class="detect-ver">${o.detail}</div></div></div>
        <div class="detect-item"><span class="detect-icon">📦</span><div><div class="detect-name">Binary</div><div class="detect-ver">~10MB → ~/.rawenv/bin/rawenv</div></div></div>
        <div class="detect-item"><span class="detect-icon">⚙️</span><div><div class="detect-name">Service manager</div><div class="detect-ver">${o.svc} integration</div></div></div>
        <div class="detect-item"><span class="detect-icon">🔒</span><div><div class="detect-name">Isolation</div><div class="detect-ver">${o.iso}</div></div></div>
        <div class="detect-item"><span class="detect-icon">🌐</span><div><div class="detect-name">DNS</div><div class="detect-ver">${o.dns} (.test domains)</div></div></div>
        <div class="detect-item"><span class="detect-icon">🐚</span><div><div class="detect-name">Shell</div><div class="detect-ver">PATH + completions (zsh, bash, fish)</div></div></div>
      </div>
      <div class="installer-actions"><div></div><button class="btn btn-primary" data-testid="installer-install-btn" onclick="installerNext('install')">Install →</button></div></div>`,

    install:`<div class="installer-body">
      <div class="installer-title">Installing rawenv...</div>
      <div class="installer-steps">${dots}</div>
      <div class="installer-content">
        <div class="progress-bar"><div class="progress-fill" id="install-progress" style="width:0%"></div></div>
        <div id="install-steps">
          <div class="check-item"><span class="check-pending" id="s0">○</span> Downloading rawenv binary</div>
          <div class="check-item"><span class="check-pending" id="s1">○</span> Installing to ~/.rawenv/bin/</div>
          <div class="check-item"><span class="check-pending" id="s2">○</span> Registering with ${o.svc}</div>
          <div class="check-item"><span class="check-pending" id="s3">○</span> Configuring ${o.iso}</div>
          <div class="check-item"><span class="check-pending" id="s4">○</span> Setting up ${o.dns}</div>
          <div class="check-item"><span class="check-pending" id="s5">○</span> Adding to PATH + shell completions</div>
        </div>
      </div>
      <div class="installer-actions"><div></div><button class="btn btn-secondary" id="install-btn" disabled>Installing...</button></div></div>
      <script>if(!window._installRan){window._installRan=true;let i=0;const t=setInterval(()=>{const el=document.getElementById('s'+i);if(!el||i>5){clearInterval(t);window._installRan=false;const b=document.getElementById('install-btn');if(b)b.outerHTML='<button class="btn btn-primary" data-testid="installer-launch-btn" onclick="installerNext(\'done\')">Launch rawenv →</button>';return}el.className='check-done';el.textContent='✓';document.getElementById('install-progress').style.width=((i+1)/6*100)+'%';i++},350)}</script>`,

    done:`<div class="installer-body">
      <div class="installer-logo">✓</div><div class="installer-title">rawenv installed</div>
      <div class="installer-sub">Ready to go. rawenv will now scan your system for projects.</div>
      <div class="installer-steps">${dots}</div>
      <div class="installer-content" style="text-align:center">
        <div class="terminal-block">
          <div class="t-muted">$ rawenv --version</div>
          <div>rawenv 0.1.0 (${o.name} ${os==='macos'?'arm64':'x86_64'})</div>
          <div class="t-muted" style="margin-top:8px">$ rawenv</div>
          <div style="color:var(--accent)">Scanning for projects...</div>
        </div>
      </div>
      <div class="installer-actions"><div></div><button class="btn btn-primary" data-testid="installer-continue-btn" onclick="navigate('project-scan')">Continue →</button></div></div>`
  };
  return `<div class="screen active"><div class="installer-window">${titlebar(os,'rawenv installer')}${pages[step]||pages.welcome}</div></div>`;
}
