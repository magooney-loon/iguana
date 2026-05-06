class_name UITheme
extends Resource

## Color scheme for the Iguana player UI.
## To create a custom theme: duplicate this file, adjust the colors, save as
## ui/themes/<your_name>.tres, then set theme_name in Settings.

@export_group("Glass Panels")
@export var c_glass      := Color(0.08, 0.09, 0.16, 0.68)
@export var c_glass_lt   := Color(0.14, 0.16, 0.26, 0.55)
@export var c_glass_dark := Color(0.06, 0.07, 0.12, 0.72)
@export var c_logo       := Color(0.06, 0.07, 0.12, 0.88)

@export_group("Borders & Shadows")
@export var c_border  := Color(0.55, 0.65, 0.85, 0.18)
@export var c_hilite  := Color(0.70, 0.80, 1.00, 0.22)
@export var c_shadow  := Color(0.00, 0.00, 0.02, 0.45)

@export_group("Buttons")
@export var c_btn   := Color(0.16, 0.18, 0.28, 0.35)
@export var c_btn_h := Color(0.30, 0.38, 0.55, 0.45)
@export var c_btn_p := Color(0.08, 0.09, 0.14, 0.50)
@export var c_accent := Color(0.40, 0.58, 0.92, 0.35)

@export_group("Sliders")
@export var c_slider_bg   := Color(0.06, 0.07, 0.12, 0.55)
@export var c_slider_fill := Color(0.30, 0.48, 0.80, 0.55)
@export var c_grabber     := Color(0.55, 0.72, 1.00, 0.85)
@export var c_grabber_h   := Color(0.70, 0.85, 1.00, 0.95)

@export_group("Panels")
@export var c_title_bar    := Color(0.10, 0.11, 0.18, 0.60)
@export var c_panel_bg     := Color(0.04, 0.05, 0.09, 0.60)
@export var c_footer_bar   := Color(0.08, 0.09, 0.15, 0.55)
@export var c_active_row   := Color(0.22, 0.34, 0.56, 0.50)

@export_group("Separators & Text")
@export var c_sep      := Color(0.45, 0.55, 0.75, 0.15)
@export var c_sep_draw := Color(0.45, 0.55, 0.75, 0.22)
@export var c_link     := Color(0.55, 0.75, 1.00, 1.00)
@export var c_link_h   := Color(0.70, 0.88, 1.00, 1.00)
@export var c_section     := Color(0.55, 0.80, 1.00, 0.75)
@export var c_text_hi     := Color(0.70, 0.82, 1.00, 1.00)
@export var c_text_dim    := Color(0.55, 0.65, 0.85, 0.55)

@export_group("Notification")
@export var c_notify_shadow := Color(0.0, 0.0, 0.0, 0.6)
@export var notify_offset   := Vector2(16, 14)

@export_group("Font Sizes")
@export var font_notification := 22
@export var font_title        := 14
@export var font_body         := 12
@export var font_section      := 10
@export var font_version      := 11

@export_group("Text Opacity")
@export var a_time_label   := 0.70
@export var a_footer_stats := 0.60
@export var a_info_text    := 0.75
@export var a_label_text   := 0.55
@export var a_tagline      := 0.65
@export var a_version      := 0.35
@export var a_empty_msg    := 0.45
@export var a_track_num    := 0.40
@export var a_duration     := 0.50
@export var a_dim_icon     := 0.50

@export_group("Tabs")
@export var c_tab_fg    := Color(0.30, 0.38, 0.55, 0.45)
@export var c_tab_bg    := Color(0.16, 0.18, 0.28, 0.35)
@export var c_tab_hover := Color(0.40, 0.58, 0.92, 0.35)

@export_group("Dropdown")
@export var c_drop_bg       := Color(0.10, 0.12, 0.20, 0.85)
@export var c_drop_border   := Color(0.55, 0.65, 0.85, 0.25)
@export var c_drop_hover    := Color(0.25, 0.35, 0.55, 0.50)
@export var c_drop_pressed  := Color(0.15, 0.20, 0.35, 0.60)

@export_group("Debug")
@export var c_dbg_bg      := Color(0.03, 0.04, 0.08, 0.50)
@export var c_dbg_fill    := Color(0.35, 0.52, 0.85, 0.55)
