function navigate(screen) { window._screen=screen; render(); updateNav(); }
function installerNext(step) { window._screen='installer-'+step; render(); }
function selectService(i) { window._selectedSvc=i; render(); }
function switchTab(el) { el.parentElement.querySelectorAll('.tab').forEach(t=>t.classList.remove('active')); el.classList.add('active'); }
function switchTuiTab(el) { el.parentElement.querySelectorAll('.tui-tab').forEach(t=>t.classList.remove('active')); el.classList.add('active'); }
function toggleSvc(el) { el.classList.toggle('on'); el.classList.toggle('off'); }
function toggleAll(a) { document.querySelectorAll('.toggle').forEach(t=>{t.classList.remove('on','off');t.classList.add(a==='start'?'on':'off')}); }
function setTheme(t) {
  window._theme=t;
  document.body.className=t==='light'?'light':'';
  document.querySelectorAll('.theme-btn').forEach(b=>b.classList.toggle('active',b.dataset.theme===t));
  render();
}

function render() {
  const c=document.getElementById('screen-container');
  const s=window._screen, os=window._os;
  if(s.startsWith('installer-')) c.innerHTML=renderInstaller(s.replace('installer-',''));
  else if(s==='project-scan') c.innerHTML=renderProjectScan();
  else if(s==='project-list') c.innerHTML=renderProjectList();
  else if(s==='project-setup') c.innerHTML=renderProjectSetup();
  else if(s==='project-installing') c.innerHTML=renderProjectInstalling();
  else if(s==='tui-services') c.innerHTML=renderTUI();
  else if(s==='gui-dashboard') c.innerHTML=renderGUIDashboard(os);
  else if(s==='menubar') c.innerHTML=renderMenuBar();
  else if(s==='gui-settings') c.innerHTML=renderSettings(os);
  else if(s==='deploy') c.innerHTML=renderDeploy();
  else if(s==='tunnel') c.innerHTML=renderTunnel();
  else if(s==='ai-chat') c.innerHTML=renderAIChat();
  else if(s==='connections') c.innerHTML=renderConnections();
  else if(s==='uninstall') c.innerHTML=renderUninstall();
}

function updateNav() {
  document.querySelectorAll('.nav-btn:not(.os-btn):not(.theme-btn)').forEach(b=>{
    const ds=b.dataset.screen||'---';
    b.classList.toggle('active', ds===window._screen || window._screen.startsWith(ds));
  });
}

document.querySelectorAll('.nav-btn').forEach(btn=>{
  btn.addEventListener('click',()=>{
    if(btn.classList.contains('os-btn')){
      window._os=btn.dataset.os;
      document.querySelectorAll('.os-btn').forEach(b=>b.classList.remove('active'));
      btn.classList.add('active'); render();
    } else if(btn.classList.contains('theme-btn')) return;
    else if(btn.dataset.screen) navigate(btn.dataset.screen);
  });
});

document.addEventListener('keydown',e=>{
  if(!window._screen.startsWith('tui')) return;
  if(e.key==='j'||e.key==='ArrowDown'){window._selectedSvc=Math.min(window._selectedSvc+1,SERVICES.length-1);render();}
  if(e.key==='k'||e.key==='ArrowUp'){window._selectedSvc=Math.max(window._selectedSvc-1,0);render();}
});

render(); updateNav();

// Live theme color application (fires on input, not just change — works while dragging)
function applyThemeColor(varName, value) {
  document.documentElement.style.setProperty(varName, value);
  // Update theme file preview
  const id = 'tv-' + varName.replace('--','');
  const el = document.getElementById(id);
  if(el) el.textContent = value;
}
function applyThemeVar(varName, value) {
  document.documentElement.style.setProperty(varName, value);
}

// Update preview panel to reflect all theme changes
function updatePreview() {
  const p = document.getElementById('theme-preview');
  if (!p) return;
  // Force re-render of preview by toggling a class
  p.style.fontSize = getComputedStyle(document.documentElement).getPropertyValue('--font-size') || '13px';
  // Update all swatches to use current radius
  p.querySelectorAll('.swatch').forEach(s => {
    s.style.borderRadius = getComputedStyle(document.documentElement).getPropertyValue('--radius-sm');
  });
}

// WCAG contrast ratio checker
function luminance(hex) {
  const rgb = [parseInt(hex.slice(1,3),16)/255, parseInt(hex.slice(3,5),16)/255, parseInt(hex.slice(5,7),16)/255];
  const lin = rgb.map(c => c <= 0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055, 2.4));
  return 0.2126*lin[0] + 0.7152*lin[1] + 0.0722*lin[2];
}
function contrastRatio(hex1, hex2) {
  const l1 = luminance(hex1), l2 = luminance(hex2);
  const lighter = Math.max(l1,l2), darker = Math.min(l1,l2);
  return (lighter + 0.05) / (darker + 0.05);
}
function contrastWarning(fg, bg, label) {
  const ratio = contrastRatio(fg, bg);
  const r = ratio.toFixed(1);
  if (ratio >= 7) return `<div class="contrast-badge contrast-aaa">✓ ${label}: ${r}:1 AAA</div>`;
  if (ratio >= 4.5) return `<div class="contrast-badge contrast-aa">✓ ${label}: ${r}:1 AA</div>`;
  if (ratio >= 3) return `<div class="contrast-badge contrast-low">⚠️ ${label}: ${r}:1 — hard to read, try ${luminance(fg)>luminance(bg)?'darker':'lighter'}</div>`;
  return `<div class="contrast-badge contrast-fail">🚨 ${label}: ${r}:1 — nearly invisible! Your eyes will hate you</div>`;
}
function getThemeColor(varName, fallback) {
  return getComputedStyle(document.documentElement).getPropertyValue(varName).trim() || fallback;
}
function updateContrastWarnings() {
  const el = document.getElementById('contrast-warnings');
  if (!el) return;
  const bg = getThemeColor('--bg-primary','#0f0f14');
  const bgSec = getThemeColor('--bg-secondary','#16161e');
  const text = getThemeColor('--text','#e2e4f0');
  const muted = getThemeColor('--text-muted','#8b8da6');
  const accent = getThemeColor('--accent','#6366f1');
  const success = getThemeColor('--success','#34d399');
  const error = getThemeColor('--error','#f87171');
  const warning = getThemeColor('--warning','#fbbf24');
  el.innerHTML =
    contrastWarning(text, bg, 'Text on background') +
    contrastWarning(muted, bg, 'Muted text on background') +
    contrastWarning(accent, bg, 'Accent on background') +
    contrastWarning(success, bg, 'Success on background') +
    contrastWarning(error, bg, 'Error on background') +
    contrastWarning(warning, bg, 'Warning on background') +
    contrastWarning('#ffffff', accent, 'White on accent buttons');
}
// Hook into color changes
const _origApply = window.applyThemeColor;
window.applyThemeColor = function(v, val) {
  _origApply(v, val);
  setTimeout(updateContrastWarnings, 50);
};
