class_name UIStyle
extends Resource

## Shader + effect parameters for the Iguana player UI.
## To create a custom style: duplicate this file, point shader_path at your
## own .gdshader, adjust the params, save as ui/styles/<your_name>.tres,
## then set style_name in Settings.

@export var shader_path: String = "res://ui/appearance/styles/aero_glass.gdshader"

@export_group("Logo")
@export var logo_visible: bool = true
@export_enum("Center", "Left", "Right") var logo_anchor: int = 0

@export_group("Animation")
@export var anim_autohide_duration: float = 0.35
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var anim_autohide_trans: int = 7
@export var anim_win_open_duration: float = 0.30
@export_enum("In", "Out", "In Out", "Out In") var anim_win_open_ease: int = 1
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var anim_win_open_trans: int = 7
@export var anim_win_close_duration: float = 0.22
@export_enum("In", "Out", "In Out", "Out In") var anim_win_close_ease: int = 0
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic", "Cubic", "Circ", "Bounce", "Back", "Spring") var anim_win_close_trans: int = 7
@export var anim_win_fade_in:    float = 0.22
@export var anim_win_fade_out:   float = 0.18
@export var anim_crossfade_out:  float = 0.20
@export var anim_crossfade_in:   float = 0.30

@export_group("Shader — Subtle Mode")
@export var subtle_grain_strength:     float = 0.025
@export var subtle_grain_speed:        float = 0.8
@export var subtle_vignette_strength:  float = 0.05
@export var subtle_vignette_pulse:     float = 0.012
@export var subtle_vignette_pulse_spd: float = 0.35
@export var subtle_specular_strength:  float = 0.15
@export var subtle_specular_y_pos:     float = 0.02
@export var subtle_specular_height:    float = 0.18
@export var subtle_corner_radius:      float = 0.04
@export var subtle_gradient_strength:  float = 0.05
@export var subtle_fresnel_strength:   float = 0.06
@export var subtle_fresnel_width:      float = 0.05
@export var subtle_bevel_strength:     float = 0.10
@export var subtle_bevel_width:        float = 0.025
@export var subtle_gloss_texture_str:  float = 0.012
@export var subtle_caustic_scale:      float = 8.0
@export var subtle_iridescence:        float = 0.5

@export_group("Shader — Normal Mode")
@export var normal_grain_strength:     float = 0.04
@export var normal_grain_speed:        float = 1.2
@export var normal_vignette_strength:  float = 0.09
@export var normal_vignette_pulse:     float = 0.02
@export var normal_vignette_pulse_spd: float = 0.5
@export var normal_specular_strength:  float = 0.25
@export var normal_specular_y_pos:     float = 0.01
@export var normal_specular_height:    float = 0.22
@export var normal_corner_radius:      float = 0.035
@export var normal_gradient_strength:  float = 0.10
@export var normal_fresnel_strength:   float = 0.12
@export var normal_fresnel_width:      float = 0.06
@export var normal_bevel_strength:     float = 0.18
@export var normal_bevel_width:        float = 0.03
@export var normal_gloss_texture_str:  float = 0.02
@export var normal_caustic_scale:      float = 10.0
@export var normal_iridescence:        float = 0.65
