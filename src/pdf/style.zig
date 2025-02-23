pub const Color = struct {
    r: f64,
    g: f64,
    b: f64,

    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const white = Color{ .r = 1, .g = 1, .b = 1 };
};

pub const TextStyle = struct {
    font_family: []const u8 = "Helvetica",
    font_size: f64 = 11,
    is_italic: bool = false,
    is_bold: bool = false,
    color: Color = Color.black,
};
