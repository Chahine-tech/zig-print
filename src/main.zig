const std = @import("std");
const MarkdownParser = @import("markdown/parser.zig").MarkdownParser;
const PdfRenderer = @import("pdf/renderer.zig").PdfRenderer;
const style = @import("config/style.zig");

pub const SPACING = struct {
    pub const BASE: f64 = 16.0;
    pub const PARAGRAPH: f64 = BASE * 1.2; // Reduced for better text flow
    pub const LIST_ITEM: f64 = BASE * 0.8; // Smaller spacing between list items
    pub const HEADING1: f64 = BASE * 2.0;
    pub const HEADING2: f64 = BASE * 1.5;
    pub const HEADING3: f64 = BASE * 1.2;
    pub const INDENT: f64 = BASE * 1.2; // Smaller indent for better text alignment
};

pub const RenderContext = struct {
    allocator: std.mem.Allocator,
    renderer: *PdfRenderer,
    style: style.DocumentStyle,
    current_y: f64,
    current_x: f64,
    list_level: u32 = 0,
    in_list_item: bool = false,
    list_counters: std.ArrayList(u32),
    is_ordered_list: bool = false,

    pub fn init(allocator: std.mem.Allocator, renderer: *PdfRenderer) !RenderContext {
        return RenderContext{
            .allocator = allocator,
            .renderer = renderer,
            .style = style.DocumentStyle.default(),
            .current_y = 0,
            .current_x = 0,
            .in_list_item = false,
            .list_counters = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *RenderContext) void {
        self.list_counters.deinit();
    }

    fn getEffectiveWidth(self: *RenderContext) f64 {
        return self.style.page_width - self.style.margin_left - self.style.margin_right;
    }

    fn shouldWrapText(self: *RenderContext, text: []const u8, _: style.TextStyle) bool {
        const current_width = self.renderer.getTextWidth(text);
        const available_width = self.getEffectiveWidth() - (self.current_x - self.style.margin_left);
        return current_width > available_width;
    }

    fn wrapText(self: *RenderContext, text: []const u8, text_style: style.TextStyle) !void {
        var words = std.mem.split(u8, text, " ");
        var current_line = std.ArrayList(u8).init(self.allocator);
        defer current_line.deinit();

        var first_word = true;
        var line_start_x = self.current_x;
        const font_extents = self.renderer.getFontExtents(text_style);
        const line_height = text_style.font_size * text_style.line_height;

        while (words.next()) |word| {
            if (!first_word) {
                try current_line.append(' ');
            }
            first_word = false;

            try current_line.appendSlice(word);

            const line_width = self.renderer.getTextWidth(current_line.items);
            const available_width = self.getEffectiveWidth() - (line_start_x - self.style.margin_left);

            if (line_width > available_width) {
                if (current_line.items.len > 0) {
                    // Retirer le dernier espace si présent
                    if (current_line.items[current_line.items.len - 1] == ' ') {
                        _ = current_line.pop();
                    }

                    const baseline_y = self.current_y + font_extents.ascent;
                    _ = self.renderer.drawText(current_line.items, line_start_x, baseline_y, text_style);

                    self.current_y += line_height;
                    self.checkPageBreak();

                    line_start_x = self.getListIndentation();
                    current_line.clearRetainingCapacity();
                    try current_line.appendSlice(word);
                }
            }
        }

        if (current_line.items.len > 0) {
            const baseline_y = self.current_y + font_extents.ascent;
            _ = self.renderer.drawText(current_line.items, line_start_x, baseline_y, text_style);
            self.current_x = line_start_x + self.renderer.getTextWidth(current_line.items);
        }
    }

    fn checkPageBreak(self: *RenderContext) void {
        const margin_bottom = self.style.margin_bottom;
        const page_height = self.style.page_height;

        // Vérifier si nous avons dépassé la marge inférieure
        if (self.current_y >= page_height - margin_bottom) {
            self.renderer.newPage();
            self.current_y = self.style.margin_top;
            // Conserver l'indentation actuelle pour la continuité du texte
            if (self.current_x > 0) {
                self.current_x = if (self.list_level == 0)
                    self.style.margin_left
                else
                    self.getListIndentation();
            }
        }
    }

    fn getListIndentation(self: *RenderContext) f64 {
        if (self.list_level == 0) {
            return self.style.margin_left;
        }
        // Simpler indentation calculation
        return self.style.margin_left + SPACING.INDENT;
    }

    pub fn onText(self: *RenderContext, text: []const u8, bold: bool, italic: bool) !void {
        self.checkPageBreak();

        var text_style = self.style.default_text;
        text_style.is_bold = bold;
        text_style.is_italic = italic;

        // Obtenir les métriques de la police pour l'alignement
        const font_extents = self.renderer.getFontExtents(text_style);
        const line_height = text_style.font_size * text_style.line_height;
        const baseline_y = self.current_y + font_extents.ascent;

        // Si nous sommes au début d'une ligne, utiliser l'indentation de liste
        if (self.current_x == 0) {
            self.current_x = if (self.list_level == 0)
                self.style.margin_left
            else
                self.getListIndentation();
        }

        // Traiter le texte
        const trimmed_text = std.mem.trim(u8, text, " \n\t\r");
        const needs_space_before = text.len > 0 and text[0] == ' ' and !self.in_list_item;
        const needs_space_after = text.len > 0 and text[text.len - 1] == ' ';

        // Use a small fixed space width (about 1/4 of the font size)
        const space_width = text_style.font_size * 0.15;

        // Ajouter un espace avant si nécessaire
        if (needs_space_before and self.current_x > self.style.margin_left) {
            self.current_x += space_width;
        }

        // Dessiner le texte principal
        if (trimmed_text.len > 0) {
            const text_width = self.renderer.getTextWidth(trimmed_text);
            const available_width = self.getEffectiveWidth() - (self.current_x - self.style.margin_left);

            if (text_width > available_width) {
                try self.wrapText(trimmed_text, text_style);
            } else {
                _ = self.renderer.drawText(trimmed_text, self.current_x, baseline_y, text_style);
                self.current_x += text_width;
            }

            // Always add a small space after any text segment (for styled text)
            if (bold or italic) {
                self.current_x += space_width;
            }
        }

        // Ajouter un espace après si nécessaire
        if (needs_space_after) {
            self.current_x += space_width;
        }

        // Gérer le retour à la ligne explicite
        if (text.len > 0 and text[text.len - 1] == '\n') {
            self.current_x = 0;
            self.current_y += line_height;
        }

        self.in_list_item = false;
    }

    pub fn onParagraph(self: *RenderContext, text: []const u8) !void {
        // Add spacing before paragraphs
        if (self.current_y > self.style.margin_top) {
            self.current_y += SPACING.PARAGRAPH;
        }

        // Always start from the left margin for regular paragraphs
        self.current_x = self.style.margin_left;
        try self.onText(text, false, false);

        // Add a small space after the paragraph
        self.current_y += SPACING.BASE * 0.5;
    }

    pub fn onHeading(self: *RenderContext, level: c_int, text: []const u8) !void {
        // Ajouter un espacement avant le titre seulement si ce n'est pas le premier élément
        if (self.current_y > self.style.margin_top) {
            const spacing = switch (level) {
                1 => SPACING.HEADING1,
                2 => SPACING.HEADING2,
                else => SPACING.HEADING3,
            };
            self.current_y += spacing * 0.5;
        }

        const heading_style = switch (level) {
            1 => self.style.heading1,
            2 => self.style.heading2,
            else => self.style.heading3,
        };

        // Obtenir les métriques de la police pour l'alignement
        const font_extents = self.renderer.getFontExtents(heading_style);
        const baseline_y = self.current_y + font_extents.ascent;

        const x = self.style.margin_left;
        _ = self.renderer.drawText(text, x, baseline_y, heading_style);

        // Ajuster l'espacement après le titre
        self.current_y += heading_style.font_size * heading_style.line_height;
        if (level == 1) {
            self.current_y += SPACING.HEADING1 * 0.3;
        } else if (level == 2) {
            self.current_y += SPACING.HEADING2 * 0.3;
        } else {
            self.current_y += SPACING.HEADING3 * 0.3;
        }
    }

    pub fn onList(self: *RenderContext, is_ordered: bool) !void {
        // Add spacing before lists
        if (self.list_level == 0) {
            self.current_y += SPACING.PARAGRAPH * 0.8;
        }
        self.list_level += 1;
        self.is_ordered_list = is_ordered;
        try self.list_counters.append(1);
    }

    pub fn onListEnd(self: *RenderContext) !void {
        if (self.list_level > 0) {
            self.list_level -= 1;
            if (self.list_level == 0) {
                // Add spacing after lists
                self.current_y += SPACING.PARAGRAPH * 0.8;
            }
            _ = self.list_counters.pop();
        }
    }

    pub fn onListItem(self: *RenderContext) !void {
        const text_style = self.style.default_text;
        const total_indent = self.getListIndentation();

        // Add consistent spacing between list items
        if (self.current_y > self.style.margin_top) {
            self.current_y += SPACING.LIST_ITEM;
        }

        const font_extents = self.renderer.getFontExtents(text_style);
        const baseline_y = self.current_y + font_extents.ascent;

        if (self.is_ordered_list) {
            const current_number = self.list_counters.items[self.list_level - 1];
            self.list_counters.items[self.list_level - 1] += 1;

            var number_text: [16]u8 = undefined;
            const text = std.fmt.bufPrintZ(&number_text, "{d}.", .{current_number}) catch return;

            _ = self.renderer.drawText(text, total_indent, baseline_y, text_style);
            // Consistent spacing after numbers
            self.current_x = total_indent + SPACING.BASE;
        } else {
            _ = self.renderer.drawText("•", total_indent, baseline_y, text_style);
            // Consistent spacing after bullets
            self.current_x = total_indent + SPACING.BASE;
        }

        self.in_list_item = true;
    }

    pub fn onCodeBlock(self: *RenderContext, code: []const u8, lang: ?[]const u8) !void {
        _ = lang; // TODO: Implement syntax highlighting

        var lines = std.mem.split(u8, code, "\n");
        while (lines.next()) |line| {
            const x = self.style.margin_left + 20;
            const height = self.renderer.drawText(line, x, self.current_y, self.style.code);
            self.current_y += height;
        }
        self.current_y += self.style.code.margin_bottom;
    }

    pub fn onLink(self: *RenderContext, text: []const u8, url: []const u8) !void {
        _ = url; // TODO: Implement clickable links

        const x = self.style.margin_left;
        const height = self.renderer.drawText(text, x, self.current_y, self.style.link);
        self.current_y += height + self.style.link.margin_bottom;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <input_file> <output_file> [style_file]\n", .{args[0]});
        return error.InvalidArguments;
    }

    const input_path = args[1];
    const output_path = args[2];

    // Initialize document style
    var document_style = style.DocumentStyle.default();
    if (args.len > 3) {
        const style_path = args[3];
        const style_content = try std.fs.cwd().readFileAlloc(allocator, style_path, 1024 * 1024);
        defer allocator.free(style_content);
        document_style = try style.DocumentStyle.fromJson(style_content, allocator);
    }

    // Parse markdown
    var parser = try MarkdownParser.init(allocator);
    defer parser.deinit();
    try parser.parseFile(input_path);

    // Initialize PDF renderer
    var renderer = try PdfRenderer.init(
        output_path,
        document_style.page_width,
        document_style.page_height,
    );
    defer renderer.deinit();

    // Create render context
    var context = try RenderContext.init(allocator, &renderer);
    defer context.deinit();
    context.current_y = document_style.margin_top;
    context.style = document_style;

    // Process markdown and render PDF
    const Visitor = MarkdownParser.NodeVisitor(*RenderContext);
    try parser.visit(&context, Visitor{
        .onText = RenderContext.onText,
        .onHeading = RenderContext.onHeading,
        .onList = RenderContext.onList,
        .onListEnd = RenderContext.onListEnd,
        .onListItem = RenderContext.onListItem,
        .onCodeBlock = RenderContext.onCodeBlock,
        .onLink = RenderContext.onLink,
    });

    // S'assurer que tout est écrit dans le PDF
    renderer.finish();
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
