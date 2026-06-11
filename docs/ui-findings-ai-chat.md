# UI Exploration — AI Chat (message flow, provider switching, context awareness)

**Story:** UI-005 — Explore AI Chat: message flow, provider switching, context
awareness
**Date:** 2026-06-11
**Surface explored:** `design/prototype/` interactive HTML prototype (the design
source-of-truth for the GUI/TUI AI assistant). Served locally with
`python3 -m http.server 8799` and driven through the in-page `navigate()` router
and `eval`-based DOM introspection (pinchtab headless browser).
**Files behind this flow:**
- `design/prototype/screens-ai.js` — GUI AI chat screen (`renderAIChat`).
- `design/prototype/ai-engine.js` — `sendAIMessage()`, `aiChatHTML()`, system
  prompt, mock fallback, shared `window._aiHistory`.
- `design/prototype/screens-tui.js` — TUI "AI Chat" tab (`tuiAIChatTab`, tab 5).
- `design/prototype/app.js` — router (`navigate`, `render`).
- Native (Zig) counterpart: `src/ai/{chat,provider,context,cascade,proactive}.zig`.

**Verification legend:**
- ✅ *live* — observed at runtime in the browser via DOM/`eval`.
- 📄 *source* — determined from authoritative prototype source (deterministic
  code path). Live re-confirmation of the **async** send path was blocked by an
  aggressive idle-tab reaper in the automation harness (the same one noted in
  `docs/ui-settings-exploration.md`), but the logic is unambiguous.

---

## 1. How to reach the screen

- **GUI:** nav button `data-testid="nav-ai"` → screen `ai-chat`
  (`navigate('ai-chat')` → `renderAIChat()`). Breadcrumb: Dashboard › AI Assistant.
- **TUI:** screen `tui-services`, tab index 4 — `data-testid="tui-tab-ai-chat"`
  ("AI Chat"). Renders `tuiAIChatTab()`.
- Both GUI and TUI render the **same** conversation via `aiChatHTML(isTUI)` over
  the shared `window._aiHistory` array. ✅ live (GUI), 📄 source (TUI).

---

## 2. Layout (GUI) — observed

`renderAIChat()` builds an OS-chromed window with the standard sidebar +
`main-content` fl/column:

```
┌ rawenv — AI Assistant ───────────────────────────────────────┐
│ 🤖 AI Assistant                          [provider ▼] [Clear] │
│ Project-aware · Free tier · No data sent to third parties     │
├───────────────────────────────────────────────────────────────┤
│  ⚡  <assistant bubbles>                                       │
│                                   <user bubbles (right)>  🧑    │
│  … scrollable .ai-chat-area …                                 │
├───────────────────────────────────────────────────────────────┤
│ [ Ask anything about your environment… ]            [ Send ]  │
└───────────────────────────────────────────────────────────────┘
```

Confirmed live:
- Header `h1` = `🤖 AI Assistant`.
- `.content-meta` = `Project-aware · Free tier · No data sent to third parties`.
- Input: `data-testid="ai-input"`, placeholder
  `Ask anything about your environment... (try: optimize memory, deploy to hetzner, enable redis persistence)`.
- Send: `data-testid="ai-send"` present.

---

## 3. Acceptance-criteria results

### AC1 — Chat input field: type, send, verify display

- **Empty/whitespace guard** ✅ live. `sendAIMessage('')` and
  `sendAIMessage('   ')` both no-op (`if (!input.trim()) return;`). History length
  unchanged. Good.
- **Send wiring** ✅ live (source). Two entry points, identical behavior:
  - `Enter` key: `onkeydown … if(event.key==='Enter'){sendAIMessage(this.value);this.value=''}`.
  - `Send` button: reads `#gui-ai-input`, calls `sendAIMessage`, clears the field.
