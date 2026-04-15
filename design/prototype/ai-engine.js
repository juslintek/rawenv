// Real AI chat using Groq free API (Llama 3.3 70B)
const GROQ_KEY = 'GROQ_API_KEY_HERE';
const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';

const AI_SYSTEM_PROMPT = `You are rawenv AI assistant — a built-in helper for the rawenv development environment manager. rawenv manages native (no Docker) dev environments with OS-level isolation.

Current project: "utilio" at ~/Projects/GOTAS/utilio
Stack: Node.js 22.15 (Qwik), PHP 8.4, PostgreSQL 18.2 (:5432, 84MB, cell:isolated), Redis 7.4 (:6379, 12MB), Meilisearch 1.14 (:7700, 156MB), SQL Server 2025 (stopped)
Total footprint: 462MB. OS: macOS (Apple Silicon). Isolation: Seatbelt sandbox.
DNS: utilio.test → 127.0.0.1

Be concise. Use monospace for commands/paths. Suggest optimizations proactively.`;

window._aiHistory = window._aiHistory || [
  {role:'assistant', content:'👋 I\'m your rawenv AI assistant. I can see your utilio project is running 4/5 services using 462MB total.\n\n💡 **Proactive:** Your PostgreSQL has `max_connections=20` but only 3 active — already optimized. Redis has no persistence configured — cached data will be lost on restart. Want me to enable AOF?'}
];

async function sendAIMessage(input) {
  if (!input.trim()) return;
  window._aiHistory.push({role:'user', content: input});
  render();

  // Scroll to bottom
  setTimeout(()=>{
    const el = document.querySelector('.ai-chat-area,.tui-ai-scroll');
    if(el) el.scrollTop = el.scrollHeight;
  }, 50);

  // Try Groq, fallback to mock
  try {
    const messages = [{role:'system',content:AI_SYSTEM_PROMPT}, ...window._aiHistory.map(m=>({role:m.role==='assistant'?'assistant':'user',content:m.content}))];

    // Try Groq first
    let resp = await fetch(GROQ_URL, {
      method:'POST',
      headers:{'Content-Type':'application/json','Authorization':'Bearer '+GROQ_KEY},
      body:JSON.stringify({model:'llama-3.3-70b-versatile',messages,max_tokens:500,temperature:0.7})
    });

    if (!resp.ok) {
      // Fallback to Cerebras
      resp = await fetch('https://api.cerebras.ai/v1/chat/completions', {
        method:'POST',
        headers:{'Content-Type':'application/json','Authorization':'Bearer CEREBRAS_API_KEY_HERE'},
        body:JSON.stringify({model:'llama-3.3-70b',messages,max_tokens:500,temperature:0.7})
      });
    }

    if (resp.ok) {
      const data = await resp.json();
      window._aiHistory.push({role:'assistant', content: data.choices[0].message.content});
    } else {
      throw new Error('Both APIs failed');
    }
  } catch(e) {
    // Mock fallback with contextual responses
    const q = input.toLowerCase();
    let reply = "I can help with that. Could you be more specific about what you'd like to do?";
    if (q.includes('redis') && q.includes('persist')) reply = "Done. Enabled AOF persistence for Redis:\n\n```\nappendonly yes\nappendfsync everysec\n```\n\nRedis restarted. Disk usage +~2MB. Data survives restarts now.";
    else if (q.includes('memory') || q.includes('optimize')) reply = "Current breakdown:\n\n| Service | Memory | Optimized? |\n|---------|--------|------------|\n| Node.js | 210MB | ✓ typical for Qwik dev |\n| Meilisearch | 156MB | ✓ indexing limit 100MB |\n| PostgreSQL | 84MB | ✓ shared_buffers=64MB |\n| Redis | 12MB | ✓ maxmemory=64mb |\n\nTotal: 462MB. Already well optimized. Only option: stop SQL Server allocation (saves 0 now, prevents 512MB later).";
    else if (q.includes('deploy') || q.includes('hetzner')) reply = "For Hetzner CX22 (2 vCPU, 4GB, €4.85/mo):\n\n```bash\nrawenv deploy generate --provider hetzner\nrawenv deploy apply\n```\n\nThis will:\n1. Create server via Hetzner API\n2. Install rawenv remotely\n3. Copy your rawenv.toml\n4. Start all services\n\nEstimated time: ~3 minutes. Want me to run it?";
    else if (q.includes('tunnel') || q.includes('public')) reply = "To expose your dev server:\n\n```bash\nrawenv tunnel 3000\n```\n\n→ `https://utilio-3000.rawenv.sh`\n\nUsing bore (built-in). Latency ~12ms. For custom domain, set `tunnel.domain` in rawenv.toml.";
    else if (q.includes('slow') || q.includes('performance')) reply = "Let me check... PostgreSQL `log_min_duration_statement` is disabled. Enable it to find slow queries:\n\n```\nlog_min_duration_statement = 100  # log queries >100ms\n```\n\nWant me to apply this? I'll also check if `pg_stat_statements` extension would help.";
    else if (q.includes('backup')) reply = "Current backup status:\n\n- PostgreSQL: auto-backup ON (before config changes)\n- Redis: no persistence (⚠️ enable AOF)\n- Meilisearch: snapshots in `.rawenv/data/meilisearch/dumps/`\n\nTo create a full backup now:\n```bash\nrawenv backup create --all\n```";
    window._aiHistory.push({role:'assistant', content: reply});
  }
  render();
  setTimeout(()=>{
    const el = document.querySelector('.ai-chat-area,.tui-ai-scroll');
    if(el) el.scrollTop = el.scrollHeight;
  }, 100);
}

function aiChatHTML(isTUI) {
  const msgs = window._aiHistory.map(m => {
    // Simple markdown-ish rendering
    let text = m.content
      .replace(/```(\w*)\n?([\s\S]*?)```/g, '<div style="margin:4px 0;padding:6px 8px;background:var(--bg-tertiary);border-radius:4px;font-family:\'JetBrains Mono\',monospace;font-size:'+(isTUI?'10':'11')+'px;white-space:pre-wrap">$2</div>')
      .replace(/`([^`]+)`/g, '<code style="background:var(--bg-tertiary);padding:1px 4px;border-radius:3px;font-size:'+(isTUI?'10':'11')+'px">$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\n/g, '<br>');

    if (m.role==='assistant') {
      return `<div class="${isTUI?'tui-ai-msg':'ai-msg ai-system'}"><${isTUI?'span class="tui-ai-system"':'div class="ai-avatar"'}>${isTUI?'⚡ rawenv:':'⚡'}</${isTUI?'span':'div'}><div class="${isTUI?'':'ai-bubble'}" style="font-size:${isTUI?'11':'13'}px;line-height:1.6">${text}</div></div>`;
    }
    return `<div class="${isTUI?'tui-ai-msg tui-ai-user':'ai-msg ai-user'}"><div class="${isTUI?'':'ai-bubble user'}" style="font-size:${isTUI?'11':'13'}px">${isTUI?'> ':''}${text}</div></div>`;
  }).join('');
  return msgs;
}
