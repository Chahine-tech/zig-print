const std = @import("std");
const c = @cImport({
    @cInclude("cmark.h");
    @cInclude("cairo.h");
    @cInclude("cairo-pdf.h");
});

const TextStyle = struct {
    font_size: f64,
    vertical_spacing: f64,
    is_bold: bool,
    is_italic: bool,
};

fn renderText(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, style: TextStyle) f64 {
    const slant: c.cairo_font_slant_t = if (style.is_italic)
        c.CAIRO_FONT_SLANT_ITALIC
    else
        c.CAIRO_FONT_SLANT_NORMAL;

    const weight: c.cairo_font_weight_t = if (style.is_bold)
        c.CAIRO_FONT_WEIGHT_BOLD
    else
        c.CAIRO_FONT_WEIGHT_NORMAL;

    c.cairo_select_font_face(cr, "Sans", slant, weight);
    c.cairo_set_font_size(cr, style.font_size);
    c.cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

    var extents: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &extents);
    c.cairo_move_to(cr, x, y);
    c.cairo_show_text(cr, text.ptr);

    return extents.height + style.vertical_spacing;
}

fn getStyleForNodeType(node_type: c.cmark_node_type) TextStyle {
    return switch (node_type) {
        c.CMARK_NODE_HEADING => .{ .font_size = 24, .vertical_spacing = 30, .is_bold = true, .is_italic = false },
        c.CMARK_NODE_PARAGRAPH => .{ .font_size = 12, .vertical_spacing = 15, .is_bold = false, .is_italic = false },
        c.CMARK_NODE_LIST => .{ .font_size = 12, .vertical_spacing = 10, .is_bold = false, .is_italic = false },
        c.CMARK_NODE_ITEM => .{ .font_size = 12, .vertical_spacing = 10, .is_bold = false, .is_italic = false },
        else => .{ .font_size = 12, .vertical_spacing = 10, .is_bold = false, .is_italic = false },
    };
}

fn processNode(
    cr: *c.cairo_t,
    node: *c.cmark_node,
    x: f64,
    y: *f64,
    allocator: std.mem.Allocator,
    list_depth: usize,
    parent_style: ?TextStyle,
) !void {
    const node_type = c.cmark_node_get_type(node);
    var style = if (parent_style) |p_style|
        p_style
    else
        getStyleForNodeType(node_type);

    const indent = x + @as(f64, @floatFromInt(list_depth)) * 20.0;

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
            const bullet_style = style;
            y.* += renderText(cr, bullet, indent - 15.0, y.*, bullet_style);
        },
        c.CMARK_NODE_TEXT, c.CMARK_NODE_CODE => {
            if (c.cmark_node_get_literal(node)) |text_ptr| {
                const text = std.mem.span(text_ptr);
                if (text.len > 0) {
                    y.* += renderText(cr, text, indent, y.*, style);
                }
            }
        },
        else => {},
    }

    var child = c.cmark_node_first_child(node);
    while (child != null) : (child = c.cmark_node_next(child)) {
        try processNode(cr, child.?, indent, y, allocator, list_depth, style);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} input.md output.pdf\n", .{args[0]});
        return;
    }

    const input_path = args[1];
    const output_path = args[2];

    const markdown_content = try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024);
    defer allocator.free(markdown_content);

    const parser = c.cmark_parser_new(c.CMARK_OPT_DEFAULT);
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

    if (cr) |context| {
        if (doc) |document| {
            try processNode(context, document, margin_x, &current_y, allocator, 0, null);
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
    exe.linkLibC();

    exe.addIncludePath("/opt/homebrew/include");
    exe.addLibraryPath("/opt/homebrew/lib");

    b.installArtifact(exe);
}
