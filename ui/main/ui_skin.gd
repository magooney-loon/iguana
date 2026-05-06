class_name UISkin
extends Resource

## Shape parameters for the Iguana player UI.
## To create a custom skin: duplicate this file, adjust the values, save as
## ui/skins/<your_name>.tres, then set skin_name in Settings.
## For shader/effect changes use a UIStyle instead.

@export_group("Shape")
@export var btn_radius:      float = 7.0
@export var panel_radius:    float = 10.0
@export var bar_radius:      float = 12.0
@export var logo_radius:     float = 18.0
@export var bar_shadow_size: int   = 16
@export var bar_padding_h:   float = 14.0
@export var bar_padding_v:   float = 8.0

@export_group("Buttons")
@export var btn_margin_h:              float = 10.0
@export var btn_margin_top:            float = 4.0
@export var btn_margin_bottom:         float = 4.0
@export var btn_hover_shadow:          int    = 14
@export var btn_pressed_margin_top:    float = 5.0
@export var btn_pressed_margin_bottom: float = 3.0
@export var btn_pressed_shadow:        int    = 4

@export_group("Sliders")
@export var slider_track_compact:  float = 4.0
@export var slider_track_normal:   float = 6.0
@export var slider_grab_compact:   float = 12.0
@export var slider_grab_normal:    float = 14.0
@export var slider_radius_compact: float = 4.0
@export var slider_radius_normal:  float = 5.0
@export var slider_grabber_shadow: int   = 4
@export var slider_grabber_h_shadow: int = 6

@export_group("Windows")
@export var win_title_radius:    float = 14.0
@export var win_tab_radius:       float = 8.0
@export var win_tab_panel_radius: float = 10.0
@export var win_tab_margin:       float = 10.0
@export var win_footer_radius:    float = 8.0

@export_group("Playlist Rows")
@export var row_radius:       float = 6.0
@export var row_margin_h:     float = 10.0
@export var row_margin_v:     float = 5.0
@export var row_btn_radius:   float = 5.0
@export var row_btn_margin_h: float = 4.0
@export var row_btn_margin_v: float = 3.0

@export_group("Logo")
@export var logo_margin_h:      float = 8.0
@export var logo_margin_top:    float = 5.0
@export var logo_margin_bottom: float = 2.0
@export var logo_icon_size:     float = 40.0

@export_group("Separator")
@export var sep_base_wave:  float = 0.5
@export var sep_base_cap:   float = 1.8
@export var sep_h_margin:   float = 10.0
@export var sep_v_margin:   float = 5.0
