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

@export_group("Sliders")
@export var slider_track_compact: float = 4.0
@export var slider_track_normal:  float = 6.0
@export var slider_grab_compact:  float = 12.0
@export var slider_grab_normal:   float = 14.0

@export_group("Separator")
@export var sep_base_wave: float = 0.5
@export var sep_base_cap:  float = 1.8
