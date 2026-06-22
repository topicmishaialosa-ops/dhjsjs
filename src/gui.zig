const gfx = @import("render.zig");
pub const mouse = @import("mouse.zig");

pub const MAX_ID_STACK: usize = 64;
pub const MAX_LAYOUT_STACK: usize = 64;
pub const MAX_WINDOW_STACK: usize = 16;
pub const MAX_STATE_ITEMS: usize = 128;
pub const MAX_KEY: usize = 256;

pub const Style = struct {
    bg: u32,
    panel_bg: u32,
    button_bg: u32,
    button_hover: u32,
    button_active: u32,
    button_text: u32,
    text: u32,
    text_dim: u32,
    accent: u32,
    accent_hover: u32,
    input_bg: u32,
    input_border: u32,
    input_text: u32,
    border: u32,
    slider_track: u32,
    slider_thumb: u32,
    separator: u32,
    header_bg: u32,
    header_text: u32,
    title_bg: u32,
    title_text: u32,
    check_bg: u32,
    check_mark: u32,
    scrollbar_bg: u32,
    scrollbar_thumb: u32,
    rounding: u8,
    window_rounding: u8,
    shadow: u8,
    spacing: u8,
    padding: u8,

    pub fn fromBase(base: Style) Style {
        return base;
    }

    pub fn setBg(s: *Style, c: u32) void { s.bg = c; }
    pub fn setPanelBg(s: *Style, c: u32) void { s.panel_bg = c; }
    pub fn setButtonBg(s: *Style, c: u32) void { s.button_bg = c; }
    pub fn setButtonHover(s: *Style, c: u32) void { s.button_hover = c; }
    pub fn setButtonActive(s: *Style, c: u32) void { s.button_active = c; }
    pub fn setButtonText(s: *Style, c: u32) void { s.button_text = c; }
    pub fn setText(s: *Style, c: u32) void { s.text = c; }
    pub fn setAccent(s: *Style, c: u32) void { s.accent = c; }
    pub fn setBorder(s: *Style, c: u32) void { s.border = c; }
    pub fn setRounding(s: *Style, r: u8) void { s.rounding = r; }
    pub fn setWindowRounding(s: *Style, r: u8) void { s.window_rounding = r; }
    pub fn setShadow(s: *Style, v: u8) void { s.shadow = v; }
    pub fn setSpacing(s: *Style, v: u8) void { s.spacing = v; }
    pub fn setPadding(s: *Style, v: u8) void { s.padding = v; }
};

