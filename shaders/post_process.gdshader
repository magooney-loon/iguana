shader_type canvas_item;
// @meta: skip

uniform sampler2D screen_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex  : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float exposure       = 0.35;
uniform float tonemap_knee   = 0.0;   // 0 = bypass tonemap
uniform float gamma          = 0.93;   // 1.0 = bypass; <1 lifts, >1 darkens
uniform float vignette_dark  = 0.30;   // 0 = no vignette, 1 = black edges
uniform float grain_strength = 0.012;  // 0 = off
uniform float time_val       = 0.0;

void fragment() {
	vec3 col = texture(screen_tex, UV).rgb;

	col *= exposure;

	// Reinhard tonemap (bypassed when knee = 0)
	col = col / (1.0 + col * tonemap_knee);

	// Gamma (bypassed when gamma = 1.0)
	col = pow(max(col, vec3(0.0)), vec3(gamma));

	// Vignette
	vec2 vc    = UV - 0.5;
	float vign = 1.0 - smoothstep(0.25, 1.2, length(vc) * 1.8);
	col *= mix(vignette_dark, 1.0, vign);

	// Film grain
	float grain = texture(noise_tex, UV * 300.0 + fract(time_val * 0.07)).r;
	col += (grain - 0.5) * grain_strength;

	COLOR = vec4(col, 1.0);
}
