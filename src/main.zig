const std = @import("std");
const c = @cImport({
    @cInclude("cmark.h");
    @cInclude("cairo.h");
    @cInclude("cairo-pdf.h");
});

fn renderText(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, font_size: f64) f64 {
    c.cairo_set_font_size(cr, font_size);

    var text_extents: c.cairo_text_extents_t = undefined;
    c.cairo_text_extents(cr, text.ptr, &text_extents);

    c.cairo_move_to(cr, x, y);
    c.cairo_show_text(cr, text.ptr);

    return text_extents.height + font_size * 0.5; // Return height plus some padding
}

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read input file
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} input.md output.pdf\n", .{args[0]});
        return;
    }

    const input_path = args[1];
    const output_path = args[2];

    // Read markdown content
    const markdown_content = try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024);
    defer allocator.free(markdown_content);

    // Parse markdown to HTML using cmark
    const parser = c.cmark_parser_new(c.CMARK_OPT_DEFAULT);
    defer c.cmark_parser_free(parser);

    c.cmark_parser_feed(parser, markdown_content.ptr, markdown_content.len);
    const doc = c.cmark_parser_finish(parser);
    defer c.cmark_node_free(doc);

    const html = c.cmark_render_html(doc, c.CMARK_OPT_DEFAULT);
    defer std.c.free(html);

    // Create PDF surface
    const surface = c.cairo_pdf_surface_create(output_path.ptr, 595.0, 842.0); // A4 size in points
    const cr = c.cairo_create(surface);
    defer {
        c.cairo_destroy(cr);
        c.cairo_surface_destroy(surface);
    }

    // Set up basic styling
    c.cairo_select_font_face(cr, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);

    // Simple parsing and rendering of the HTML content
    var current_y: f64 = 50.0;
    const margin_x: f64 = 50.0;

    var it = std.mem.split(u8, std.mem.span(html), "<");
    while (it.next()) |part| {
        if (part.len == 0) continue;

        if (std.mem.startsWith(u8, part, "h1>")) {
            const text = part[3..];
            if (!std.mem.endsWith(u8, text, "</h1>")) continue;
            const clean_text = text[0 .. text.len - 5];
            current_y += renderText(cr, clean_text, margin_x, current_y + 30.0, 24.0);
        } else if (std.mem.startsWith(u8, part, "h2>")) {
            const text = part[3..];
            if (!std.mem.endsWith(u8, text, "</h2>")) continue;
            const clean_text = text[0 .. text.len - 5];
            current_y += renderText(cr, clean_text, margin_x, current_y + 20.0, 20.0);
        } else if (std.mem.startsWith(u8, part, "p>")) {
            const text = part[2..];
            if (!std.mem.endsWith(u8, text, "</p>")) continue;
            const clean_text = text[0 .. text.len - 4];
            current_y += renderText(cr, clean_text, margin_x, current_y + 15.0, 12.0);
        } else if (std.mem.startsWith(u8, part, "li>")) {
            const text = part[3..];
            if (!std.mem.endsWith(u8, text, "</li>")) continue;
            const clean_text = text[0 .. text.len - 5];
            // Add bullet point
            _ = renderText(cr, "• ", margin_x, current_y + 15.0, 12.0);
            current_y += renderText(cr, clean_text, margin_x + 20.0, current_y + 15.0, 12.0);
        }
    }

    // Finish PDF
    c.cairo_surface_finish(surface);
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

    // Link with required C libraries
    exe.linkSystemLibrary("cmark");
    exe.linkSystemLibrary("cairo");
    exe.linkLibC();

    // Add include paths for Homebrew installations
    exe.addIncludePath("/opt/homebrew/include");
    exe.addLibraryPath("/opt/homebrew/lib");

    b.installArtifact(exe);
}