pub const style_dark = Style{
    .bg = 0xFF1E1E1E, .panel_bg = 0xFF252526,
    .button_bg = 0xFF3C3C3C, .button_hover = 0xFF505050, .button_active = 0xFF2D2D2D, .button_text = 0xFFCCCCCC,
    .text = 0xFFCCCCCC, .text_dim = 0xFF888888,
    .accent = 0xFF0E639C, .accent_hover = 0xFF1177BB,
    .input_bg = 0xFF1E1E1E, .input_border = 0xFF3C3C3C, .input_text = 0xFFCCCCCC,
    .border = 0xFF3C3C3C,
    .slider_track = 0xFF3C3C3C, .slider_thumb = 0xFF0E639C,
    .separator = 0xFF3C3C3C,
    .header_bg = 0xFF2D2D2D, .header_text = 0xFFCCCCCC,
    .title_bg = 0xFF2D2D2D, .title_text = 0xFFCCCCCC,
    .check_bg = 0xFF1E1E1E, .check_mark = 0xFFCCCCCC,
    .scrollbar_bg = 0xFF3C3C3C, .scrollbar_thumb = 0xFF0E639C, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_light = Style{
    .bg = 0xFFF0F0F0, .panel_bg = 0xFFFAFAFA,
    .button_bg = 0xFFE0E0E0, .button_hover = 0xFFD0D0D0, .button_active = 0xFFC0C0C0, .button_text = 0xFF222222,
    .text = 0xFF222222, .text_dim = 0xFF888888,
    .accent = 0xFF0078D4, .accent_hover = 0xFF106EBE,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFCCCCCC, .input_text = 0xFF222222,
    .border = 0xFFCCCCCC,
    .slider_track = 0xFFCCCCCC, .slider_thumb = 0xFF0078D4,
    .separator = 0xFFCCCCCC,
    .header_bg = 0xFFE8E8E8, .header_text = 0xFF222222,
    .title_bg = 0xFFE8E8E8, .title_text = 0xFF222222,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFF222222,
    .scrollbar_bg = 0xFFCCCCCC, .scrollbar_thumb = 0xFF0078D4, .rounding = 4, .window_rounding = 6, .shadow = 15, .spacing = 4, .padding = 4,
};

pub const style_dracula = Style{
    .bg = 0xFF282A36, .panel_bg = 0xFF2D2F3E,
    .button_bg = 0xFF44475A, .button_hover = 0xFF5A5D75, .button_active = 0xFF383A4E, .button_text = 0xFFF8F8F2,
    .text = 0xFFF8F8F2, .text_dim = 0xFF6272A4,
    .accent = 0xFFBD93F9, .accent_hover = 0xFFCCA9FF,
    .input_bg = 0xFF1E1F2E, .input_border = 0xFF44475A, .input_text = 0xFFF8F8F2,
    .border = 0xFF44475A,
    .slider_track = 0xFF44475A, .slider_thumb = 0xFFBD93F9,
    .separator = 0xFF44475A,
    .header_bg = 0xFF2D2F3E, .header_text = 0xFFF8F8F2,
    .title_bg = 0xFF2D2F3E, .title_text = 0xFFBD93F9,
    .check_bg = 0xFF1E1F2E, .check_mark = 0xFF50FA7B,
    .scrollbar_bg = 0xFF44475A, .scrollbar_thumb = 0xFFBD93F9, .rounding = 6, .window_rounding = 8, .shadow = 25, .spacing = 4, .padding = 4,
};

pub const style_nord = Style{
    .bg = 0xFF2E3440, .panel_bg = 0xFF3B4252,
    .button_bg = 0xFF434C5E, .button_hover = 0xFF4C566A, .button_active = 0xFF3B4252, .button_text = 0xFFECEFF4,
    .text = 0xFFECEFF4, .text_dim = 0xFF81A1C1,
    .accent = 0xFF88C0D0, .accent_hover = 0xFFA3D0D8,
    .input_bg = 0xFF2E3440, .input_border = 0xFF434C5E, .input_text = 0xFFECEFF4,
    .border = 0xFF434C5E,
    .slider_track = 0xFF434C5E, .slider_thumb = 0xFF88C0D0,
    .separator = 0xFF434C5E,
    .header_bg = 0xFF3B4252, .header_text = 0xFFECEFF4,
    .title_bg = 0xFF3B4252, .title_text = 0xFF88C0D0,
    .check_bg = 0xFF2E3440, .check_mark = 0xFFA3BE8C,
    .scrollbar_bg = 0xFF434C5E, .scrollbar_thumb = 0xFF88C0D0, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_solarized_dark = Style{
    .bg = 0xFF002B36, .panel_bg = 0xFF073642,
    .button_bg = 0xFF184C56, .button_hover = 0xFF246572, .button_active = 0xFF0E3842, .button_text = 0xFF93A1A1,
    .text = 0xFF93A1A1, .text_dim = 0xFF657B83,
    .accent = 0xFF268BD2, .accent_hover = 0xFF44A4E0,
    .input_bg = 0xFF002B36, .input_border = 0xFF184C56, .input_text = 0xFF93A1A1,
    .border = 0xFF184C56,
    .slider_track = 0xFF184C56, .slider_thumb = 0xFF268BD2,
    .separator = 0xFF184C56,
    .header_bg = 0xFF073642, .header_text = 0xFF93A1A1,
    .title_bg = 0xFF073642, .title_text = 0xFF268BD2,
    .check_bg = 0xFF002B36, .check_mark = 0xFF859900,

    .scrollbar_bg = 0xFF184C56, .scrollbar_thumb = 0xFF268BD2, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_solarized_light = Style{
    .bg = 0xFFFDF6E3, .panel_bg = 0xFFEEE8D5,
    .button_bg = 0xFFE4DDC9, .button_hover = 0xFFD5CEB8, .button_active = 0xFFDDD5C1, .button_text = 0xFF586E75,
    .text = 0xFF586E75, .text_dim = 0xFF93A1A1,
    .accent = 0xFF268BD2, .accent_hover = 0xFF1A7CC0,
    .input_bg = 0xFFFDF6E3, .input_border = 0xFFE4DDC9, .input_text = 0xFF586E75,
    .border = 0xFFE4DDC9,
    .slider_track = 0xFFE4DDC9, .slider_thumb = 0xFF268BD2,
    .separator = 0xFFE4DDC9,
    .header_bg = 0xFFEEE8D5, .header_text = 0xFF586E75,
    .title_bg = 0xFFEEE8D5, .title_text = 0xFF268BD2,
    .check_bg = 0xFFFDF6E3, .check_mark = 0xFF859900,

    .scrollbar_bg = 0xFFE4DDC9, .scrollbar_thumb = 0xFF268BD2, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_monokai = Style{
    .bg = 0xFF272822, .panel_bg = 0xFF2D2E27,
    .button_bg = 0xFF3E3D32, .button_hover = 0xFF4F4E42, .button_active = 0xFF35362E, .button_text = 0xFFF8F8F2,
    .text = 0xFFF8F8F2, .text_dim = 0xFF75715E,
    .accent = 0xFFA6E22E, .accent_hover = 0xFFBBF045,
    .input_bg = 0xFF1A1A16, .input_border = 0xFF3E3D32, .input_text = 0xFFF8F8F2,
    .border = 0xFF3E3D32,
    .slider_track = 0xFF3E3D32, .slider_thumb = 0xFFA6E22E,
    .separator = 0xFF3E3D32,
    .header_bg = 0xFF2D2E27, .header_text = 0xFFF8F8F2,
    .title_bg = 0xFF2D2E27, .title_text = 0xFFA6E22E,
    .check_bg = 0xFF1A1A16, .check_mark = 0xFFFD971F,

    .scrollbar_bg = 0xFF3E3D32, .scrollbar_thumb = 0xFFA6E22E, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_one_dark = Style{
    .bg = 0xFF282C34, .panel_bg = 0xFF313640,
    .button_bg = 0xFF3E4451, .button_hover = 0xFF4F5665, .button_active = 0xFF353B45, .button_text = 0xFFABB2BF,
    .text = 0xFFABB2BF, .text_dim = 0xFF5C6370,
    .accent = 0xFF61AFEF, .accent_hover = 0xFF7EC2F8,
    .input_bg = 0xFF21252B, .input_border = 0xFF3E4451, .input_text = 0xFFABB2BF,
    .border = 0xFF3E4451,
    .slider_track = 0xFF3E4451, .slider_thumb = 0xFF61AFEF,
    .separator = 0xFF3E4451,
    .header_bg = 0xFF313640, .header_text = 0xFFABB2BF,
    .title_bg = 0xFF313640, .title_text = 0xFF61AFEF,
    .check_bg = 0xFF21252B, .check_mark = 0xFF98C379,

    .scrollbar_bg = 0xFF3E4451, .scrollbar_thumb = 0xFF61AFEF, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_github_light = Style{
    .bg = 0xFFFFFFFF, .panel_bg = 0xFFF6F8FA,
    .button_bg = 0xFFF0F2F5, .button_hover = 0xFFE1E4E8, .button_active = 0xFFD1D5DA, .button_text = 0xFF24292E,
    .text = 0xFF24292E, .text_dim = 0xFF586069,
    .accent = 0xFF0366D6, .accent_hover = 0xFF0256B3,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFD1D5DA, .input_text = 0xFF24292E,
    .border = 0xFFD1D5DA,
    .slider_track = 0xFFE1E4E8, .slider_thumb = 0xFF0366D6,
    .separator = 0xFFE1E4E8,
    .header_bg = 0xFFF6F8FA, .header_text = 0xFF24292E,
    .title_bg = 0xFFF6F8FA, .title_text = 0xFF0366D6,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFF28A745,

    .scrollbar_bg = 0xFFD1D5DA, .scrollbar_thumb = 0xFF0366D6, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_gruvbox_dark = Style{
    .bg = 0xFF282828, .panel_bg = 0xFF32302F,
    .button_bg = 0xFF3C3836, .button_hover = 0xFF504945, .button_active = 0xFF32302F, .button_text = 0xFFEBDBB2,
    .text = 0xFFEBDBB2, .text_dim = 0xFF928374,
    .accent = 0xFFD79921, .accent_hover = 0xFFE5B92C,
    .input_bg = 0xFF1D2021, .input_border = 0xFF3C3836, .input_text = 0xFFEBDBB2,
    .border = 0xFF3C3836,
    .slider_track = 0xFF3C3836, .slider_thumb = 0xFFD79921,
    .separator = 0xFF3C3836,
    .header_bg = 0xFF32302F, .header_text = 0xFFEBDBB2,
    .title_bg = 0xFF32302F, .title_text = 0xFFD79921,
    .check_bg = 0xFF1D2021, .check_mark = 0xFF98971A,

    .scrollbar_bg = 0xFF3C3836, .scrollbar_thumb = 0xFFD79921, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_gruvbox_light = Style{
    .bg = 0xFFFBF1C7, .panel_bg = 0xFFF2E5BC,
    .button_bg = 0xFFE6D5AA, .button_hover = 0xFFD5C49A, .button_active = 0xFFDDCCA2, .button_text = 0xFF3C3836,
    .text = 0xFF3C3836, .text_dim = 0xFF928374,
    .accent = 0xFFB57614, .accent_hover = 0xFF9D6510,
    .input_bg = 0xFFFBF1C7, .input_border = 0xFFE6D5AA, .input_text = 0xFF3C3836,
    .border = 0xFFE6D5AA,
    .slider_track = 0xFFE6D5AA, .slider_thumb = 0xFFB57614,
    .separator = 0xFFE6D5AA,
    .header_bg = 0xFFF2E5BC, .header_text = 0xFF3C3836,
    .title_bg = 0xFFF2E5BC, .title_text = 0xFFB57614,
    .check_bg = 0xFFFBF1C7, .check_mark = 0xFF98971A,

    .scrollbar_bg = 0xFFE6D5AA, .scrollbar_thumb = 0xFFB57614, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_catppuccin = Style{
    .bg = 0xFF1E1E2E, .panel_bg = 0xFF252540,
    .button_bg = 0xFF363650, .button_hover = 0xFF48486A, .button_active = 0xFF2E2E48, .button_text = 0xFFCDD6F4,
    .text = 0xFFCDD6F4, .text_dim = 0xFF6C7086,
    .accent = 0xFFCBA6F7, .accent_hover = 0xFFD3BDF8,
    .input_bg = 0xFF181825, .input_border = 0xFF363650, .input_text = 0xFFCDD6F4,
    .border = 0xFF363650,
    .slider_track = 0xFF363650, .slider_thumb = 0xFFCBA6F7,
    .separator = 0xFF363650,
    .header_bg = 0xFF252540, .header_text = 0xFFCDD6F4,
    .title_bg = 0xFF252540, .title_text = 0xFFCBA6F7,
    .check_bg = 0xFF181825, .check_mark = 0xFFA6E3A1,

    .scrollbar_bg = 0xFF363650, .scrollbar_thumb = 0xFFCBA6F7, .rounding = 6, .window_rounding = 8, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_tokyo_night = Style{
    .bg = 0xFF1A1B26, .panel_bg = 0xFF222335,
    .button_bg = 0xFF2F3048, .button_hover = 0xFF3D3E5C, .button_active = 0xFF282940, .button_text = 0xFFA9B1D6,
    .text = 0xFFA9B1D6, .text_dim = 0xFF565F89,
    .accent = 0xFF7AA2F7, .accent_hover = 0xFF92B5F9,
    .input_bg = 0xFF13131D, .input_border = 0xFF2F3048, .input_text = 0xFFA9B1D6,
    .border = 0xFF2F3048,
    .slider_track = 0xFF2F3048, .slider_thumb = 0xFF7AA2F7,
    .separator = 0xFF2F3048,
    .header_bg = 0xFF222335, .header_text = 0xFFA9B1D6,
    .title_bg = 0xFF222335, .title_text = 0xFF7AA2F7,
    .check_bg = 0xFF13131D, .check_mark = 0xFF9ECE6A,

    .scrollbar_bg = 0xFF2F3048, .scrollbar_thumb = 0xFF7AA2F7, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_ayu_dark = Style{
    .bg = 0xFF0A0E14, .panel_bg = 0xFF141820,
    .button_bg = 0xFF1F2430, .button_hover = 0xFF2D3340, .button_active = 0xFF191E28, .button_text = 0xFFC7C7C7,
    .text = 0xFFC7C7C7, .text_dim = 0xFF6C7380,
    .accent = 0xFFF29668, .accent_hover = 0xFFF5AD82,
    .input_bg = 0xFF06090E, .input_border = 0xFF1F2430, .input_text = 0xFFC7C7C7,
    .border = 0xFF1F2430,
    .slider_track = 0xFF1F2430, .slider_thumb = 0xFFF29668,
    .separator = 0xFF1F2430,
    .header_bg = 0xFF141820, .header_text = 0xFFC7C7C7,
    .title_bg = 0xFF141820, .title_text = 0xFFF29668,
    .check_bg = 0xFF06090E, .check_mark = 0xFF87CEEB,

    .scrollbar_bg = 0xFF1F2430, .scrollbar_thumb = 0xFFF29668, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_ayu_light = Style{
    .bg = 0xFFFAFAFA, .panel_bg = 0xFFF5F5F5,
    .button_bg = 0xFFE8E8E8, .button_hover = 0xFFD6D6D6, .button_active = 0xFFDCDCDC, .button_text = 0xFF333333,
    .text = 0xFF333333, .text_dim = 0xFF8A8A8A,
    .accent = 0xFFF29668, .accent_hover = 0xFFE8865A,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFCCCCCC, .input_text = 0xFF333333,
    .border = 0xFFCCCCCC,
    .slider_track = 0xFFE0E0E0, .slider_thumb = 0xFFF29668,
    .separator = 0xFFE0E0E0,
    .header_bg = 0xFFF0F0F0, .header_text = 0xFF333333,
    .title_bg = 0xFFF0F0F0, .title_text = 0xFFF29668,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFF86B300,

    .scrollbar_bg = 0xFFCCCCCC, .scrollbar_thumb = 0xFFF29668, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_material_dark = Style{
    .bg = 0xFF212121, .panel_bg = 0xFF2C2C2C,
    .button_bg = 0xFF383838, .button_hover = 0xFF484848, .button_active = 0xFF303030, .button_text = 0xFFEEEEEE,
    .text = 0xFFEEEEEE, .text_dim = 0xFF888888,
    .accent = 0xFF4CAF50, .accent_hover = 0xFF66BB6A,
    .input_bg = 0xFF1A1A1A, .input_border = 0xFF383838, .input_text = 0xFFEEEEEE,
    .border = 0xFF383838,
    .slider_track = 0xFF383838, .slider_thumb = 0xFF4CAF50,
    .separator = 0xFF383838,
    .header_bg = 0xFF2C2C2C, .header_text = 0xFFEEEEEE,
    .title_bg = 0xFF2C2C2C, .title_text = 0xFF4CAF50,
    .check_bg = 0xFF1A1A1A, .check_mark = 0xFF4CAF50,

    .scrollbar_bg = 0xFF383838, .scrollbar_thumb = 0xFF4CAF50, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_material_light = Style{
    .bg = 0xFFFAFAFA, .panel_bg = 0xFFFFFFFF,
    .button_bg = 0xFFE0E0E0, .button_hover = 0xFFD0D0D0, .button_active = 0xFFC8C8C8, .button_text = 0xFF333333,
    .text = 0xFF333333, .text_dim = 0xFF888888,
    .accent = 0xFF1976D2, .accent_hover = 0xFF1565C0,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFBDBDBD, .input_text = 0xFF333333,
    .border = 0xFFBDBDBD,
    .slider_track = 0xFFE0E0E0, .slider_thumb = 0xFF1976D2,
    .separator = 0xFFE0E0E0,
    .header_bg = 0xFFF5F5F5, .header_text = 0xFF333333,
    .title_bg = 0xFFF5F5F5, .title_text = 0xFF1976D2,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFF1976D2,

    .scrollbar_bg = 0xFFBDBDBD, .scrollbar_thumb = 0xFF1976D2, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_high_contrast = Style{
    .bg = 0xFF000000, .panel_bg = 0xFF0D0D0D,
    .button_bg = 0xFF1A1A1A, .button_hover = 0xFF333333, .button_active = 0xFF0D0D0D, .button_text = 0xFFFFFFFF,
    .text = 0xFFFFFFFF, .text_dim = 0xFFAAAAAA,
    .accent = 0xFFFFFFFF, .accent_hover = 0xFFCCCCCC,
    .input_bg = 0xFF000000, .input_border = 0xFFFFFFFF, .input_text = 0xFFFFFFFF,
    .border = 0xFFFFFFFF,
    .slider_track = 0xFF333333, .slider_thumb = 0xFFFFFFFF,
    .separator = 0xFFFFFFFF,
    .header_bg = 0xFF0D0D0D, .header_text = 0xFFFFFFFF,
    .title_bg = 0xFF0D0D0D, .title_text = 0xFFFFFFFF,
    .check_bg = 0xFF000000, .check_mark = 0xFFFFFFFF,

    .scrollbar_bg = 0xFFFFFFFF, .scrollbar_thumb = 0xFFFFFFFF, .rounding = 0, .window_rounding = 0, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_retro_terminal = Style{
    .bg = 0xFF0D0D0D, .panel_bg = 0xFF111111,
    .button_bg = 0xFF1A1A1A, .button_hover = 0xFF222222, .button_active = 0xFF0F0F0F, .button_text = 0xFF33FF33,
    .text = 0xFF33FF33, .text_dim = 0xFF1A8C1A,
    .accent = 0xFF33FF33, .accent_hover = 0xFF66FF66,
    .input_bg = 0xFF050505, .input_border = 0xFF33FF33, .input_text = 0xFF33FF33,
    .border = 0xFF33FF33,
    .slider_track = 0xFF1A1A1A, .slider_thumb = 0xFF33FF33,
    .separator = 0xFF33FF33,
    .header_bg = 0xFF111111, .header_text = 0xFF33FF33,
    .title_bg = 0xFF111111, .title_text = 0xFF33FF33,
    .check_bg = 0xFF050505, .check_mark = 0xFF33FF33,

    .scrollbar_bg = 0xFF33FF33, .scrollbar_thumb = 0xFF33FF33, .rounding = 0, .window_rounding = 0, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_forest = Style{
    .bg = 0xFF1E2E1E, .panel_bg = 0xFF253725,
    .button_bg = 0xFF2F452F, .button_hover = 0xFF3D573D, .button_active = 0xFF283D28, .button_text = 0xFFD4E7D4,
    .text = 0xFFD4E7D4, .text_dim = 0xFF7AA87A,
    .accent = 0xFF6BBF6B, .accent_hover = 0xFF85CF85,
    .input_bg = 0xFF152215, .input_border = 0xFF2F452F, .input_text = 0xFFD4E7D4,
    .border = 0xFF2F452F,
    .slider_track = 0xFF2F452F, .slider_thumb = 0xFF6BBF6B,
    .separator = 0xFF2F452F,
    .header_bg = 0xFF253725, .header_text = 0xFFD4E7D4,
    .title_bg = 0xFF253725, .title_text = 0xFF6BBF6B,
    .check_bg = 0xFF152215, .check_mark = 0xFFA8D8A8,

    .scrollbar_bg = 0xFF2F452F, .scrollbar_thumb = 0xFF6BBF6B, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_ocean = Style{
    .bg = 0xFF0D1B2A, .panel_bg = 0xFF142538,
    .button_bg = 0xFF1B344E, .button_hover = 0xFF254664, .button_active = 0xFF162D44, .button_text = 0xFFD0E8F0,
    .text = 0xFFD0E8F0, .text_dim = 0xFF6090A0,
    .accent = 0xFF40B4D0, .accent_hover = 0xFF5CC9E4,
    .input_bg = 0xFF091420, .input_border = 0xFF1B344E, .input_text = 0xFFD0E8F0,
    .border = 0xFF1B344E,
    .slider_track = 0xFF1B344E, .slider_thumb = 0xFF40B4D0,
    .separator = 0xFF1B344E,
    .header_bg = 0xFF142538, .header_text = 0xFFD0E8F0,
    .title_bg = 0xFF142538, .title_text = 0xFF40B4D0,
    .check_bg = 0xFF091420, .check_mark = 0xFF60D0A0,

    .scrollbar_bg = 0xFF1B344E, .scrollbar_thumb = 0xFF40B4D0, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_sunset = Style{
    .bg = 0xFF1A1410, .panel_bg = 0xFF241C16,
    .button_bg = 0xFF33281E, .button_hover = 0xFF44362A, .button_active = 0xFF2C221A, .button_text = 0xFFE8D5C0,
    .text = 0xFFE8D5C0, .text_dim = 0xFFA08060,
    .accent = 0xFFE87540, .accent_hover = 0xFFF09060,
    .input_bg = 0xFF120E0A, .input_border = 0xFF33281E, .input_text = 0xFFE8D5C0,
    .border = 0xFF33281E,
    .slider_track = 0xFF33281E, .slider_thumb = 0xFFE87540,
    .separator = 0xFF33281E,
    .header_bg = 0xFF241C16, .header_text = 0xFFE8D5C0,
    .title_bg = 0xFF241C16, .title_text = 0xFFE87540,
    .check_bg = 0xFF120E0A, .check_mark = 0xFFF0C040,

    .scrollbar_bg = 0xFF33281E, .scrollbar_thumb = 0xFFE87540, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_candy = Style{
    .bg = 0xFF1E1020, .panel_bg = 0xFF281A2C,
    .button_bg = 0xFF3A2440, .button_hover = 0xFF4D3054, .button_active = 0xFF321E38, .button_text = 0xFFF0E0F0,
    .text = 0xFFF0E0F0, .text_dim = 0xFFA080B0,
    .accent = 0xFFE060B0, .accent_hover = 0xFFE880C0,
    .input_bg = 0xFF140A16, .input_border = 0xFF3A2440, .input_text = 0xFFF0E0F0,
    .border = 0xFF3A2440,
    .slider_track = 0xFF3A2440, .slider_thumb = 0xFFE060B0,
    .separator = 0xFF3A2440,
    .header_bg = 0xFF281A2C, .header_text = 0xFFF0E0F0,
    .title_bg = 0xFF281A2C, .title_text = 0xFFE060B0,
    .check_bg = 0xFF140A16, .check_mark = 0xFF80E0B0,

    .scrollbar_bg = 0xFF3A2440, .scrollbar_thumb = 0xFFE060B0, .rounding = 6, .window_rounding = 8, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_monochrome = Style{
    .bg = 0xFF1A1A1A, .panel_bg = 0xFF222222,
    .button_bg = 0xFF333333, .button_hover = 0xFF444444, .button_active = 0xFF2A2A2A, .button_text = 0xFFE0E0E0,
    .text = 0xFFE0E0E0, .text_dim = 0xFF808080,
    .accent = 0xFFB0B0B0, .accent_hover = 0xFFCCCCCC,
    .input_bg = 0xFF121212, .input_border = 0xFF333333, .input_text = 0xFFE0E0E0,
    .border = 0xFF333333,
    .slider_track = 0xFF333333, .slider_thumb = 0xFFB0B0B0,
    .separator = 0xFF333333,
    .header_bg = 0xFF222222, .header_text = 0xFFE0E0E0,
    .title_bg = 0xFF222222, .title_text = 0xFFCCCCCC,
    .check_bg = 0xFF121212, .check_mark = 0xFFE0E0E0,

    .scrollbar_bg = 0xFF333333, .scrollbar_thumb = 0xFFB0B0B0, .rounding = 0, .window_rounding = 0, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_rose_pine = Style{
    .bg = 0xFF191724, .panel_bg = 0xFF1F1D2E,
    .button_bg = 0xFF2A273F, .button_hover = 0xFF363253, .button_active = 0xFF242237, .button_text = 0xFFE0DEF4,
    .text = 0xFFE0DEF4, .text_dim = 0xFF6E6A86,
    .accent = 0xFFEBBCBA, .accent_hover = 0xFFF0D0CE,
    .input_bg = 0xFF13101D, .input_border = 0xFF2A273F, .input_text = 0xFFE0DEF4,
    .border = 0xFF2A273F,
    .slider_track = 0xFF2A273F, .slider_thumb = 0xFFEBBCBA,
    .separator = 0xFF2A273F,
    .header_bg = 0xFF1F1D2E, .header_text = 0xFFE0DEF4,
    .title_bg = 0xFF1F1D2E, .title_text = 0xFFEBBCBA,
    .check_bg = 0xFF13101D, .check_mark = 0xFF9CCFD8,

    .scrollbar_bg = 0xFF2A273F, .scrollbar_thumb = 0xFFEBBCBA, .rounding = 6, .window_rounding = 8, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_everforest = Style{
    .bg = 0xFF2D353B, .panel_bg = 0xFF343F44,
    .button_bg = 0xFF3D4A50, .button_hover = 0xFF4D5A60, .button_active = 0xFF364348, .button_text = 0xFFD3C6AA,
    .text = 0xFFD3C6AA, .text_dim = 0xFF859080,
    .accent = 0xFFA7C080, .accent_hover = 0xFFBAD99A,
    .input_bg = 0xFF232A2E, .input_border = 0xFF3D4A50, .input_text = 0xFFD3C6AA,
    .border = 0xFF3D4A50,
    .slider_track = 0xFF3D4A50, .slider_thumb = 0xFFA7C080,
    .separator = 0xFF3D4A50,
    .header_bg = 0xFF343F44, .header_text = 0xFFD3C6AA,
    .title_bg = 0xFF343F44, .title_text = 0xFFA7C080,
    .check_bg = 0xFF232A2E, .check_mark = 0xFFE69875,

    .scrollbar_bg = 0xFF3D4A50, .scrollbar_thumb = 0xFFA7C080, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_nord_light = Style{
    .bg = 0xFFEFF1F5, .panel_bg = 0xFFE6E8ED,
    .button_bg = 0xFFD8DCE5, .button_hover = 0xFFC9CDD7, .button_active = 0xFFCFD3DD, .button_text = 0xFF2E3440,
    .text = 0xFF2E3440, .text_dim = 0xFF7B88A1,
    .accent = 0xFF5E81AC, .accent_hover = 0xFF4F73A0,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFD8DCE5, .input_text = 0xFF2E3440,
    .border = 0xFFD8DCE5,
    .slider_track = 0xFFD8DCE5, .slider_thumb = 0xFF5E81AC,
    .separator = 0xFFD8DCE5,
    .header_bg = 0xFFE6E8ED, .header_text = 0xFF2E3440,
    .title_bg = 0xFFE6E8ED, .title_text = 0xFF5E81AC,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFFA3BE8C,

    .scrollbar_bg = 0xFFD8DCE5, .scrollbar_thumb = 0xFF5E81AC, .rounding = 4, .window_rounding = 6, .shadow = 20, .spacing = 4, .padding = 4,
};

pub const style_modern_dark = Style{
    .bg = 0xFF161820, .panel_bg = 0xFF222532,
    .button_bg = 0xFF3A3E52, .button_hover = 0xFF484C66, .button_active = 0xFF3A76D2, .button_text = 0xFFE8EBF8,
    .text = 0xFFE8EBF8, .text_dim = 0xFFAFB6D2,
    .accent = 0xFF6EA5FF, .accent_hover = 0xFF5690EE,
    .input_bg = 0xFF1C1E2A, .input_border = 0xFF3A3E52, .input_text = 0xFFE8EBF8,
    .border = 0xFF363A4A,
    .slider_track = 0xFF34384A, .slider_thumb = 0xFF468AF0,
    .separator = 0xFF323648,
    .header_bg = 0xFF243458, .header_text = 0xFFE8EBF8,
    .title_bg = 0xFF1E2030, .title_text = 0xFFE8EBF8,
    .check_bg = 0xFF2A2D3E, .check_mark = 0xFF50D282,
    .scrollbar_bg = 0xFF282B3C, .scrollbar_thumb = 0xFF468AF0, .rounding = 6, .window_rounding = 10, .shadow = 24, .spacing = 6, .padding = 6,
};

pub const style_modern_light = Style{
    .bg = 0xFFF2F4F9, .panel_bg = 0xFFFFFFFF,
    .button_bg = 0xFFDCE1EC, .button_hover = 0xFFC9D0DF, .button_active = 0xFF306CC3, .button_text = 0xFF1C2030,
    .text = 0xFF1C2030, .text_dim = 0xFF6A7490,
    .accent = 0xFF2A58A8, .accent_hover = 0xFF1E4A94,
    .input_bg = 0xFFFFFFFF, .input_border = 0xFFD2D8E4, .input_text = 0xFF1C2030,
    .border = 0xFFC8CEDC,
    .slider_track = 0xFFD6DBE6, .slider_thumb = 0xFF3268C0,
    .separator = 0xFFD6DBE6,
    .header_bg = 0xFF204480, .header_text = 0xFFFFFFFF,
    .title_bg = 0xFFE8EBF2, .title_text = 0xFF1C2030,
    .check_bg = 0xFFFFFFFF, .check_mark = 0xFF269658,
    .scrollbar_bg = 0xFFE4E7EF, .scrollbar_thumb = 0xFF3A78D0, .rounding = 6, .window_rounding = 10, .shadow = 24, .spacing = 6, .padding = 6,
};

pub const WidgetStateType = enum(u8) {
    none,
    text_input,
    slider_drag,
    collapsed,
};

pub const WidgetState = struct {
    id: u32,
    t: WidgetStateType,
    text_buf: [256]u8,
    text_len: usize,
    text_cursor: usize,
    float_val: f32,
    bool_val: bool,
    rect_x: i32,
    rect_y: i32,
    rect_w: u32,
    rect_h: u32,
    aux_x: i32,
    aux_y: i32,
};

pub const LayoutMode = enum(u8) {
    vertical,
    horizontal,
};

pub const LayoutFrame = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    cursor_x: i32,
    cursor_y: i32,
    max_x: i32,
    max_y: i32,
    mode: LayoutMode,
    spacing: i32,
    indent: i32,
};

pub const WindowState = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    title_h: i32,
    dragging: bool,
    drag_off_x: i32,
    drag_off_y: i32,
    id: u32,
};

pub const InputState = struct {
    mouse_x: i32,
    mouse_y: i32,
    mouse_down: bool,
    mouse_clicked: bool,
    mouse_released: bool,
    scroll: i32,
    keys: [MAX_KEY]bool,
    keys_pressed: [MAX_KEY]bool,
    text_input: [16]u8,
    text_len: usize,
    mouse_state: mouse.State,

    pub fn fromMouse(m: mouse.State, keys: [MAX_KEY]bool, keys_pressed: [MAX_KEY]bool, text_input: [16]u8, text_len: usize) InputState {
        return InputState{
            .mouse_x = m.x,
            .mouse_y = m.y,
            .mouse_down = m.primary_down,
            .mouse_clicked = m.primary_pressed,
            .mouse_released = m.primary_released,
            .scroll = m.wheel_y,
            .keys = keys,
            .keys_pressed = keys_pressed,
            .text_input = text_input,
            .text_len = text_len,
            .mouse_state = m,
        };
    }
};

pub const Gui = struct {
    style: Style,
    fb: *gfx.Framebuffer,
    input: InputState,

    id_stack: [MAX_ID_STACK]u32,
    id_depth: usize,

    layout_stack: [MAX_LAYOUT_STACK]LayoutFrame,
    layout_depth: usize,

    window_stack: [MAX_WINDOW_STACK]WindowState,
    window_depth: usize,

    state_items: [MAX_STATE_ITEMS]WidgetState,
    state_count: usize,

    hot_id: u32,
    active_id: u32,
    focus_id: u32,
    last_active_id: u32,
    mouse_capture_id: u32,
    next_id_counter: u32,
    frame_count: u64,
    clip_rect: gfx.Rect,

    pub fn init(fb: *gfx.Framebuffer) Gui {
        return Gui{
            .style = style_dark,
            .fb = fb,
            .input = InputState{
                .mouse_x = 0, .mouse_y = 0,
                .mouse_down = false, .mouse_clicked = false, .mouse_released = false,
                .scroll = 0,
                .keys = [_]bool{false} ** MAX_KEY,
                .keys_pressed = [_]bool{false} ** MAX_KEY,
                .text_input = [_]u8{0} ** 16,
                .text_len = 0,
                .mouse_state = mouse.State.init(),
            },
            .id_stack = [_]u32{0} ** MAX_ID_STACK,
            .id_depth = 0,
            .layout_stack = [_]LayoutFrame{LayoutFrame{
                .x = 0, .y = 0, .w = 0, .h = 0,
                .cursor_x = 0, .cursor_y = 0,
                .max_x = 0, .max_y = 0,
                .mode = .vertical, .spacing = 4, .indent = 0,
            }} ** MAX_LAYOUT_STACK,
            .layout_depth = 0,
            .window_stack = [_]WindowState{undefined} ** MAX_WINDOW_STACK,
            .window_depth = 0,
            .state_items = [_]WidgetState{WidgetState{
                .id = 0, .t = .none,
                .text_buf = [_]u8{0} ** 256,
                .text_len = 0, .text_cursor = 0,
                .float_val = 0, .bool_val = false,
                .rect_x = 0, .rect_y = 0, .rect_w = 0, .rect_h = 0,
                .aux_x = 0, .aux_y = 0,
            }} ** MAX_STATE_ITEMS,
            .state_count = 0,
            .hot_id = 0,
            .active_id = 0,
            .focus_id = 0,
            .last_active_id = 0,
            .mouse_capture_id = 0,
            .next_id_counter = 1,
            .frame_count = 0,
            .clip_rect = gfx.Rect{ .x = 0, .y = 0, .w = 0, .h = 0 },
        };
    }

    pub fn setStyle(self: *Gui, s: Style) void {
        self.style = s;
    }

    pub fn beginFrame(self: *Gui, fb: *gfx.Framebuffer, input: InputState) void {
        self.fb = fb;
        self.input = input;
        self.input.mouse_x = input.mouse_state.x;
        self.input.mouse_y = input.mouse_state.y;
        self.input.mouse_down = input.mouse_state.primary_down;
        self.input.mouse_clicked = input.mouse_state.primary_pressed;
        self.input.mouse_released = input.mouse_state.primary_released;
        self.input.scroll = input.mouse_state.wheel_y;
        self.input.mouse_state.capture_id = self.mouse_capture_id;
        self.frame_count += 1;
        self.hot_id = 0;
        self.next_id_counter = 1;
        self.id_depth = 0;
        self.layout_depth = 0;
        self.window_depth = 0;
        self.clip_rect = gfx.Rect{ .x = 0, .y = 0, .w = fb.width, .h = fb.height };
        self.fb.fill(gfx.rgb(
            @as(u8, @truncate((self.style.bg >> 16) & 0xFF)),
            @as(u8, @truncate((self.style.bg >> 8) & 0xFF)),
            @as(u8, @truncate(self.style.bg & 0xFF)),
        ));
    }

    pub fn endFrame(self: *Gui) void {
        if (self.active_id != 0 and !self.input.mouse_down) {
            self.active_id = 0;
        }
        self.mouse_capture_id = self.input.mouse_state.capture_id;
    }

    fn nextId(self: *Gui) u32 {
        const id = self.next_id_counter;
        self.next_id_counter += 1;
        return id;
    }

    fn getOrCreateState(self: *Gui, id: u32, t: WidgetStateType) *WidgetState {
        var i: usize = 0;
        while (i < self.state_count) : (i += 1) {
            if (self.state_items[i].id == id) return &self.state_items[i];
        }
        if (self.state_count < MAX_STATE_ITEMS) {
            const idx = self.state_count;
            self.state_count += 1;
            self.state_items[idx] = WidgetState{
                .id = id, .t = t,
                .text_buf = [_]u8{0} ** 256,
                .text_len = 0, .text_cursor = 0,
                .float_val = 0, .bool_val = false,
                .rect_x = 0, .rect_y = 0, .rect_w = 0, .rect_h = 0,
                .aux_x = 0, .aux_y = 0,
            };
            return &self.state_items[idx];
        }
        return &self.state_items[0];
    }

    fn isHot(self: *Gui, id: u32) bool { return self.hot_id == id; }
    fn isActive(self: *Gui, id: u32) bool { return self.active_id == id; }
    fn isFocused(self: *Gui, id: u32) bool { return self.focus_id == id; }

    fn testHot(self: *Gui, id: u32, x: i32, y: i32, w: u32, h: u32) bool {
        if (self.input.mouse_state.hot(id, mouse.rect(x, y, w, h))) {
            self.hot_id = id;
            return true;
        }
        return false;
    }

    fn getContentRegion(self: *Gui) gfx.Rect {
        if (self.layout_depth > 0) {
            const l = &self.layout_stack[self.layout_depth - 1];
            return gfx.Rect{ .x = l.cursor_x, .y = l.cursor_y, .w = 0, .h = 0 };
        }
        return gfx.Rect{ .x = 0, .y = 0, .w = self.fb.width, .h = self.fb.height };
    }

    pub fn button(self: *Gui, label_text: []const u8) bool {
        const id = self.nextId();
        const pad = @as(u32, self.style.padding);
        const bh: u32 = 24 + pad;
        var area = self.allocSpace(@as(u32, @intCast(label_text.len * 10 + pad * 2 + 20)), bh);
        if (area.w < 10) area.w = 80;

        const hovered = self.testHot(id, area.x, area.y, area.w, area.h);
        var clicked = false;

        if (hovered and self.input.mouse_clicked) {
            self.active_id = id;
            self.input.mouse_state.setCapture(id);
            self.mouse_capture_id = id;
        }
        if (self.isActive(id) and self.input.mouse_released) {
            if (hovered) clicked = true;
            self.active_id = 0;
            self.input.mouse_state.releaseCapture(id);
            self.mouse_capture_id = 0;
        }

        const active = self.isActive(id);
        const bg = if (active) self.style.button_active
            else if (hovered) self.style.button_hover
            else self.style.button_bg;

        const r = @min(self.style.rounding, @as(u8, @intCast(@min(area.w, area.h) / 2)));
        if (hovered or active) {
            drawShadow(self.fb, area.x, area.y, area.w, area.h, self.style.shadow, r);
        }
        fillRoundedRect(self.fb, area.x, area.y, area.w, area.h, r, bg);
        if (area.h > 6 and area.w > 6) {
            const top_h = @max(@as(u32, 2), area.h / 2);
            fillRect(self.fb, area.x + 1, area.y + 1, area.w - 2, top_h, lightenColor(bg, if (hovered) 26 else 14));
            fillRect(self.fb, area.x + 1, area.y + @as(i32, @intCast(area.h)) - 2, area.w - 2, 1, darkenColor(bg, 42));
        }
        if (active and area.w > @as(u32, r) * 2 + 2) {
            fillRect(self.fb, area.x + @as(i32, r), area.y + @as(i32, @intCast(area.h)) - 3, area.w - @as(u32, r) * 2, 2, self.style.accent);
        }
        const border = if (active) self.style.accent_hover else if (hovered) self.style.accent else self.style.border;
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, border);
        drawInsetBorder(self.fb, area.x + 1, area.y + 1, area.w -| 2, area.h -| 2, lightenColor(bg, 18), darkenColor(bg, 36));
        const tw = @as(i32, @intCast(label_text.len * 8));
        drawTextAt(self.fb, label_text,
            area.x + @divTrunc(@as(i32, @intCast(area.w)), 2) - @divTrunc(tw, 2),
            area.y + @divTrunc(@as(i32, @intCast(bh)), 2) - 4 + (if (active) @as(i32, 1) else @as(i32, 0)),
            self.style.button_text, 8);

        return clicked;
    }

    pub fn label(self: *Gui, text: []const u8) void {
        _ = self.nextId();
        const th: u32 = 16;
        const tw = @as(u32, @intCast(text.len * 8));
        const area = self.allocSpace(tw + 4, th);
        drawTextAt(self.fb, text, area.x + 2, area.y + 2, self.style.text, 8);
    }

    pub fn labelColored(self: *Gui, text: []const u8, color: u32) void {
        _ = self.nextId();
        const th: u32 = 16;
        const tw = @as(u32, @intCast(text.len * 8));
        const area = self.allocSpace(tw + 4, th);
        drawTextAt(self.fb, text, area.x + 2, area.y + 2, color, 8);
    }

    pub fn textInput(self: *Gui, label_text: []const u8, buf: []u8) bool {
        const id = self.nextId();
        const widget_id = id;
        const state = self.getOrCreateState(widget_id, .text_input);

        _ = label_text;
        if (state.text_len == 0 and buf.len > 0 and buf[0] != 0) {
            var bi: usize = 0;
            while (bi < buf.len and bi < 255 and buf[bi] != 0) : (bi += 1) {
                state.text_buf[bi] = buf[bi];
            }
            state.text_len = bi;
            state.text_cursor = bi;
        }

        const ih: u32 = 24;
        const iw: u32 = @max(160, @as(u32, @intCast(self.fb.width)) - 40);
        var area = self.allocSpace(iw, ih);
        if (area.w < 20) area.w = iw;

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);
        var changed = false;

        if (hovered and self.input.mouse_clicked) {
            self.active_id = widget_id;
            self.focus_id = widget_id;
        }

        const is_focused = self.isFocused(widget_id);

        if (is_focused and self.active_id == widget_id and !self.input.mouse_down) {
            self.active_id = 0;
        }

        if (is_focused) {
            if (self.input.keys_pressed[8] or self.input.keys_pressed[46]) {
                if (state.text_len > 0) {
                    if (state.text_cursor > 0) {
                        state.text_cursor -= 1;
                        var k: usize = state.text_cursor;
                        while (k < state.text_len) : (k += 1) {
                            state.text_buf[k] = state.text_buf[k + 1];
                        }
                        state.text_len -= 1;
                        changed = true;
                    }
                }
            }
            if (self.input.text_len > 0) {
                var ti: usize = 0;
                while (ti < self.input.text_len and state.text_len < 255) : (ti += 1) {
                    const ch = self.input.text_input[ti];
                    if (ch >= 32 and ch < 127) {
                        var k: usize = state.text_len;
                        while (k > state.text_cursor) : (k -= 1) {
                            state.text_buf[k] = state.text_buf[k - 1];
                        }
                        state.text_buf[state.text_cursor] = ch;
                        state.text_cursor += 1;
                        state.text_len += 1;
                        changed = true;
                    }
                }
            }
        }

        const bg = self.style.input_bg;
        const border = if (is_focused) self.style.accent else if (hovered) self.style.border else self.style.input_border;
        const r = @min(self.style.rounding, @as(u8, 4));
        fillRoundedRect(self.fb, area.x, area.y, area.w, area.h, r, bg);
        if (area.w > 6 and area.h > 6) {
            fillRect(self.fb, area.x + 1, area.y + 1, area.w - 2, 1, darkenColor(bg, 34));
            fillRect(self.fb, area.x + 1, area.y + @as(i32, @intCast(area.h)) - 2, area.w - 2, 1, lightenColor(bg, 24));
        }
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, border);
        if (is_focused and area.w > 4 and area.h > 4) {
            drawRectBorder(self.fb, area.x + 1, area.y + 1, area.w - 2, area.h - 2, mixColor(self.style.accent, bg, 95));
        }

        var display_buf: [257]u8 = undefined;
        const display_len: usize = state.text_len;
        var di: usize = 0;
        while (di < display_len) : (di += 1) {
            display_buf[di] = state.text_buf[di];
        }
        display_buf[display_len] = 0;

        const txt_x = area.x + 4;
        const txt_y = area.y + 4;
        drawTextAt(self.fb, display_buf[0..display_len], txt_x, txt_y, self.style.input_text, 8);

        if (is_focused and (self.frame_count / 30) % 2 == 0) {
            const cx = txt_x + @as(i32, @intCast(state.text_cursor * 8));
            fillRect(self.fb, cx, txt_y, 2, 16, self.style.accent);
        }

        if (changed and buf.len >= state.text_len) {
            var ci: usize = 0;
            while (ci < state.text_len) : (ci += 1) buf[ci] = state.text_buf[ci];
            if (state.text_len < buf.len) buf[state.text_len] = 0;
        }

        return changed;
    }

    pub fn checkbox(self: *Gui, label_text: []const u8, checked: *bool) void {
        const id = self.nextId();
        const widget_id = id;

        const ch: u32 = 20;
        const cw: u32 = 20;
        const area = self.allocSpace(cw + @as(u32, @intCast(label_text.len * 8 + 8)), ch + 4);

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);

        if (hovered and self.input.mouse_clicked) {
            checked.* = !checked.*;
            self.active_id = widget_id;
        }
        if (self.isActive(widget_id) and self.input.mouse_released) {
            self.active_id = 0;
        }

        const bx = area.x;
        const by = area.y + 2;
        const border = if (hovered) self.style.accent else self.style.border;
        const r = @min(self.style.rounding, @as(u8, 4));
        const box_bg = if (checked.*) mixColor(self.style.check_bg, self.style.accent, 150)
            else if (hovered) lightenColor(self.style.check_bg, 18)
            else self.style.check_bg;
        fillRoundedRect(self.fb, bx, by, cw, ch, r, box_bg);
        fillRect(self.fb, bx + 2, by + 2, cw - 4, 1, lightenColor(box_bg, 22));
        drawRectBorder(self.fb, bx, by, cw, ch, border);

        if (checked.*) {
            const mark = self.style.check_mark;
            drawLineRaw(self.fb, bx + 5, by + 10, bx + 8, by + 13, mark);
            drawLineRaw(self.fb, bx + 6, by + 10, bx + 9, by + 13, mark);
            drawLineRaw(self.fb, bx + 8, by + 13, bx + 15, by + 5, mark);
            drawLineRaw(self.fb, bx + 9, by + 13, bx + 16, by + 5, mark);
        }

        drawTextAt(self.fb, label_text, bx + @as(i32, @intCast(cw)) + 6, by + 1, if (hovered) self.style.text else self.style.text_dim, 8);
    }

    pub fn slider(self: *Gui, label_text: []const u8, value: *f32, min: f32, max: f32) bool {
        const id = self.nextId();
        const widget_id = id;

        const sh: u32 = 22;
        const sw: u32 = @max(120, @as(u32, @intCast(self.fb.width - 40)));
        var area = self.allocSpace(sw, sh + 18);
        if (area.w < 20) area.w = sw;

        const track_h: u32 = 8;
        const thumb_w: u32 = 14;
        const thumb_h: u32 = 18;
        const track_x = area.x;
        const track_y = area.y + @as(i32, @intCast(sh));
        const track_w = area.w;

        const range = max - min;
        const raw_norm = if (range != 0) (value.* - min) / range else 0.0;
        const norm = @min(@as(f32, 1.0), @max(@as(f32, 0.0), raw_norm));
        const travel_w = if (track_w > 1) track_w - 1 else track_w;
        const thumb_x = track_x + @as(i32, @intFromFloat(@as(f64, norm) * @as(f64, @floatFromInt(travel_w))));

        const hovered = self.testHot(widget_id, track_x, area.y, track_w, area.h);

        var changed = false;

        if (hovered and self.input.mouse_clicked) {
            self.active_id = widget_id;
            self.input.mouse_state.setCapture(widget_id);
            self.mouse_capture_id = widget_id;
        }

        if (self.isActive(widget_id)) {
            const rel_x = self.input.mouse_x - track_x;
            const new_norm = @min(1.0, @max(0.0, @as(f32, @floatFromInt(rel_x)) / @as(f32, @floatFromInt(track_w))));
            const new_val = min + new_norm * range;
            if (new_val != value.*) {
                value.* = new_val;
                changed = true;
            }
            if (!self.input.mouse_down) {
                self.active_id = 0;
                self.input.mouse_state.releaseCapture(widget_id);
                self.mouse_capture_id = 0;
            }
        }

        const is_active = self.isActive(widget_id);
        const thumb_fill = if (is_active) self.style.accent_hover else self.style.slider_thumb;
        const tr = @min(self.style.rounding, @as(u8, 4));

        fillRoundedRect(self.fb, track_x, track_y, track_w, track_h, tr, darkenColor(self.style.slider_track, 18));
        fillRect(self.fb, track_x + 1, track_y + 1, track_w -| 2, 1, lightenColor(self.style.slider_track, 18));

        const fill_w: u32 = @intCast(@max(0, thumb_x - track_x));
        if (fill_w > 0) {
            fillRoundedRect(self.fb, track_x, track_y, fill_w, track_h, tr, self.style.accent);
            fillRect(self.fb, track_x + 1, track_y + 1, fill_w -| 2, 1, lightenColor(self.style.accent, 24));
        }

        const hx = thumb_x - @divTrunc(@as(i32, @intCast(thumb_w)), 2);
        const hy = track_y - @divTrunc(@as(i32, @intCast(thumb_h - track_h)), 2);
        drawShadow(self.fb, hx, hy, thumb_w, thumb_h, if (hovered or is_active) self.style.shadow else 10, tr + 2);
        fillRoundedRect(self.fb, hx, hy, thumb_w, thumb_h, tr + 2, thumb_fill);
        fillRect(self.fb, hx + 2, hy + 2, thumb_w - 4, 1, lightenColor(thumb_fill, 35));
        drawRectBorder(self.fb, hx, hy, thumb_w, thumb_h, if (is_active) self.style.accent_hover else self.style.border);

        var lbl_buf: [32]u8 = undefined;
        var lbl_len: usize = 0;
        if (label_text.len > 0) {
            for (label_text) |ch| { if (lbl_len < 30) { lbl_buf[lbl_len] = ch; lbl_len += 1; } }
            lbl_buf[lbl_len] = ' '; lbl_len += 1;
            lbl_buf[lbl_len] = ':'; lbl_len += 1;
            lbl_buf[lbl_len] = ' '; lbl_len += 1;
        }
        const ival = @as(i32, @intFromFloat(value.*));
        var num_buf: [16]u8 = undefined;
        var num_len: usize = 0;
        if (ival == 0 and value.* < 0) {
            if (num_len < 15) { num_buf[num_len] = '-'; num_len += 1; }
        }
        const tmp = @abs(value.*);
        const int_part = @as(i32, @intFromFloat(tmp));
        var tmp2 = int_part;
        var digits: [16]u8 = undefined;
        var dc: usize = 0;
        if (tmp2 == 0) { digits[dc] = '0'; dc += 1; }
        else { while (tmp2 > 0) { digits[dc] = @as(u8, @intCast('0' + @mod(tmp2, 10))); tmp2 = @divTrunc(tmp2, 10); dc += 1; } }
        var di2: usize = dc;
        while (di2 > 0) {
            di2 -= 1;
            if (num_len < 15) { num_buf[num_len] = digits[di2]; num_len += 1; }
        }
        const frac = @as(i32, @intFromFloat((tmp - @as(f32, @floatFromInt(int_part))) * 100));
        if (num_len < 15) { num_buf[num_len] = '.'; num_len += 1; }
        const f1 = @abs(frac) / 10;
        const f2 = @abs(frac) % 10;
        if (num_len < 15) { num_buf[num_len] = @as(u8, @intCast('0' + @as(u8, @intCast(f1)))); num_len += 1; }
        if (num_len < 15) { num_buf[num_len] = @as(u8, @intCast('0' + @as(u8, @intCast(f2)))); num_len += 1; }

        for (num_buf[0..num_len]) |ch| {
            if (lbl_len < 30) { lbl_buf[lbl_len] = ch; lbl_len += 1; }
        }

        drawTextAt(self.fb, lbl_buf[0..lbl_len], area.x, area.y + 2, if (hovered or is_active) self.style.text else self.style.text_dim, 8);
        return changed;
    }

    pub fn collapsible(self: *Gui, label_text: []const u8, open: *bool) bool {
        const id = self.nextId();
        const widget_id = id;

        const h: u32 = 24;
        const tw = @as(u32, @intCast(label_text.len * 8));
        const area = self.allocSpace(tw + 40, h);

        const hovered = self.testHot(widget_id, area.x, area.y, area.w, area.h);
        var opened_this_frame = false;

        if (hovered and self.input.mouse_clicked) {
            open.* = !open.*;
            opened_this_frame = true;
            self.active_id = widget_id;
        }
        if (self.isActive(widget_id) and self.input.mouse_released) {
            self.active_id = 0;
        }

        const bg = if (hovered) self.style.button_hover else self.style.header_bg;
        const r = @min(self.style.rounding, @as(u8, 4));
        fillRoundedRect(self.fb, area.x, area.y, area.w, area.h, r, bg);
        if (area.w > 8 and area.h > 8) {
            fillRect(self.fb, area.x + 1, area.y + 1, area.w - 2, 1, lightenColor(bg, 22));
            fillRect(self.fb, area.x + @as(i32, r), area.y + @as(i32, @intCast(area.h)) - 3, area.w - @as(u32, r) * 2, 2, if (open.*) self.style.accent else self.style.separator);
        }
        drawRectBorder(self.fb, area.x, area.y, area.w, area.h, if (hovered) self.style.accent else self.style.border);

        const arrow = if (open.*) "v" else ">";
        drawTextAt(self.fb, arrow, area.x + 4, area.y + 4, self.style.header_text, 8);
        drawTextAt(self.fb, label_text, area.x + 20, area.y + 4, self.style.header_text, 8);

        if (open.*) {
            const indent = self.style.button_bg;
            _ = indent;
            self.addSpace(0, 2);
        }

        return open.*;
    }

    pub fn comboBox(self: *Gui, label_text: []const u8, items: []const []const u8, current: *usize) bool {
        const id = self.nextId();
        const state = self.getOrCreateState(id, .none);
        const is_open = state.bool_val;

        const bh: u32 = 24;
        const tw = @as(u32, @intCast(label_text.len * 8 + 8));
        var total_w = tw;
        var mi: usize = 0;
        while (mi < items.len) : (mi += 1) {
            const iw = @as(u32, @intCast(items[mi].len * 8 + 16));
            if (iw > total_w) total_w = iw;
        }
        if (total_w < 100) total_w = 100;

        const area = self.allocSpace(total_w, bh);
        const r = @min(self.style.rounding, @as(u8, 4));
        const hovered = self.testHot(id, area.x, area.y, total_w, bh);

        if (hovered and self.input.mouse_clicked) {
            state.bool_val = !state.bool_val;
            self.active_id = id;
        }
        if (self.isActive(id) and self.input.mouse_released) {
            if (!hovered and is_open) {
                var ci: usize = 0;
                while (ci < items.len) : (ci += 1) {
                    const iy = area.y + @as(i32, @intCast(bh)) + @as(i32, @intCast(ci * bh));
                    if (self.input.mouse_y >= iy and self.input.mouse_y < iy + @as(i32, @intCast(bh))) {
                        current.* = ci;
                        state.bool_val = false;
                        self.active_id = 0;
                        return true;
                    }
                }
                state.bool_val = false;
            }
            self.active_id = 0;
        }

        const box_bg = if (hovered or is_open) lightenColor(self.style.input_bg, 16) else self.style.input_bg;
        fillRoundedRect(self.fb, area.x, area.y, total_w, bh, r, box_bg);
        if (total_w > 6 and bh > 6) {
            fillRect(self.fb, area.x + 1, area.y + 1, total_w - 2, 1, lightenColor(box_bg, 24));
            fillRect(self.fb, area.x + @as(i32, @intCast(total_w)) - 22, area.y + 1, 1, bh - 2, self.style.separator);
        }
        drawRectBorder(self.fb, area.x, area.y, total_w, bh, if (is_open) self.style.accent else if (hovered) self.style.border else self.style.input_border);
        if (current.* < items.len) {
            drawTextAt(self.fb, items[current.*], area.x + 6, area.y + 4, self.style.text, 8);
        }
        drawTextAt(self.fb, if (is_open) "v" else ">", area.x + @as(i32, @intCast(total_w)) - 15, area.y + 4, if (is_open) self.style.accent else self.style.text_dim, 8);

        if (is_open) {
            const total_h = bh * @as(u32, @intCast(items.len));
            drawShadow(self.fb, area.x, area.y + @as(i32, @intCast(bh)), total_w, total_h, self.style.shadow, r);
            var ci: usize = 0;
            while (ci < items.len) : (ci += 1) {
                const iy = area.y + @as(i32, @intCast(bh)) + @as(i32, @intCast(ci * bh));
                const isel = ci == current.*;
                const item_hover = self.input.mouse_x >= area.x and self.input.mouse_x < area.x + @as(i32, @intCast(total_w)) and
                    self.input.mouse_y >= iy and self.input.mouse_y < iy + @as(i32, @intCast(bh));
                const ibg = if (isel) self.style.accent else if (item_hover) self.style.button_hover else self.style.panel_bg;
                fillRoundedRect(self.fb, area.x, iy, total_w, bh, 0, ibg);
                if (isel) {
                    fillRect(self.fb, area.x, iy, 3, bh, self.style.accent_hover);
                }
                drawRectBorder(self.fb, area.x, iy, total_w, bh, self.style.border);
                drawTextAt(self.fb, items[ci], area.x + 6, iy + 4, if (isel) self.style.button_text else self.style.text, 8);
            }
            drawRectBorder(self.fb, area.x, area.y + bh, total_w, total_h, self.style.border);
        }

        if (!is_open and state.bool_val) {
            state.bool_val = false;
        }

        return false;
    }

    pub fn separator(self: *Gui) void {
        const id = self.nextId();
        _ = id;
        const area = self.allocSpace(10, 6);
        const cy = area.y + 2;
        const cw = if (self.layout_depth > 0) self.layout_stack[self.layout_depth - 1].w else @as(u32, @intCast(self.fb.width));
        fillRoundedRect(self.fb, area.x, cy, cw, 2, 1, self.style.separator);
    }

    pub fn sameLine(self: *Gui, spacing: i32) void {
        if (self.layout_depth > 0) {
            const l = &self.layout_stack[self.layout_depth - 1];
            if (l.mode == .vertical) {
                l.cursor_x = l.max_x + spacing;
                l.max_x = l.cursor_x;
            }
        }
    }

    pub fn addSpace(self: *Gui, w: u32, h: u32) void {
        _ = self.nextId();
        _ = self.allocSpace(w, h);
    }

    pub fn beginVertical(self: *Gui) void {
        const id = self.nextId();
        const pos = self.getContentRegion();
        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = pos.x, .y = pos.y, .w = 0, .h = 0,
                .cursor_x = pos.x, .cursor_y = pos.y,
                .max_x = pos.x, .max_y = pos.y,
                .mode = .vertical, .spacing = @as(i32, self.style.spacing), .indent = 0,
            };
            self.layout_depth += 1;
        }
        _ = id;
    }

    pub fn endVertical(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
            const l = self.layout_stack[self.layout_depth];
            self.addSpace(@as(u32, @intCast(@max(0, l.max_x - l.x))),
                @as(u32, @intCast(@max(0, l.max_y - l.y))));
        }
    }

    pub fn beginHorizontal(self: *Gui) void {
        const id = self.nextId();
        const pos = self.getContentRegion();
        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = pos.x, .y = pos.y, .w = 0, .h = 0,
                .cursor_x = pos.x, .cursor_y = pos.y,
                .max_x = pos.x, .max_y = pos.y,
                .mode = .horizontal, .spacing = @as(i32, self.style.spacing), .indent = 0,
            };
            self.layout_depth += 1;
        }
        _ = id;
    }

    pub fn endHorizontal(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
            const l = self.layout_stack[self.layout_depth];
            self.addSpace(@as(u32, @intCast(@max(0, l.max_x - l.x))),
                @as(u32, @intCast(@max(0, l.max_y - l.y))));
        }
    }

    pub fn beginWindow(self: *Gui, title: []const u8, x: i32, y: i32, w: u32, h: u32, resizable: bool) bool {
        const id = self.nextId();
        const title_h: i32 = 28;
        const win_state = self.getOrCreateState(id, .none);
        if (win_state.rect_w == 0 or win_state.rect_h == 0) {
            win_state.rect_x = x;
            win_state.rect_y = y;
            win_state.rect_w = w;
            win_state.rect_h = h;
        }
        var win_x = win_state.rect_x;
        var win_y = win_state.rect_y;
        var win_w = win_state.rect_w;
        var win_h = win_state.rect_h;

        if (self.window_depth < MAX_WINDOW_STACK) {
            var ws = WindowState{
                .x = win_x, .y = win_y, .w = win_w, .h = win_h,
                .title_h = title_h,
                .dragging = win_state.bool_val, .drag_off_x = win_state.aux_x, .drag_off_y = win_state.aux_y,
                .id = id,
            };

            const drag_h = title_h;
            const drag_id = id + 0x1000;
            const hover_title = self.testHot(drag_id, win_x, win_y, win_w, @as(u32, @intCast(drag_h)));

            if (hover_title and self.input.mouse_clicked) {
                self.active_id = drag_id;
                self.input.mouse_state.setCapture(drag_id);
                self.mouse_capture_id = drag_id;
                ws.dragging = true;
                ws.drag_off_x = self.input.mouse_x - win_x;
                ws.drag_off_y = self.input.mouse_y - win_y;
                win_state.bool_val = true;
                win_state.aux_x = ws.drag_off_x;
                win_state.aux_y = ws.drag_off_y;
            }

            if (ws.dragging and self.isActive(drag_id)) {
                win_x = self.input.mouse_x - ws.drag_off_x;
                win_y = self.input.mouse_y - ws.drag_off_y;
                ws.x = win_x;
                ws.y = win_y;
                win_state.rect_x = win_x;
                win_state.rect_y = win_y;
                if (!self.input.mouse_down) {
                    ws.dragging = false;
                    win_state.bool_val = false;
                    self.active_id = 0;
                    self.input.mouse_state.releaseCapture(drag_id);
                    self.mouse_capture_id = 0;
                }
            } else if (!self.input.mouse_down and win_state.bool_val) {
                win_state.bool_val = false;
            }

            self.window_stack[self.window_depth] = ws;
            self.window_depth += 1;
        }

        const wr = self.style.window_rounding;
        drawShadow(self.fb, win_x, win_y, win_w, win_h, self.style.shadow, wr);
        fillRoundedRect(self.fb, win_x, win_y, win_w, win_h, wr, self.style.panel_bg);
        fillRoundedRect(self.fb, win_x, win_y, win_w, @as(u32, @intCast(title_h)), wr, self.style.title_bg);
        if (win_w > 8) {
            fillRect(self.fb, win_x + @as(i32, wr), win_y + 1, win_w - @as(u32, wr) * 2, 1, lightenColor(self.style.title_bg, 24));
            fillRect(self.fb, win_x + @as(i32, wr), win_y + @as(i32, @intCast(title_h)) - 3, win_w - @as(u32, wr) * 2, 2, self.style.accent);
        }
        drawTextAt(self.fb, title, win_x + 10, win_y + 7, self.style.title_text, 8);

        const client_y = win_y + title_h;
        const client_h = win_h - @as(u32, @intCast(title_h));
        if (client_h > 4 and win_w > 4) {
            fillRect(self.fb, win_x + 1, client_y, win_w - 2, 1, darkenColor(self.style.panel_bg, 18));
            fillRect(self.fb, win_x + 1, win_y + @as(i32, @intCast(win_h)) - 2, win_w - 2, 1, lightenColor(self.style.panel_bg, 12));
        }
        drawRectBorder(self.fb, win_x, win_y, win_w, win_h, self.style.border);
        drawInsetBorder(self.fb, win_x + 1, win_y + 1, win_w -| 2, win_h -| 2, lightenColor(self.style.panel_bg, 14), darkenColor(self.style.panel_bg, 34));

        if (resizable) {
            const resize_id = id + 0x2000;
            const rs: i32 = 12;
            _ = self.testHot(resize_id, win_x + @as(i32, @intCast(win_w)) - rs, win_y + @as(i32, @intCast(win_h)) - rs, @as(u32, @intCast(rs)), @as(u32, @intCast(rs)));
            if (self.isHot(resize_id) and self.input.mouse_clicked) {
                self.active_id = resize_id;
                self.input.mouse_state.setCapture(resize_id);
                self.mouse_capture_id = resize_id;
            }
            if (self.isActive(resize_id)) {
                const new_w = @max(100, self.input.mouse_x - win_x);
                const new_h = @max(60, self.input.mouse_y - win_y);
                if (self.window_depth > 0) {
                    self.window_stack[self.window_depth - 1].w = @as(u32, @intCast(new_w));
                    self.window_stack[self.window_depth - 1].h = @as(u32, @intCast(new_h));
                }
                win_w = @as(u32, @intCast(new_w));
                win_h = @as(u32, @intCast(new_h));
                win_state.rect_w = win_w;
                win_state.rect_h = win_h;
                if (!self.input.mouse_down) {
                    self.active_id = 0;
                    self.input.mouse_state.releaseCapture(resize_id);
                    self.mouse_capture_id = 0;
                }
            }
            drawLineRaw(self.fb, win_x + @as(i32, @intCast(win_w)) - 11, win_y + @as(i32, @intCast(win_h)) - 4, win_x + @as(i32, @intCast(win_w)) - 4, win_y + @as(i32, @intCast(win_h)) - 11, self.style.text_dim);
            drawLineRaw(self.fb, win_x + @as(i32, @intCast(win_w)) - 8, win_y + @as(i32, @intCast(win_h)) - 4, win_x + @as(i32, @intCast(win_w)) - 4, win_y + @as(i32, @intCast(win_h)) - 8, self.style.text_dim);
        }

        if (self.layout_depth < MAX_LAYOUT_STACK) {
            self.layout_stack[self.layout_depth] = LayoutFrame{
                .x = win_x + 8, .y = client_y + 4, .w = win_w -| 16, .h = client_h -| 8,
                .cursor_x = win_x + 8, .cursor_y = client_y + 4,
                .max_x = win_x + 8, .max_y = client_y + 4,
                .mode = .vertical, .spacing = @as(i32, self.style.spacing), .indent = 0,
            };
            self.layout_depth += 1;
        }

        return true;
    }

    pub fn endWindow(self: *Gui) void {
        if (self.layout_depth > 0) {
            self.layout_depth -= 1;
        }
    }

    fn allocSpace(self: *Gui, w: u32, h: u32) gfx.Rect {
        if (self.layout_depth == 0) {
            return gfx.Rect{ .x = 0, .y = 0, .w = w, .h = h };
        }
        const l = &self.layout_stack[self.layout_depth - 1];
        const rx = l.cursor_x;
        const ry = l.cursor_y;

        if (l.mode == .vertical) {
            l.cursor_y += @as(i32, @intCast(h)) + l.spacing;
            l.cursor_x = l.x;
            if (w > @as(u32, @intCast(l.max_x - l.x))) {
                l.max_x = l.x + @as(i32, @intCast(w));
            }
            if (l.cursor_y > l.max_y) {
                l.max_y = l.cursor_y;
            }
            if (w < 1) {
                l.cursor_x = l.x;
            }
            const lw: u32 = @as(u32, @intCast(@max(0, l.max_x - l.x)));
            _ = lw;
            return gfx.Rect{ .x = rx, .y = ry, .w = if (w > 0) w else @as(u32, @intCast(@max(0, l.w))), .h = h };
        } else {
            l.cursor_x += @as(i32, @intCast(w)) + l.spacing;
            if (l.cursor_x > l.max_x) l.max_x = l.cursor_x;
            const lh: u32 = @as(u32, @intCast(@max(0, l.max_y - l.y)));
            _ = lh;
            return gfx.Rect{ .x = rx, .y = ry, .w = w, .h = if (h > 0) h else 20 };
        }
    }
};

fn colorR(c: u32) u8 { return @as(u8, @intCast((c >> 16) & 0xFF)); }
fn colorG(c: u32) u8 { return @as(u8, @intCast((c >> 8) & 0xFF)); }
fn colorB(c: u32) u8 { return @as(u8, @intCast(c & 0xFF)); }
fn colorA(c: u32) u8 { return @as(u8, @intCast((c >> 24) & 0xFF)); }

pub fn mixColor(a: u32, b: u32, amount_b: u8) u32 {
    const ia = @as(u32, 255 - amount_b);
    const ib = @as(u32, amount_b);
    const r = (@as(u32, colorR(a)) * ia + @as(u32, colorR(b)) * ib) / 255;
    const g = (@as(u32, colorG(a)) * ia + @as(u32, colorG(b)) * ib) / 255;
    const bl = (@as(u32, colorB(a)) * ia + @as(u32, colorB(b)) * ib) / 255;
    const al = (@as(u32, colorA(a)) * ia + @as(u32, colorA(b)) * ib) / 255;
    return (al << 24) | (r << 16) | (g << 8) | bl;
}

pub fn lightenColor(c: u32, amount: u8) u32 {
    return mixColor(c, 0xFFFFFFFF, amount);
}

pub fn darkenColor(c: u32, amount: u8) u32 {
    return mixColor(c, 0xFF000000, amount);
}

fn fillRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w == 0 or h == 0) return;
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const raw_x2 = x + @as(i32, @intCast(w));
    const raw_y2 = y + @as(i32, @intCast(h));
    if (raw_x2 <= 0 or raw_y2 <= 0) return;
    const x2: u32 = @min(@as(u32, @intCast(raw_x2)), fb.width);
    const y2: u32 = @min(@as(u32, @intCast(raw_y2)), fb.height);
    if (x2 <= x1 or y2 <= y1) return;
    var yi = y1;
    while (yi < y2) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        var xi = x1;
        while (xi < x2) : (xi += 1) {
            fb.pixels[row + xi] = color;
        }
    }
}

pub fn fillRoundedRect(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, r: u8, color: u32) void {
    if (r == 0 or w < @as(u32, @intCast(r * 2 + 2)) or h < @as(u32, @intCast(r * 2 + 2))) {
        fillRect(fb, x, y, w, h, color);
        return;
    }
    const rr = @as(u32, r);
    const x1: u32 = if (x < 0) 0 else @intCast(x);
    const y1: u32 = if (y < 0) 0 else @intCast(y);
    const x2_: u32 = @min(x1 + w, fb.width);
    const y2_: u32 = @min(y1 + h, fb.height);
    var yi = y1;
    while (yi < y2_) : (yi += 1) {
        const row = @as(usize, yi) * fb.stride;
        const local_y = yi - y1;
        var xi = x1;
        while (xi < x2_) : (xi += 1) {
            const local_x = xi - x1;
            var in_corner = false;
            if (local_x < rr and local_y < rr) {
                const dx = rr - local_x - 1;
                const dy = rr - local_y - 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x >= w - rr and local_y < rr) {
                const dx = local_x - (w - rr) + 1;
                const dy = rr - local_y - 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x < rr and local_y >= h - rr) {
                const dx = rr - local_x - 1;
                const dy = local_y - (h - rr) + 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            } else if (local_x >= w - rr and local_y >= h - rr) {
                const dx = local_x - (w - rr) + 1;
                const dy = local_y - (h - rr) + 1;
                if (dx * dx + dy * dy > rr * rr) in_corner = true;
            }
            if (!in_corner) {
                fb.pixels[row + xi] = color;
            }
        }
    }
}

pub fn drawShadow(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, intensity: u8, r: u8) void {
    if (intensity == 0) return;
    const steps = @as(u32, @min(@as(u32, intensity) / 20 + 1, 4));
    var s: u32 = 1;
    while (s <= steps) : (s += 1) {
        const alpha = intensity / (s * 2 + 1);
        if (alpha < 5) continue;
        const shadow_color: u32 = 0xFF000000 | (@as(u32, alpha) << 16) | (@as(u32, alpha) << 8) | @as(u32, alpha);
        const off = @as(i32, @intCast(s));
        const sr = if (r > s) r - @as(u8, @intCast(s)) else 0;
        fillRoundedRect(fb, x + off, y + off, w, h, sr, shadow_color);
    }
}

fn drawRectBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    if (w < 2 or h < 2) {
        fillRect(fb, x, y, w, h, color);
        return;
    }
    fillRect(fb, x, y, w, 1, color);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, color);
    fillRect(fb, x, y, 1, h, color);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, color);
}

fn drawInsetBorder(fb: *gfx.Framebuffer, x: i32, y: i32, w: u32, h: u32, light: u32, dark: u32) void {
    if (w < 2 or h < 2) return;
    fillRect(fb, x, y, w, 1, light);
    fillRect(fb, x, y, 1, h, light);
    fillRect(fb, x, y + @as(i32, @intCast(h)) - 1, w, 1, dark);
    fillRect(fb, x + @as(i32, @intCast(w)) - 1, y, 1, h, dark);
}

fn drawLineRaw(fb: *gfx.Framebuffer, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) void {
    const dx: i32 = if (x2 >= x1) x2 - x1 else x1 - x2;
    const dy_abs: i32 = if (y2 >= y1) y2 - y1 else y1 - y2;
    const dy: i32 = -dy_abs;
    const sx: i32 = if (x1 < x2) 1 else -1;
    const sy: i32 = if (y1 < y2) 1 else -1;
    var err = dx + dy;
    var cx = x1;
    var cy = y1;
    while (true) {
        if (cx >= 0 and cy >= 0 and cx < @as(i32, @intCast(fb.width)) and cy < @as(i32, @intCast(fb.height))) {
            fb.pixels[@as(usize, @intCast(cy)) * fb.stride + @as(usize, @intCast(cx))] = color;
        }
        if (cx == x2 and cy == y2) break;
        const e2 = 2 * err;
        if (e2 >= dy) { err += dy; cx += sx; }
        if (e2 <= dx) { err += dx; cy += sy; }
    }
}

fn drawTextAt(fb: *gfx.Framebuffer, text: []const u8, x: i32, y: i32, color: u32, size: u32) void {
    const scale = if (size >= 8) @as(u32, @intCast(@divFloor(size, 8))) else 1;
    var cx = x;
    var cy = y;
    for (text) |ch| {
        if (ch == '\n') { cy += @as(i32, @intCast(scale * 8 + 2)); cx = x; continue; }
        const glyph = gfx.getGlyph(ch);
        var gy: u32 = 0;
        while (gy < 8) : (gy += 1) {
            var gx: u32 = 0;
            while (gx < 8) : (gx += 1) {
                if ((glyph[gy] & (@as(u8, 1) << @intCast(7 - gx))) != 0) {
                    const bx = cx + @as(i32, @intCast(gx * scale));
                    const by = cy + @as(i32, @intCast(gy * scale));
                    var sy: u32 = 0;
                    while (sy < scale) : (sy += 1) {
                        var sx: u32 = 0;
                        while (sx < scale) : (sx += 1) {
                            const px = bx + @as(i32, @intCast(sx));
                            const py = by + @as(i32, @intCast(sy));
                            if (px >= 0 and py >= 0 and px < @as(i32, @intCast(fb.width)) and py < @as(i32, @intCast(fb.height))) {
                                fb.pixels[@as(usize, @intCast(py)) * fb.stride + @as(usize, @intCast(px))] = color;
                            }
                        }
                    }
                }
            }
        }
        cx += @as(i32, @intCast(scale * 8 + 2));
    }
}
