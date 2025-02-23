const std = @import("std");

pub const TextStyle = struct {
    font_family: []const u8,
    font_size: f64,
    line_height: f64,
    is_bold: bool,
    is_italic: bool,
    color: Color,
    margin_bottom: f64 = 0.0,
};

pub const Color = struct {
    r: f64,
    g: f64,
    b: f64,
    a: f64 = 1.0,

    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const white = Color{ .r = 1, .g = 1, .b = 1 };
    pub const gray = Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
};

pub const SPACING = struct {
    pub const BASE: f64 = 16.0;
    pub const PARAGRAPH: f64 = BASE * 1.2;
    pub const LIST_ITEM: f64 = BASE * 0.8;
    pub const HEADING1: f64 = BASE * 2.0;
    pub const HEADING2: f64 = BASE * 1.5;
    pub const HEADING3: f64 = BASE * 1.2;
    pub const INDENT: f64 = BASE * 1.5;
};

pub const DocumentStyle = struct {
    page_width: f64 = 595.0, // A4 width in points
    page_height: f64 = 842.0, // A4 height in points
    margin_top: f64 = 60.0, // ~0.83 inch
    margin_bottom: f64 = 60.0, // ~0.83 inch
    margin_left: f64 = 72.0, // 1 inch
    margin_right: f64 = 72.0, // 1 inch
    background_color: Color = Color.white,
    default_text: TextStyle,
    heading1: TextStyle,
    heading2: TextStyle,
    heading3: TextStyle,
    code: TextStyle,
    link: TextStyle,

    pub fn default() DocumentStyle {
        return DocumentStyle{
            .page_width = 595.0,
            .page_height = 842.0,
            .margin_top = 60.0,
            .margin_bottom = 60.0,
            .margin_left = 72.0,
            .margin_right = 72.0,
            .background_color = Color.white,
            .default_text = TextStyle{
                .font_family = "Arial",
                .font_size = 11,
                .line_height = 1.4,
                .is_bold = false,
                .is_italic = false,
                .color = Color.black,
                .margin_bottom = SPACING.PARAGRAPH,
            },
            .heading1 = TextStyle{
                .font_family = "Arial",
                .font_size = 24,
                .line_height = 1.2,
                .is_bold = true,
                .is_italic = false,
                .color = Color.black,
                .margin_bottom = SPACING.HEADING1,
            },
            .heading2 = TextStyle{
                .font_family = "Arial",
                .font_size = 18,
                .line_height = 1.2,
                .is_bold = true,
                .is_italic = false,
                .color = Color.black,
                .margin_bottom = SPACING.HEADING2,
            },
            .heading3 = TextStyle{
                .font_family = "Arial",
                .font_size = 14,
                .line_height = 1.2,
                .is_bold = true,
                .is_italic = false,
                .color = Color.black,
                .margin_bottom = SPACING.HEADING3,
            },
            .code = TextStyle{
                .font_family = "Courier",
                .font_size = 12,
                .line_height = 1.4,
                .is_bold = false,
                .is_italic = false,
                .color = Color{ .r = 0.2, .g = 0.2, .b = 0.2 },
                .margin_bottom = SPACING.PARAGRAPH,
            },
            .link = TextStyle{
                .font_family = "Arial",
                .font_size = 12,
                .line_height = 1.6,
                .is_bold = false,
                .is_italic = true,
                .color = Color{ .r = 0, .g = 0, .b = 1 },
                .margin_bottom = SPACING.BASE,
            },
        };
    }

    pub fn fromJson(json_str: []const u8, allocator: std.mem.Allocator) !DocumentStyle {
        _ = allocator;
        _ = json_str;
        // TODO: Implement JSON parsing for style configuration
        return DocumentStyle.default();
    }
};
