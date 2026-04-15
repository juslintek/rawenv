// Shared data
const SERVICES = [
  { name:'PostgreSQL', port:5432, version:'18.2', pid:48291, cpu:'2.1%', mem:'84MB', uptime:'2h 14m', status:'running', icon:'🐘' },
  { name:'Redis', port:6379, version:'7.4', pid:48305, cpu:'0.3%', mem:'12MB', uptime:'2h 14m', status:'running', icon:'🔴' },
  { name:'Meilisearch', port:7700, version:'1.14', pid:48312, cpu:'1.8%', mem:'156MB', uptime:'2h 14m', status:'running', icon:'🔍' },
  { name:'Node.js', port:3000, version:'22.15', pid:48320, cpu:'7.4%', mem:'210MB', uptime:'45m', status:'running', icon:'💚' },
  { name:'SQL Server', port:1433, version:'2025', pid:null, cpu:'—', mem:'—', uptime:'stopped', status:'stopped', icon:'🗄️' },
];
const LOGS = [
  { time:'14:23:01', msg:'LOG:  database system is ready to accept connections', level:'normal' },
  { time:'14:23:05', msg:'LOG:  autovacuum launcher started', level:'normal' },
  { time:'14:25:12', msg:'LOG:  connection received: host=127.0.0.1 port=52341', level:'active' },
  { time:'14:25:12', msg:'LOG:  connection authorized: user=myapp database=myapp_dev', level:'active' },
  { time:'14:30:44', msg:'WARNING:  could not open statistics file', level:'warn' },
  { time:'14:35:01', msg:'LOG:  checkpoint starting: time', level:'normal' },
  { time:'14:35:02', msg:'LOG:  checkpoint complete: wrote 42 buffers (0.3%)', level:'normal' },
  { time:'14:40:15', msg:'LOG:  connection received: host=127.0.0.1 port=52388', level:'active' },
];
const AI_MESSAGES = [
  { role:'system', text:'I detected your project uses PostgreSQL with 100 max connections but only 3 active. I can optimize this to reduce memory by ~40MB.' },
  { role:'user', text:'Yes, optimize it' },
  { role:'system', text:'Done. Set max_connections=20, shared_buffers=64MB. PostgreSQL restarted. Memory usage dropped from 84MB to 48MB.' },
  { role:'user', text:'How do I deploy this to Hetzner?' },
  { role:'system', text:'I can generate Terraform configs for a Hetzner CX22 (2 vCPU, 4GB RAM, €4.85/mo). Run `rawenv deploy generate --provider hetzner` then `rawenv deploy apply`. Want me to do it?' },
];
window._os = 'macos';
window._screen = 'installer-welcome';
window._selectedSvc = 0;
window._theme = 'dark';
function currentOS() { return window._os; }
