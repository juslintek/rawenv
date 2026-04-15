//! rawenv ImGui/zgui theme — maps directly to design tokens
//! Apply with: rawenv_theme.apply(zgui.getStyle());

const zgui = @import("zgui");

pub const colors = struct {
    // Backgrounds
    pub const bg_primary: [4]f32 = hexToRgba(0x0f0f14ff);
    pub const bg_secondary: [4]f32 = hexToRgba(0x16161eff);
    pub const bg_tertiary: [4]f32 = hexToRgba(0x1e1e2aff);
    pub const bg_hover: [4]f32 = hexToRgba(0x252535ff);
    pub const bg_active: [4]f32 = hexToRgba(0x2d2d40ff);

    // Accent
    pub const accent: [4]f32 = hexToRgba(0x6366f1ff);
    pub const accent_hover: [4]f32 = hexToRgba(0x818cf8ff);
    pub const success: [4]f32 = hexToRgba(0x34d399ff);
    pub const warning: [4]f32 = hexToRgba(0xfbbf24ff);
    pub const err: [4]f32 = hexToRgba(0xf87171ff);
    pub const info: [4]f32 = hexToRgba(0x60a5faff);

    // Text
    pub const text: [4]f32 = hexToRgba(0xe2e4f0ff);
    pub const text_muted: [4]f32 = hexToRgba(0x8b8da6ff);
    pub const text_disabled: [4]f32 = hexToRgba(0x4a4b5eff);

    // Border
    pub const border: [4]f32 = hexToRgba(0x2a2a3aff);
    pub const border_focus: [4]f32 = hexToRgba(0x6366f1ff);
};

pub fn apply(style: *zgui.Style) void {
    const c = colors;
    const s = style;

    // Rounding
    s.window_rounding = 8.0;
    s.frame_rounding = 6.0;
    s.tab_rounding = 6.0;
    s.scrollbar_rounding = 4.0;
    s.grab_rounding = 4.0;
    s.popup_rounding = 8.0;
    s.child_rounding = 8.0;

    // Spacing
    s.window_padding = .{ 16.0, 16.0 };
    s.frame_padding = .{ 12.0, 8.0 };
    s.item_spacing = .{ 8.0, 8.0 };
    s.item_inner_spacing = .{ 8.0, 4.0 };
    s.indent_spacing = 16.0;
    s.scrollbar_size = 10.0;

    // Borders
    s.window_border_size = 1.0;
    s.frame_border_size = 0.0;
    s.tab_border_size = 0.0;

    // Colors
    const col = &s.colors;
    col[@intFromEnum(zgui.StyleCol.text)] = c.text;
    col[@intFromEnum(zgui.StyleCol.text_disabled)] = c.text_disabled;
    col[@intFromEnum(zgui.StyleCol.window_bg)] = c.bg_primary;
    col[@intFromEnum(zgui.StyleCol.child_bg)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.popup_bg)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.border)] = c.border;
    col[@intFromEnum(zgui.StyleCol.frame_bg)] = c.bg_tertiary;
    col[@intFromEnum(zgui.StyleCol.frame_bg_hovered)] = c.bg_hover;
    col[@intFromEnum(zgui.StyleCol.frame_bg_active)] = c.bg_active;
    col[@intFromEnum(zgui.StyleCol.title_bg)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.title_bg_active)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.title_bg_collapsed)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.menu_bar_bg)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.scrollbar_bg)] = c.bg_primary;
    col[@intFromEnum(zgui.StyleCol.scrollbar_grab)] = c.bg_hover;
    col[@intFromEnum(zgui.StyleCol.scrollbar_grab_hovered)] = c.bg_active;
    col[@intFromEnum(zgui.StyleCol.scrollbar_grab_active)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.check_mark)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.slider_grab)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.slider_grab_active)] = c.accent_hover;
    col[@intFromEnum(zgui.StyleCol.button)] = c.bg_tertiary;
    col[@intFromEnum(zgui.StyleCol.button_hovered)] = c.bg_hover;
    col[@intFromEnum(zgui.StyleCol.button_active)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.header)] = c.bg_tertiary;
    col[@intFromEnum(zgui.StyleCol.header_hovered)] = c.bg_hover;
    col[@intFromEnum(zgui.StyleCol.header_active)] = c.accent;
    col[@intFromEnum(zgui.StyleCol.separator)] = c.border;
    col[@intFromEnum(zgui.StyleCol.tab)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.tab_hovered)] = c.bg_hover;
    col[@intFromEnum(zgui.StyleCol.tab_selected)] = c.bg_tertiary;
    col[@intFromEnum(zgui.StyleCol.table_header_bg)] = c.bg_tertiary;
    col[@intFromEnum(zgui.StyleCol.table_border_strong)] = c.border;
    col[@intFromEnum(zgui.StyleCol.table_border_light)] = c.border;
    col[@intFromEnum(zgui.StyleCol.table_row_bg)] = c.bg_primary;
    col[@intFromEnum(zgui.StyleCol.table_row_bg_alt)] = c.bg_secondary;
    col[@intFromEnum(zgui.StyleCol.nav_highlight)] = c.accent;
}

fn hexToRgba(hex: u32) [4]f32 {
    return .{
        @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
    };
}
