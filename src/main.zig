const std = @import("std");
const c = @cImport({
    @cInclude("cmark.h");
    @cInclude("cairo.h");
    @cInclude("cairo-pdf.h");
    @cInclude("fontconfig/fontconfig.h"); // Add fontconfig support
});

const TextStyle = struct {
    font_size: f64,
    vertical_spacing: f64,
    is_bold: bool,
    is_italic: bool,
};

fn initializeFontConfig() void {
    _ = c.FcInit();
    const config = c.FcConfigGetCurrent();
    _ = c.FcConfigAppFontAddDir(config, "/System/Library/Fonts"); // For macOS
    _ = c.FcConfigAppFontAddDir(config, "/usr/share/fonts"); // For Linux
}

fn renderText(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, style: TextStyle) f64 {
    // Use system font that definitely supports styles
    const font_family = "Arial"; // Standard macOS font

    const slant: c.cairo_font_slant_t = if (style.is_italic)
        c.CAIRO_FONT_SLANT_ITALIC
    else
        c.CAIRO_FONT_SLANT_NORMAL;

    const weight: c.cairo_font_weight_t = if (style.is_bold)
        c.CAIRO_FONT_WEIGHT_BOLD
    else
        c.CAIRO_FONT_WEIGHT_NORMAL;

    // Set font options for better rendering
    const font_options = c.cairo_font_options_create();
    defer c.cairo_font_options_destroy(font_options);

    c.cairo_font_options_set_antialias(font_options, c.CAIRO_ANTIALIAS_SUBPIXEL);
    c.cairo_font_options_set_hint_style(font_options, c.CAIRO_HINT_STYLE_FULL);
    c.cairo_font_options_set_hint_metrics(font_options, c.CAIRO_HINT_METRICS_ON);
    c.cairo_set_font_options(cr, font_options);

    // Select font face with proper style
    c.cairo_select_font_face(cr, font_family, slant, weight);
    c.cairo_set_font_size(cr, style.font_size);
    c.cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

    var extents: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &extents);
    c.cairo_move_to(cr, x, y);

    // Enable font options for better text rendering
    c.cairo_set_antialias(cr, c.CAIRO_ANTIALIAS_SUBPIXEL);
    c.cairo_set_line_width(cr, 1.0);

    c.cairo_show_text(cr, text.ptr);

    return extents.height + style.vertical_spacing;
}

fn processNode(
    cr: *c.cairo_t,
    node: *c.cmark_node,
    x: f64,
    y: *f64,
    allocator: std.mem.Allocator,
    list_depth: usize,
    parent_style: TextStyle,
) !void {
    const node_type = c.cmark_node_get_type(node);
    std.debug.print("Processing node type: {d}\n", .{node_type});

    // Create a new style that combines parent style with current node style
    var style = TextStyle{
        .font_size = parent_style.font_size,
        .vertical_spacing = parent_style.vertical_spacing,
        .is_bold = parent_style.is_bold,
        .is_italic = parent_style.is_italic,
    };

    // Get the parent node type
    const parent = c.cmark_node_parent(node);
    if (parent != null) {
        const parent_type = c.cmark_node_get_type(parent);
        // Inherit styles from parent node
        if (parent_type == c.CMARK_NODE_STRONG) {
            style.is_bold = true;
        }
        if (parent_type == c.CMARK_NODE_EMPH) {
            style.is_italic = true;
        }
    }

    // Apply additional styling based on node type
    switch (node_type) {
        c.CMARK_NODE_STRONG => {
            style.is_bold = true;
        },
        c.CMARK_NODE_EMPH => {
            style.is_italic = true;
        },
        c.CMARK_NODE_HEADING => {
            const level = c.cmark_node_get_heading_level(node);
            style = switch (level) {
                1 => .{ .font_size = 24, .vertical_spacing = 30, .is_bold = true, .is_italic = false },
                2 => .{ .font_size = 20, .vertical_spacing = 25, .is_bold = true, .is_italic = false },
                3 => .{ .font_size = 16, .vertical_spacing = 20, .is_bold = true, .is_italic = false },
                else => style,
            };
        },
        else => {},
    }

    const indent = x + @as(f64, @floatFromInt(list_depth)) * 20.0;

    // Handle node content
    switch (node_type) {
        c.CMARK_NODE_TEXT => {
            if (c.cmark_node_get_literal(node)) |text_ptr| {
                const text = std.mem.span(text_ptr);
                if (text.len > 0) {
                    y.* += renderText(cr, text, indent, y.*, style);
                }
            }
        },
        c.CMARK_NODE_LIST => {
            const list_type = c.cmark_node_get_list_type(node);
            if (list_type == c.CMARK_BULLET_LIST) {
                var child = c.cmark_node_first_child(node);
                while (child != null) : (child = c.cmark_node_next(child)) {
                    try processNode(cr, child.?, indent, y, allocator, list_depth + 1, style);
                }
                return;
            }
        },
        c.CMARK_NODE_ITEM => {
            const bullet = "• ";
            y.* += renderText(cr, bullet, indent - 15.0, y.*, style);
        },
        else => {},
    }

    // Process children with current style
    var child = c.cmark_node_first_child(node);
    while (child != null) : (child = c.cmark_node_next(child)) {
        try processNode(cr, child.?, indent, y, allocator, list_depth, style);
    }
}

pub fn main() !void {

    // Initialize FontConfig at the start
    initializeFontConfig();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        return;
    }

    const input_path = args[1];
    const output_path = args[2];

    const markdown_content = try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024);
    defer allocator.free(markdown_content);

    const parser = c.cmark_parser_new(c.CMARK_OPT_DEFAULT);
    if (parser == null) {
        std.debug.print("Failed to create markdown parser\n", .{});
        return error.ParserCreationFailed;
    }
    defer c.cmark_parser_free(parser);

    c.cmark_parser_feed(parser, markdown_content.ptr, markdown_content.len);
    const doc = c.cmark_parser_finish(parser);
    if (doc == null) {
        std.debug.print("Failed to parse markdown document\n", .{});
        return error.MarkdownParsingFailed;
    }
    defer c.cmark_node_free(doc);

    const surface = c.cairo_pdf_surface_create(output_path.ptr, 595.0, 842.0);
    if (surface == null) {
        std.debug.print("Failed to create PDF surface\n", .{});
        return error.SurfaceCreationFailed;
    }
    defer c.cairo_surface_destroy(surface);

    const cr = c.cairo_create(surface);
    if (cr == null) {
        std.debug.print("Failed to create Cairo context\n", .{});
        return error.ContextCreationFailed;
    }
    defer c.cairo_destroy(cr);

    c.cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
    c.cairo_paint(cr);

    var current_y: f64 = 50.0;
    const margin_x: f64 = 50.0;

    const initial_style = TextStyle{
        .font_size = 12,
        .vertical_spacing = 10,
        .is_bold = false,
        .is_italic = false,
    };

    if (cr) |context| {
        if (doc) |document| {
            try processNode(context, document, margin_x, &current_y, allocator, 0, initial_style);
        }
    }

    c.cairo_surface_finish(surface);
    std.debug.print("PDF generated successfully!\n", .{});
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "md2pdf",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkSystemLibrary("cmark");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("fontconfig"); // Add fontconfig linking
    exe.linkLibC();

    exe.addIncludePath("/opt/homebrew/include");
    exe.addLibraryPath("/opt/homebrew/lib");

    b.installArtifact(exe);
}
