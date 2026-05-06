class_name UISkin
extends Resource

## Shape and shader parameters for the Iguana player UI.
## To create a custom skin: duplicate this file, adjust the values, save as
## ui/skins/<your_name>.tres, then set skin_name in Settings.
## Point shader_path at your own .gdshader for a completely different look.

@export var shader_path: String = "res://ui/skins/style/ui_noise.gdshader"

@export_group("Shape")
@export var btn_radius:     float = 7.0
@export var panel_radius:   float = 10.0
@export var bar_radius:     float = 12.0
@export var logo_radius:    float = 18.0
@export var bar_shadow_size: int  = 16
@export var bar_padding_h:  float = 14.0
@export var bar_padding_v:  float = 8.0

@export_group("Sliders")
@export var slider_track_compact: float = 4.0
@export var slider_track_normal:  float = 6.0
@export var slider_grab_compact:  float = 12.0
@export var slider_grab_normal:   float = 14.0

@export_group("Separator")
@export var sep_base_wave: float = 0.5
@export var sep_base_cap:  float = 1.8

@export_group("Shader — Subtle Mode")
@export var subtle_grain_strength:    float = 0.025
@export var subtle_grain_speed:       float = 0.8
@export var subtle_vignette_strength: float = 0.05
@export var subtle_vignette_pulse:    float = 0.012
@export var subtle_vignette_pulse_spd: float = 0.35
@export var subtle_specular_strength: float = 0.15
@export var subtle_specular_y_pos:    float = 0.02
@export var subtle_specular_height:   float = 0.18
@export var subtle_corner_radius:     float = 0.04
@export var subtle_gradient_strength: float = 0.05
@export var subtle_fresnel_strength:  float = 0.06
@export var subtle_fresnel_width:     float = 0.05
@export var subtle_bevel_strength:    float = 0.10
@export var subtle_bevel_width:       float = 0.025
@export var subtle_gloss_texture_str: float = 0.012
@export var subtle_caustic_scale:     float = 8.0
@export var subtle_iridescence:       float = 0.5

@export_group("Shader — Normal Mode")
@export var normal_grain_strength:    float = 0.04
@export var normal_grain_speed:       float = 1.2
@export var normal_vignette_strength: float = 0.09
@export var normal_vignette_pulse:    float = 0.02
@export var normal_vignette_pulse_spd: float = 0.5
@export var normal_specular_strength: float = 0.25
@export var normal_specular_y_pos:    float = 0.01
@export var normal_specular_height:   float = 0.22
@export var normal_corner_radius:     float = 0.035
@export var normal_gradient_strength: float = 0.10
@export var normal_fresnel_strength:  float = 0.12
@export var normal_fresnel_width:     float = 0.06
@export var normal_bevel_strength:    float = 0.18
@export var normal_bevel_width:       float = 0.03
@export var normal_gloss_texture_str: float = 0.02
@export var normal_caustic_scale:     float = 10.0
@export var normal_iridescence:       float = 0.65
