const std = @import("std");
const c = @cImport({
    @cInclude("cmark.h");
});
const style = @import("../config/style.zig");

pub const MarkdownParser = struct {
    parser: ?*c.cmark_parser,
    doc: ?*c.cmark_node,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !MarkdownParser {
        const parser = c.cmark_parser_new(c.CMARK_OPT_DEFAULT);
        if (parser == null) {
            return error.ParserCreationFailed;
        }

        return MarkdownParser{
            .parser = parser,
            .doc = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MarkdownParser) void {
        if (self.doc != null) {
            c.cmark_node_free(self.doc);
        }
        if (self.parser != null) {
            c.cmark_parser_free(self.parser);
        }
    }

    pub fn parseFile(self: *MarkdownParser, file_path: []const u8) !void {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024);
        defer self.allocator.free(content);

        if (self.parser) |parser| {
            c.cmark_parser_feed(parser, content.ptr, content.len);
            self.doc = c.cmark_parser_finish(parser);
            if (self.doc == null) {
                return error.MarkdownParsingFailed;
            }
        }
    }

    pub fn NodeVisitor(comptime Context: type) type {
        return struct {
            onText: ?fn (ctx: Context, text: []const u8, is_bold: bool, is_italic: bool) error{OutOfMemory}!void = null,
            onHeading: ?fn (ctx: Context, level: c_int, text: []const u8) error{OutOfMemory}!void = null,
            onList: ?fn (ctx: Context, is_ordered: bool) error{OutOfMemory}!void = null,
            onListEnd: ?fn (ctx: Context) error{OutOfMemory}!void = null,
            onListItem: ?fn (ctx: Context) error{OutOfMemory}!void = null,
            onCodeBlock: ?fn (ctx: Context, code: []const u8, lang: ?[]const u8) error{OutOfMemory}!void = null,
            onLink: ?fn (ctx: Context, text: []const u8, url: []const u8) error{OutOfMemory}!void = null,
        };
    }

    pub fn visit(self: *MarkdownParser, context: anytype, visitor: NodeVisitor(@TypeOf(context))) !void {
        if (self.doc) |doc| {
            try self.visitNode(doc, context, visitor, false, false);
        }
    }

    fn visitNode(self: *MarkdownParser, node: *c.cmark_node, context: anytype, visitor: NodeVisitor(@TypeOf(context)), is_bold: bool, is_italic: bool) !void {
        const node_type = c.cmark_node_get_type(node);
        const current_is_bold = is_bold or node_type == c.CMARK_NODE_STRONG;
        const current_is_italic = is_italic or node_type == c.CMARK_NODE_EMPH;

        switch (node_type) {
            c.CMARK_NODE_TEXT => {
                if (visitor.onText != null) {
                    if (c.cmark_node_get_literal(node)) |text| {
                        const text_span = std.mem.span(text);
                        if (text_span.len > 0) {
                            // Add space before if needed
                            const prev_node = c.cmark_node_previous(node);
                            if (prev_node != null and c.cmark_node_get_type(prev_node.?) != c.CMARK_NODE_SOFTBREAK) {
                                try visitor.onText.?(context, " ", false, false);
                            }

                            try visitor.onText.?(context, text_span, current_is_bold, current_is_italic);
                        }
                    }
                }
            },
            c.CMARK_NODE_STRONG, c.CMARK_NODE_EMPH => {
                // Process child nodes
                var child = c.cmark_node_first_child(node);
                while (child != null) : (child = c.cmark_node_next(child)) {
                    try self.visitNode(child.?, context, visitor, current_is_bold, current_is_italic);
                }
            },
            c.CMARK_NODE_SOFTBREAK => {
                if (visitor.onText != null) {
                    try visitor.onText.?(context, " ", false, false);
                }
            },
            c.CMARK_NODE_LINEBREAK => {
                if (visitor.onText != null) {
                    try visitor.onText.?(context, "\n", false, false);
                }
            },
            c.CMARK_NODE_PARAGRAPH => {
                std.debug.print("\n=== Paragraph Node Debug ===\n", .{});
                var child = c.cmark_node_first_child(node);
                var had_content = false;
                var is_first = true;
                while (child != null) : (child = c.cmark_node_next(child)) {
                    const child_type = c.cmark_node_get_type(child.?);
                    std.debug.print("Child node type: {d}\n", .{child_type});

                    if (!is_first and visitor.onText != null) {
                        try visitor.onText.?(context, " ", false, false);
                    }
                    try self.visitNode(child.?, context, visitor, current_is_bold, current_is_italic);
                    had_content = true;
                    is_first = false;
                }
                if (had_content and visitor.onText != null) {
                    try visitor.onText.?(context, "\n", false, false);
                }
            },
            c.CMARK_NODE_HEADING => {
                if (visitor.onHeading != null) {
                    const level = c.cmark_node_get_heading_level(node);
                    std.debug.print("Heading level {d}\n", .{level});

                    if (c.cmark_node_get_literal(node)) |text| {
                        const text_span = std.mem.span(text);
                        if (text_span.len > 0) {
                            try visitor.onHeading.?(context, level, text_span);
                        }
                    } else {
                        var text_buf = std.ArrayList(u8).init(self.allocator);
                        defer text_buf.deinit();

                        var child = c.cmark_node_first_child(node);
                        while (child != null) : (child = c.cmark_node_next(child)) {
                            if (c.cmark_node_get_literal(child.?)) |text| {
                                try text_buf.appendSlice(std.mem.span(text));
                            }
                        }

                        if (text_buf.items.len > 0) {
                            std.debug.print("Heading text: {s}\n", .{text_buf.items});
                            try visitor.onHeading.?(context, level, text_buf.items);
                        }
                    }
                }
            },
            c.CMARK_NODE_LIST => {
                if (visitor.onList != null) {
                    const list_type = c.cmark_node_get_list_type(node);
                    try visitor.onList.?(context, list_type == c.CMARK_ORDERED_LIST);
                }
                var child = c.cmark_node_first_child(node);
                while (child != null) : (child = c.cmark_node_next(child)) {
                    try self.visitNode(child.?, context, visitor, current_is_bold, current_is_italic);
                }
            },
            c.CMARK_NODE_ITEM => {
                if (visitor.onListItem != null) {
                    try visitor.onListItem.?(context);
                }
                var child = c.cmark_node_first_child(node);
                while (child != null) : (child = c.cmark_node_next(child)) {
                    try self.visitNode(child.?, context, visitor, current_is_bold, current_is_italic);
                }
            },
            c.CMARK_NODE_CODE_BLOCK => {
                if (visitor.onCodeBlock != null) {
                    if (c.cmark_node_get_literal(node)) |code| {
                        const lang = if (c.cmark_node_get_fence_info(node)) |l|
                            std.mem.span(l)
                        else
                            null;
                        try visitor.onCodeBlock.?(context, std.mem.span(code), lang);
                    }
                }
            },
            c.CMARK_NODE_LINK => {
                if (visitor.onLink != null) {
                    if (c.cmark_node_get_url(node)) |url| {
                        if (c.cmark_node_get_title(node)) |title| {
                            try visitor.onLink.?(context, std.mem.span(title), std.mem.span(url));
                        }
                    }
                }
            },
            else => {
                var child = c.cmark_node_first_child(node);
                while (child != null) : (child = c.cmark_node_next(child)) {
                    try self.visitNode(child.?, context, visitor, current_is_bold, current_is_italic);
                }
            },
        }
    }
};
