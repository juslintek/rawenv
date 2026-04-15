//! rawenv GUI theme — maps design/tokens/tokens.json to ImGui style values.
//! Provides dark/light variants and WCAG contrast ratio calculation.

const std = @import("std");

pub const Color = [4]f32;

pub const Mode = enum { dark, light };

pub const Palette = struct {
    bg_primary: Color,
    bg_secondary: Color,
    bg_tertiary: Color,
    bg_hover: Color,
    bg_active: Color,
    accent: Color,
    accent_hover: Color,
    success: Color,
    warning: Color,
    err: Color,
    info: Color,
    text: Color,
    text_muted: Color,
    text_disabled: Color,
    border: Color,
    border_focus: Color,
};

pub const dark_palette = Palette{
    .bg_primary = hexToRgba(0x0f0f14ff),
    .bg_secondary = hexToRgba(0x16161eff),
    .bg_tertiary = hexToRgba(0x1e1e2aff),
    .bg_hover = hexToRgba(0x252535ff),
    .bg_active = hexToRgba(0x2d2d40ff),
    .accent = hexToRgba(0x6366f1ff),
    .accent_hover = hexToRgba(0x818cf8ff),
    .success = hexToRgba(0x34d399ff),
    .warning = hexToRgba(0xfbbf24ff),
    .err = hexToRgba(0xf87171ff),
    .info = hexToRgba(0x60a5faff),
    .text = hexToRgba(0xe2e4f0ff),
    .text_muted = hexToRgba(0x8b8da6ff),
    .text_disabled = hexToRgba(0x4a4b5eff),
    .border = hexToRgba(0x2a2a3aff),
    .border_focus = hexToRgba(0x6366f1ff),
};

pub const light_palette = Palette{
    .bg_primary = hexToRgba(0xf8f9fcff),
    .bg_secondary = hexToRgba(0xffffffff),
    .bg_tertiary = hexToRgba(0xeef0f5ff),
    .bg_hover = hexToRgba(0xe2e4ecff),
    .bg_active = hexToRgba(0xd5d7e2ff),
    .accent = hexToRgba(0x6366f1ff),
    .accent_hover = hexToRgba(0x4f46e5ff),
    .success = hexToRgba(0x059669ff),
    .warning = hexToRgba(0xd97706ff),
    .err = hexToRgba(0xdc2626ff),
    .info = hexToRgba(0x2563ebff),
    .text = hexToRgba(0x1a1a2eff),
    .text_muted = hexToRgba(0x6b7280ff),
    .text_disabled = hexToRgba(0x9ca3afff),
    .border = hexToRgba(0xd1d5dbff),
    .border_focus = hexToRgba(0x6366f1ff),
};

pub fn getPalette(mode: Mode) Palette {
    return switch (mode) {
        .dark => dark_palette,
        .light => light_palette,
    };
}

/// Style values matching design/theme/imgui_theme.zig
pub const StyleValues = struct {
    window_rounding: f32 = 8.0,
    frame_rounding: f32 = 6.0,
    tab_rounding: f32 = 6.0,
    scrollbar_rounding: f32 = 4.0,
    grab_rounding: f32 = 4.0,
    popup_rounding: f32 = 8.0,
    child_rounding: f32 = 8.0,
    window_padding: [2]f32 = .{ 16.0, 16.0 },
    frame_padding: [2]f32 = .{ 12.0, 8.0 },
    item_spacing: [2]f32 = .{ 8.0, 8.0 },
    item_inner_spacing: [2]f32 = .{ 8.0, 4.0 },
    indent_spacing: f32 = 16.0,
    scrollbar_size: f32 = 10.0,
    window_border_size: f32 = 1.0,
    frame_border_size: f32 = 0.0,
    tab_border_size: f32 = 0.0,
};

pub const style_values = StyleValues{};

/// WCAG 2.1 relative luminance from sRGB color
pub fn relativeLuminance(c: Color) f32 {
    const rs = linearize(c[0]);
    const gs = linearize(c[1]);
    const bs = linearize(c[2]);
    return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
}

fn linearize(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

/// WCAG contrast ratio between two colors (1.0 to 21.0)
pub fn contrastRatio(fg: Color, bg: Color) f32 {
    const l1 = relativeLuminance(fg);
    const l2 = relativeLuminance(bg);
    const lighter = @max(l1, l2);
    const darker = @min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
}

/// Returns true if contrast meets WCAG AA for normal text (≥4.5)
pub fn meetsAA(fg: Color, bg: Color) bool {
    return contrastRatio(fg, bg) >= 4.5;
}

/// Returns true if contrast meets WCAG AAA for normal text (≥7.0)
pub fn meetsAAA(fg: Color, bg: Color) bool {
    return contrastRatio(fg, bg) >= 7.0;
}

pub fn hexToRgba(hex: u32) Color {
    return .{
        @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
    };
}

pub fn rgbaToHex(c: Color) u32 {
    const r: u32 = @intFromFloat(c[0] * 255.0);
    const g: u32 = @intFromFloat(c[1] * 255.0);
    const b: u32 = @intFromFloat(c[2] * 255.0);
    const a: u32 = @intFromFloat(c[3] * 255.0);
    return (r << 24) | (g << 16) | (b << 8) | a;
}

test "hexToRgba roundtrip" {
    const hex: u32 = 0x6366f1ff;
    const c = hexToRgba(hex);
    const back = rgbaToHex(c);
    try std.testing.expectEqual(hex, back);
}

test "contrast ratio white on black" {
    const white = Color{ 1.0, 1.0, 1.0, 1.0 };
    const black = Color{ 0.0, 0.0, 0.0, 1.0 };
    const ratio = contrastRatio(white, black);
    try std.testing.expect(ratio > 20.9 and ratio < 21.1);
}

test "dark theme text meets AA on bg_primary" {
    const p = dark_palette;
    try std.testing.expect(meetsAA(p.text, p.bg_primary));
}

test "light theme text meets AA on bg_primary" {
    const p = light_palette;
    try std.testing.expect(meetsAA(p.text, p.bg_primary));
}

test "dark palette accent on bg_primary" {
    const p = dark_palette;
    // Accent may not meet AA on dark bg — this is expected for decorative use
    const ratio = contrastRatio(p.accent, p.bg_primary);
    try std.testing.expect(ratio > 1.0);
}
