pub const app = @import("app.zig");
pub const theme = @import("theme.zig");
pub const widgets = @import("widgets.zig");
pub const data_loader = @import("data_loader.zig");

pub fn run() !void {
    try app.run();
}

test {
    _ = app;
    _ = theme;
    _ = widgets;
    _ = data_loader;
}