- **Optimistic echo** ✅ live. On send, the user message is pushed to
  `_aiHistory` and `render()` is called **synchronously before** the network
  await — the user bubble (`.ai-bubble.user`) appears immediately, then the
  assistant reply is appended when the promise resolves. Verified:
  `userPushedImmediately=true`, `userBubbleRendered=true`.
- **Auto-scroll** 📄 source. After send and after reply, a `setTimeout` sets
  `.ai-chat-area`/`.tui-ai-scroll` `scrollTop = scrollHeight` (50ms / 100ms).
- **Input not disabled while awaiting** (gotcha): nothing disables the input or
  shows a "thinking…" indicator during the await. A user can fire multiple
  concurrent `sendAIMessage` calls; replies append in resolution order.

### AC2 — Response display: formatting, code blocks, markdown

`aiChatHTML()` does a minimal regex "markdown-ish" pass. Verified live against a
crafted message containing bold, inline code, a fenced block, and a pipe table:

| Markdown | Supported? | Rendered as | Verified |
|----------|-----------|-------------|----------|
| ` ```lang\n…``` ` fenced block | ✅ | styled monospace `<div>` (JetBrains Mono, `--bg-tertiary`) | ✅ live |
| `` `inline` `` | ✅ | `<code>` chip | ✅ live |
| `**bold**` | ✅ | `<strong>` | ✅ live |
| `\n` newlines | ✅ | `<br>` | ✅ live |
| `| tables |` | ❌ | **raw pipe text** (not parsed) | ✅ live |
| headings `#`, lists `-`, links | ❌ | raw text | 📄 source |

- Assistant bubbles get the `⚡` avatar; user bubbles are right-aligned with the
  `user` modifier. Font sizes differ GUI (13px) vs TUI (11px).

> **🐞 Bug F-AI-01 (Major) — tables in canned replies render as raw pipes.**
> The mock reply for *"optimize memory"* (see AC below) deliberately returns a
> markdown **table** (`| Service | Memory | Optimized? |`), but `aiChatHTML()`
> only handles fenced/inline code, bold, and `\n`. The table is shown as raw
> `|`-delimited lines — the single ugliest output in the whole assistant.
> **HOW IT SHOULD BE:** render GFM tables (and at least headings + lists), or
> stop emitting tables in canned replies. Real LLM responses routinely use
> tables/lists/headings, so a richer renderer is required regardless.

### AC3 — Provider picker: switch between providers, observe behavior

Options confirmed live (GUI `<select>`, default selected index 0):
`Groq (Llama 3.3 70B)`, `Cerebras (Qwen3 235B)`, `Cloudflare Workers AI`,
`Ollama (local)`. TUI exposes the same four as clickable chips
(`TUI_AI_PROVIDERS`).

> **🐞 Bug F-AI-02 (Major) — provider picker is purely cosmetic.**
> - GUI: the `<select>` has **no `onchange` handler** (verified live:
>   `selectHasOnchange=false`). Selecting "Ollama (local)" changes nothing.
> - `sendAIMessage()` **ignores the selected provider entirely** (verified live:
>   the function body references no provider/selectedIndex variable). It is
>   hardcoded to try **Groq first, then fall back to Cerebras**, regardless of
>   the picker.
> - TUI: clicking a provider chip updates `window._tuiAIProvider`, but that
>   variable is **never read** by `sendAIMessage` either — also cosmetic.
> **HOW IT SHOULD BE:** the picker must select the active provider; the selected
> value should drive the request (endpoint + key + model), and the cascade order
> should start from the chosen provider. Persist the choice across renders
> (currently lost on re-render, like all prototype state).

### AC4 — Context: verify project context is shown / loaded

- **Proactive seed message** ✅ live. On first load `_aiHistory` contains exactly
  **1** assistant message (a 👋 greeting + a `💡 Proactive` suggestion):
  "I can see your **utilio** project is running 4/5 services using 462MB total …
  PostgreSQL already optimized … Redis has no persistence — want me to enable
  AOF?" This is the *context-awareness* demo and it renders before any user input.
