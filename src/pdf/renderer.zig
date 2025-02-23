const std = @import("std");
const c = @cImport({
    @cInclude("cairo.h");
    @cInclude("cairo-pdf.h");
    @cInclude("fontconfig/fontconfig.h");
});
const style = @import("../config/style.zig");

pub const PdfRenderer = struct {
    surface: ?*c.cairo_surface_t,
    cr: ?*c.cairo_t,
    width: f64,
    height: f64,
    current_page: u32,
    fc_config: ?*c.FcConfig,

    pub fn init(output_path: []const u8, width: f64, height: f64) !PdfRenderer {
        // Initialiser FontConfig
        if (c.FcInit() == 0) {
            return error.FontConfigInitFailed;
        }
        const fc_config = c.FcInitLoadConfigAndFonts();
        if (fc_config == null) {
            return error.FontConfigLoadFailed;
        }

        const surface = c.cairo_pdf_surface_create(output_path.ptr, width, height) orelse return error.SurfaceCreationFailed;
        errdefer c.cairo_surface_destroy(surface);

        const cr = c.cairo_create(surface) orelse return error.ContextCreationFailed;
        errdefer c.cairo_destroy(cr);

        // Initialiser avec un fond blanc
        c.cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
        c.cairo_rectangle(cr, 0, 0, width, height);
        c.cairo_fill(cr);

        // Vérifier qu'il n'y a pas d'erreur
        if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) {
            std.debug.print("Cairo error: {s}\n", .{c.cairo_status_to_string(c.cairo_status(cr))});
            return error.CairoError;
        }

        return PdfRenderer{
            .surface = surface,
            .cr = cr,
            .width = width,
            .height = height,
            .current_page = 1,
            .fc_config = fc_config,
        };
    }

    pub fn deinit(self: *PdfRenderer) void {
        if (self.cr) |cr| {
            c.cairo_destroy(cr);
            self.cr = null;
        }
        if (self.surface) |surface| {
            c.cairo_surface_destroy(surface);
            self.surface = null;
        }
        if (self.fc_config != null) {
            c.FcConfigDestroy(self.fc_config);
            c.FcFini();
        }
    }

    pub fn drawPageNumber(self: *PdfRenderer) void {
        if (self.cr) |cr| {
            // Sauvegarder l'état actuel
            c.cairo_save(cr);

            // Configurer la police pour le numéro de page
            c.cairo_select_font_face(cr, "Helvetica", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_NORMAL);
            c.cairo_set_font_size(cr, 10);

            // Créer le texte du numéro de page
            var page_text: [16]u8 = undefined;
            const text = std.fmt.bufPrintZ(&page_text, "Page {d}", .{self.current_page}) catch return;

            // Mesurer le texte
            var extents: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, text.ptr, &extents);

            // Positionner et dessiner le numéro de page
            const x = (self.width - extents.width) / 2;
            const y = self.height - 36; // 36 points = 0.5 pouce du bas
            c.cairo_move_to(cr, x, y);
            c.cairo_show_text(cr, text.ptr);

            // Restaurer l'état
            c.cairo_restore(cr);
        }
    }

    pub fn newPage(self: *PdfRenderer) void {
        if (self.cr) |cr| {
            // Dessiner le numéro de page avant de passer à la page suivante
            self.drawPageNumber();
            c.cairo_show_page(cr);
            self.current_page += 1;
        }
    }

    pub fn setFont(self: *PdfRenderer, family: []const u8, size: f64, italic: bool, bold: bool) void {
        if (self.cr) |cr| {
            std.debug.print("\n=== setFont Debug ===\n", .{});
            std.debug.print("Family: {s}, Size: {d}, Italic: {}, Bold: {}\n", .{ family, size, italic, bold });

            const slant: c.cairo_font_slant_t = if (italic) c.CAIRO_FONT_SLANT_ITALIC else c.CAIRO_FONT_SLANT_NORMAL;
            const weight: c.cairo_font_weight_t = if (bold) c.CAIRO_FONT_WEIGHT_BOLD else c.CAIRO_FONT_WEIGHT_NORMAL;

            // Définir la couleur du texte en noir
            c.cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

            // Liste des polices de secours
            const fallback_fonts = [_][]const u8{
                family,
                "Helvetica",
                "Arial",
                "Liberation Sans",
                "Times New Roman",
            };

            var success = false;
            for (fallback_fonts) |font| {
                std.debug.print("Trying font: {s}\n", .{font});
                c.cairo_select_font_face(cr, font.ptr, slant, weight);
                if (c.cairo_status(cr) == c.CAIRO_STATUS_SUCCESS) {
                    success = true;
                    std.debug.print("Successfully set font to: {s}\n", .{font});
                    break;
                }
                std.debug.print("Failed to set font {s}: {s}\n", .{ font, c.cairo_status_to_string(c.cairo_status(cr)) });
            }

            if (!success) {
                std.debug.print("All fonts failed, using default font\n", .{});
            }

            c.cairo_set_font_size(cr, size);
            std.debug.print("=== End setFont Debug ===\n\n", .{});
        }
    }

    pub fn getTextWidth(self: *PdfRenderer, text: []const u8) f64 {
        if (text.len == 0) return 0;

        if (self.cr) |cr| {
            // Créer une copie null-terminated de la chaîne
            var buffer: [1024]u8 = undefined;
            if (text.len >= buffer.len) return 0;

            @memcpy(buffer[0..text.len], text);
            buffer[text.len] = 0;

            var extents: c.cairo_text_extents_t = undefined;
            c.cairo_text_extents(cr, &buffer, &extents);
            return extents.width;
        }
        return 0;
    }

    pub fn drawText(self: *PdfRenderer, text: []const u8, x: f64, y: f64, text_style: ?style.TextStyle) f64 {
        if (self.cr) |cr| {
            std.debug.print("\n=== drawText Debug ===\n", .{});
            std.debug.print("Text: '{s}', X: {d}, Y: {d}\n", .{ text, x, y });

            // Créer une copie null-terminated de la chaîne
            var buffer: [1024]u8 = undefined;
            if (text.len >= buffer.len) return 0;

            @memcpy(buffer[0..text.len], text);
            buffer[text.len] = 0;

            // Appliquer le style si fourni
            if (text_style) |ts| {
                std.debug.print("Applying style - Bold: {}, Italic: {}\n", .{ ts.is_bold, ts.is_italic });

                // Set font options for better rendering
                const font_options = c.cairo_font_options_create();
                defer c.cairo_font_options_destroy(font_options);

                c.cairo_font_options_set_antialias(font_options, c.CAIRO_ANTIALIAS_SUBPIXEL);
                c.cairo_font_options_set_hint_style(font_options, c.CAIRO_HINT_STYLE_FULL);
                c.cairo_font_options_set_hint_metrics(font_options, c.CAIRO_HINT_METRICS_ON);
                c.cairo_set_font_options(cr, font_options);

                // Appliquer les styles de manière explicite
                const slant: c.cairo_font_slant_t = if (ts.is_italic)
                    c.CAIRO_FONT_SLANT_ITALIC
                else
                    c.CAIRO_FONT_SLANT_NORMAL;

                const weight: c.cairo_font_weight_t = if (ts.is_bold)
                    c.CAIRO_FONT_WEIGHT_BOLD
                else
                    c.CAIRO_FONT_WEIGHT_NORMAL;

                // Essayer d'abord avec Arial
                c.cairo_select_font_face(cr, "Arial", slant, weight);
                if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) {
                    // Si Arial échoue, essayer avec Helvetica
                    c.cairo_select_font_face(cr, "Helvetica", slant, weight);
                }

                c.cairo_set_font_size(cr, ts.font_size);
                c.cairo_set_source_rgb(cr, ts.color.r, ts.color.g, ts.color.b);
            }

            // Mesurer le texte et la police
            var extents: c.cairo_text_extents_t = undefined;
            var font_extents: c.cairo_font_extents_t = undefined;
            c.cairo_text_extents(cr, &buffer, &extents);
            c.cairo_font_extents(cr, &font_extents);

            std.debug.print("Text metrics - Width: {d}, Height: {d}\n", .{ extents.width, extents.height });
            std.debug.print("Font metrics - Ascent: {d}, Descent: {d}, Height: {d}\n", .{ font_extents.ascent, font_extents.descent, font_extents.height });

            // Calculer la position Y en tenant compte de l'ascent
            const baseline_y = y - font_extents.descent;
            c.cairo_move_to(cr, x, baseline_y);
            c.cairo_show_text(cr, &buffer);

            // Retourner la hauteur totale de la ligne
            const line_height = if (text_style) |ts| ts.font_size * ts.line_height else font_extents.height;
            std.debug.print("Returning height: {d}\n", .{line_height});
            std.debug.print("=== End drawText Debug ===\n\n", .{});
            return line_height;
        }
        return 0;
    }

    pub fn drawImage(self: *PdfRenderer, image_path: []const u8, x: f64, y: f64, width: f64, height: f64) !void {
        if (self.cr) |cr| {
            const image_surface = c.cairo_image_surface_create_from_png(image_path.ptr);
            if (image_surface == null) {
                return error.ImageLoadFailed;
            }
            defer c.cairo_surface_destroy(image_surface);

            const status = c.cairo_surface_status(image_surface);
            if (status != c.CAIRO_STATUS_SUCCESS) {
                return error.ImageLoadFailed;
            }

            // Save current transformation matrix
            c.cairo_save(cr);

            // Move to the target position
            c.cairo_translate(cr, x, y);

            // Scale the image to the desired size
            const img_width = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(image_surface)));
            const img_height = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(image_surface)));
            const scale_x = width / img_width;
            const scale_y = height / img_height;
            c.cairo_scale(cr, scale_x, scale_y);

            // Draw the image
            c.cairo_set_source_surface(cr, image_surface, 0, 0);
            c.cairo_paint(cr);

            // Restore transformation matrix
            c.cairo_restore(cr);
        }
    }

    pub fn finish(self: *PdfRenderer) void {
        if (self.cr) |cr| {
            // Dessiner le numéro de page sur la dernière page
            self.drawPageNumber();

            // Forcer l'écriture de tout le contenu en attente
            c.cairo_stroke(cr);

            // Afficher la dernière page
            c.cairo_show_page(cr);

            // Vérifier qu'il n'y a pas d'erreur
            if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) {
                std.debug.print("Cairo error: {s}\n", .{c.cairo_status_to_string(c.cairo_status(cr))});
            }
        }
        if (self.surface) |surface| {
            // Finaliser la surface PDF
            c.cairo_surface_finish(surface);

            // Vérifier qu'il n'y a pas d'erreur
            if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
                std.debug.print("Cairo surface error: {s}\n", .{c.cairo_status_to_string(c.cairo_surface_status(surface))});
            }
        }
    }

    pub fn getFontExtents(self: *PdfRenderer, text_style: style.TextStyle) c.cairo_font_extents_t {
        var font_extents: c.cairo_font_extents_t = undefined;

        if (self.cr) |cr| {
            // Appliquer le style de police
            const slant: c.cairo_font_slant_t = if (text_style.is_italic)
                c.CAIRO_FONT_SLANT_ITALIC
            else
                c.CAIRO_FONT_SLANT_NORMAL;

            const weight: c.cairo_font_weight_t = if (text_style.is_bold)
                c.CAIRO_FONT_WEIGHT_BOLD
            else
                c.CAIRO_FONT_WEIGHT_NORMAL;

            c.cairo_select_font_face(cr, "Arial", slant, weight);
            if (c.cairo_status(cr) != c.CAIRO_STATUS_SUCCESS) {
                c.cairo_select_font_face(cr, "Helvetica", slant, weight);
            }

            c.cairo_set_font_size(cr, text_style.font_size);
            c.cairo_font_extents(cr, &font_extents);
        }

        return font_extents;
    }
};
