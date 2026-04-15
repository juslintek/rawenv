function renderAIChat() {
  const os=currentOS();
  return `<div class="screen active"><div class="window ${os}-chrome">${titlebar(os,'rawenv — AI Assistant')}
    ${breadcrumb([{label:'Dashboard',screen:'gui-dashboard'},{label:'AI Assistant'}])}
    <div class="gui-layout">${sidebar()}
    <div class="main-content" style="display:flex;flex-direction:column">
      <div class="content-header" style="padding:12px 24px">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <div><h1 style="font-size:16px">🤖 AI Assistant</h1><div class="content-meta">Project-aware · Free tier · No data sent to third parties</div></div>
          <div style="display:flex;gap:8px">
            <select class="setting-input" style="width:180px;font-size:11px"><option>Groq (Llama 3.3 70B)</option><option>Cerebras (Qwen3 235B)</option><option>Cloudflare Workers AI</option><option>Ollama (local)</option></select>
            <button class="btn btn-sm btn-secondary" onclick="window._aiHistory=[{role:'assistant',content:'Chat cleared. How can I help?'}];render()">Clear</button>
          </div>
        </div>
      </div>
      <div class="ai-chat-area" style="flex:1;overflow-y:auto;padding:16px 24px">
        ${aiChatHTML(false)}
      </div>
      <div class="ai-input-area">
        <input class="ai-input" id="gui-ai-input" data-testid="ai-input" placeholder="Ask anything about your environment... (try: optimize memory, deploy to hetzner, enable redis persistence)" onkeydown="if(event.key==='Enter'){sendAIMessage(this.value);this.value=''}">
        <button class="btn btn-primary btn-sm" data-testid="ai-send" onclick="const i=document.getElementById('gui-ai-input');sendAIMessage(i.value);i.value=''">Send</button>
      </div>
    </div></div></div></div>`;
}