- **System prompt (context injection)** 📄 source. `AI_SYSTEM_PROMPT` hardcodes
  the utilio project context: path `~/Projects/GOTAS/utilio`, stack (Node 22.15
  Qwik, PHP 8.4, PostgreSQL 18.2 :5432, Redis 7.4 :6379, Meilisearch 1.14 :7700,
  SQL Server 2025 stopped), 462MB footprint, macOS/Seatbelt, DNS
  `utilio.test → 127.0.0.1`. It is prepended as the `system` message on every
  request.
- **Native context builder** 📄 source (`src/ai/context.zig`): `buildContext()`
  assembles the same shape dynamically from a `ProjectContext` (name/path/stack/
  services/os/isolation/env) and **masks secrets** (`isSecret()` redacts keys
  matching PASSWORD/SECRET/TOKEN/API_KEY/PRIVATE_KEY → `****`), with a ~4 chars/
  token budget truncation. Good hygiene — but it is the native path, not what the
  prototype demonstrates.

> **🔐 F-AI-03 (Major) — "No data sent to third parties" is contradicted by the
> code.** The header literally says *"No data sent to third parties"*, yet
> `sendAIMessage()` POSTs the full system prompt (project path, stack, ports,
> footprint) **and** the conversation to `api.groq.com` and `api.cerebras.ai` —
> third-party endpoints. The claim is only true for the `Ollama (local)` option,
> which the picker can't actually select (see F-AI-02). **HOW IT SHOULD BE:** the
> label must reflect the active provider (e.g. "sent to Groq" vs "local only"),
> and project paths/env should be redacted before leaving the machine (the
> native `context.zig` already masks env secrets — extend that to the prototype
> and to paths).

### AC5 — Error states: no API key, network failure, invalid provider

`sendAIMessage()` wraps the whole request in `try/catch`; **every** failure mode
funnels into a deterministic **mock fallback**:

- **No / invalid API key** 📄 source. The keys are placeholders committed in
  source: `GROQ_KEY = 'GROQ_API_KEY_HERE'` and a literal
  `'Bearer CEREBRAS_API_KEY_HERE'`. Both requests return non-200 → `!resp.ok` →
  Cerebras fallback also non-200 → `throw` → **mock**. So out of the box the
  prototype *always* answers from canned text. ✅ live corollary: the proactive
  seed + all replies observed are local; no spinner, no error toast.
- **Network failure** ✅ live (simulated by stubbing `window.fetch` to reject) /
  📄 source. Rejection is caught → **mock**. No user-visible error; the assistant
  just answers from canned text as if nothing happened.
- **Invalid provider** — **not reachable** by the user. There is no free-text
  provider, no API-key input field, and the picker is inert (F-AI-02). The only
  failure surface is the silent mock fallback.

**Canned (mock) replies** — keyed on case-insensitive substrings of the user
message (📄 source; redis branch ✅ live-confirmed text `appendonly yes`):

| Trigger substring(s) | Canned reply summary |
|----------------------|----------------------|
| `redis` + `persist` | enables AOF (`appendonly yes` / `appendfsync everysec`) |
| `memory` \| `optimize` | per-service memory **table** (triggers F-AI-01) |
| `deploy` \| `hetzner` | Hetzner CX22 deploy steps + `rawenv deploy …` |
| `tunnel` \| `public` | `rawenv tunnel 3000` → bore URL |
| `slow` \| `performance` | PostgreSQL `log_min_duration_statement` advice |
| `backup` | backup status + `rawenv backup create --all` |
| *(anything else)* | generic "Could you be more specific…" |

> **🐞 F-AI-04 (Minor) — no error/loading affordance.** Because all errors are
> swallowed into the mock, the user can never tell whether they got a real LLM
> answer or a canned one, nor that a key/network is missing. **HOW IT SHOULD BE:**
> distinguish "thinking…", "fell back to offline answers (no API key)", and hard
> errors; surface them in the UI.

