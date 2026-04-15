# rawenv Component Specification

## Design Principles
- Dark-first, indigo accent (#6366f1)
- 8px grid system, all spacing multiples of 4
- Rounded corners (6-12px), no sharp edges
- Status communicated via color dots (green/red/amber)
- Monospace for data (ports, PIDs, versions), Inter for UI text

---

## Components

### StatusDot
- Size: 10x10px (r=5)
- Colors: running=#34d399, stopped=#f87171, warning=#fbbf24
- Used in: service list, sidebar, TUI table

### ServiceCard (sidebar item)
- Height: 44px, padding: 8px 12px
- Background: transparent (default), bg.tertiary (selected)
- Selected indicator: 3px left border, accent color
- Layout: [StatusDot 10x10] [12px gap] [Name + Port stack]
- Name: Inter 13px/500, text.primary
- Port: JetBrains Mono 11px/400, text.secondary
- Status label: Inter 10px, right-aligned, color matches StatusDot
- Hover: bg.hover

### StatsCard
- Size: 190x88px, padding: 16px
- Background: bg.secondary, radius: 10px, shadow.md
- Label: Inter 11px/500, text.secondary, top
- Value: Inter 28px/700, text.primary, middle
- Progress bar: full width, 6px height, radius.full
  - Track: bg.tertiary
  - Fill: success (CPU <50%), accent (MEM), info (disk)

### ServiceTable (TUI)
- Header: bg.tertiary, 24px height
- Header text: JetBrains Mono 10px, text.secondary, uppercase
- Row height: 32px, alternating bg.primary / bg.secondary
- Selected row: bg.tertiary + 3px left accent border
- Columns: STATUS(dot) | SERVICE | VERSION | PORT | PID | CPU | MEM | UPTIME
- Port color: info (#60a5fa)
- Stopped row: all text uses text.disabled

### LogViewer
- Background: bg.primary
- Font: JetBrains Mono 12px/20px
- Timestamp: text.disabled
- Normal log: text.secondary
- Active log: text.primary
- Warning: warning (#fbbf24)
- Error: error (#f87171)
- Cursor: 8x16px rect, accent color, 80% opacity

### TabBar
- Height: 36px, background: bg.secondary, radius.md
- Active tab: bg.tertiary, 4px bottom border accent
- Active text: Inter 12px/600, text.primary
- Inactive text: Inter 12px/400, text.secondary
- Hover: bg.hover

### ActionButton
- Primary: bg=accent, text=white, radius=6px, padding=12x8
- Secondary: bg=bg.tertiary, text=text.secondary, radius=6px
- Danger: text=error on secondary bg
- Height: 32px (compact), 36px (default)
- Hover: accent.secondary (primary), bg.hover (secondary)

### Toggle (menu bar popover)
- Size: 36x20px, radius.full
- On: bg=success, knob=white, knob at right
- Off: bg=border, knob=text.disabled, knob at left
- Knob: 16x16px circle

### ConnectionString bar
- Height: 32px, bg=bg.tertiary, radius=6px
- Font: JetBrains Mono 11px, text.secondary
- Copy button: 60x24px, bg=accent, text=white, radius=4px, right-aligned

### HeaderBar (TUI)
- Height: 32px, bg=accent
- Logo: "⚡ rawenv" white bold 13px
- Project name: accent.secondary 11px
- Stats: accent.secondary 11px, right side
- Keybind hint: accent.secondary 11px, far right

### StatusBar (TUI)
- Height: 26px, bg=bg.secondary
- Version: accent color, bold 11px
- Keybinds: text.secondary 10px
- Connection indicator: "● connected" success color, right

---

## Layout Specs

### GUI Main Window: 1100x720 min
- Sidebar: 240px fixed width, bg.secondary
- Content: flex, bg.primary
- Title bar: 44px (native on macOS, custom on Linux/Windows)

### Menu Bar Popover: 320x440
- Padding: 12px
- Service item height: 48px
- Corner radius: 12px
- Shadow: shadow.lg
- Arrow notch: 10px equilateral triangle, centered

### TUI Dashboard: full terminal width
- Header: 1 line, accent bg
- Tab bar: 1 line
- Table: flexible rows
- Log viewer: ~40% of remaining height
- Resource bars: 3 lines
- Status bar: 1 line