### AC6 — Clear / reset

✅ live (source). Both the GUI `Clear` button and the TUI `^L:clear` chip set
`window._aiHistory=[{role:'assistant',content:'Chat cleared. How can I help?'}]`
and `render()`. The proactive seed is **not** restored — after clearing you get
a plain "Chat cleared" greeting, losing the context demo. (Borderline: arguably
should re-seed the proactive suggestion.)

### Empty state & long conversations

- **Empty state:** there is no truly empty state in the prototype — the screen
  always starts with the 1 proactive assistant message. Clearing yields the
  minimal "Chat cleared" greeting (the closest thing to empty).
- **Long conversations:** ✅ structurally — `.ai-chat-area` is
  `overflow-y:auto` and auto-scrolls to bottom; TUI scroll is capped
  `max-height:250px`. The prototype keeps **unbounded** history (no truncation).
  The native `ChatSession` (📄 `src/ai/chat.zig`) *does* truncate: it evicts the
  oldest non-system messages once an estimated token count (chars/4) exceeds
  `token_limit` (default 4096). That budgeting is **not** present in the
  prototype JS.

---

## 4. Native (Zig) reality check — scope note

The prototype is the design spec; the shipped binary's AI path is only partly
wired:

- `src/ai/provider.zig`: `sendMessage()` is a **stub** — it returns
  `error.ConnectionRefused` with a TODO: *"std.http.Client requires Io in Zig
  0.16.0."* So the native `rawenv ai "…"` command cannot actually reach any
  provider yet; only request-building, JSON escaping, and response parsing
  (`parseResponseContent`) exist and are unit-tested.
- `src/ai/cascade.zig` + `chat.zig`: provider cascade and a token-truncating
  `ChatSession` exist (history mgmt, system-prompt prepend, owned-string
  cleanup).
- `src/ai/context.zig`: dynamic context builder **with env-secret masking**.
- `src/ai/provider.zig` also defines real defaults per provider (groq/cerebras/
  cloudflare/ollama/custom) and env-key names (`GROQ_API_KEY`, `CEREBRAS_API_KEY`,
  `CLOUDFLARE_API_KEY`; ollama/custom have none) — i.e. the native design *does*
  read keys from env, unlike the prototype's hardcoded placeholders.

So the prototype over-promises (real Groq/Cerebras calls) while the native binary
under-delivers (HTTP not implemented). Both fall back to "no real call."

---

## 5. Summary of findings

| ID | Sev | Finding |
|----|-----|---------|
| F-AI-01 | Major | Canned "optimize memory" reply uses a markdown table, but the renderer doesn't parse tables → raw pipes shown. Renderer also lacks headings/lists/links. |
| F-AI-02 | Major | Provider picker is cosmetic: GUI `<select>` has no `onchange`; `sendAIMessage` ignores selection and is hardcoded Groq→Cerebras; TUI `_tuiAIProvider` is never read. |
| F-AI-03 | Major | "No data sent to third parties" is false for the default path — full project context + chat are POSTed to api.groq.com / api.cerebras.ai. Label should be provider-aware; paths should be redacted. |
| F-AI-04 | Minor | All errors (no key, 401, network failure) are silently swallowed into the mock fallback; no loading/error/offline indicator. API keys are committed as placeholders. |
| F-AI-05 | Minor | `Clear` does not restore the proactive context seed; long-conversation history is unbounded in the prototype (native `ChatSession` truncates by token budget, prototype does not). |
| (scope) | Info | Native `src/ai/provider.zig:sendMessage` is a TODO stub returning `ConnectionRefused`; native AI calls are not functional in Zig 0.16 yet. |

**What works well:** optimistic user-bubble echo, the proactive context-seed
message (good first impression of "project-aware"), code-block + inline-code +
bold rendering, the empty-input guard, shared history across GUI/TUI, and (in the
native layer) env-secret masking + token-budget truncation.
