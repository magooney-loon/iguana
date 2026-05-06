shader_type canvas_item;

// ── UI Material Overlay — Aero Glass ────────────────────────────────────────
// Subtle animated grain, pulsing vignette, and Frutiger Aero gloss
// (specular band, lighting gradient, fresnel edge, directional bevel,
// micro-texture).  Everything is driven by TIME so the surface never
// feels completely static.

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.04;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 3.0;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 1.2;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.08;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.85;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.02;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.5;

group_uniforms Aero;
uniform float specular_strength : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float specular_y_pos    : hint_range(0.1, 0.9, 0.05)  = 0.28;
uniform float specular_height   : hint_range(0.02, 0.3, 0.01) = 0.12;
uniform float specular_curve    : hint_range(0.5, 4.0, 0.1)   = 1.8;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.05;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.025;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  FILM GRAIN  (multi-octave, animated)
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 100.0 + fract(t_a * 0.7) * 37.0);
	grain += hash12(g_uv * 200.0 + fract(t_a * 1.3) * 53.0) * 0.5;
	grain += hash12(g_uv * 400.0 + fract(t_a * 2.1) * 71.0) * 0.25;
	grain = (grain / 1.75) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  PULSING VIGNETTE
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	float vig_pulse = sin(t * vignette_pulse_spd) * vignette_pulse;
	float vig_r = vignette_radius + vig_pulse;
	float vignette = smoothstep(vig_r, vig_r - 0.4, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  FRUTIGER AERO GLOSS
	//      Specular band, lighting gradient, fresnel edge, directional
	//      bevel, and micro-texture.
	// ══════════════════════════════════════════════════════════════════════

	// Specular highlight — curved elliptical gloss band (upper portion)
	float spec_y = (uv.y - specular_y_pos) / max(specular_height, 0.001);
	float spec_x = 1.0 - pow(abs(uv.x - 0.5) * 2.0, specular_curve);
	float specular = exp(-spec_y * spec_y * 4.0) * max(spec_x, 0.0);

	// Top-to-bottom lighting gradient (1 at top, 0 at bottom)
	float lighting_grad = 1.0 - uv.y;

	// Fresnel edge bloom — edges catch more light like real glass
	float f_edge_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fresnel = smoothstep(fresnel_width, 0.0, f_edge_d);

	// Directional bevel — light source from top-left
	float bv_top    = smoothstep(bevel_width, 0.0, uv.y);
	float bv_left   = smoothstep(bevel_width, 0.0, uv.x);
	float bv_bottom = smoothstep(bevel_width, 0.0, 1.0 - uv.y);
	float bv_right  = smoothstep(bevel_width, 0.0, 1.0 - uv.x);
	float bevel_hi  = bv_top * 0.6 + bv_left * 0.4;
	float bevel_sh  = bv_bottom * 0.4 + bv_right * 0.6;

	// Micro-texture for material grain
	float gloss_tex = hash12(uv * 512.0 + 7.3) - 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Grain (signed additive)
	result += grain_amt;

	// Vignette darkens edges
	result -= vig_amt;

	// Aero gloss — specular highlight band
	result += specular * specular_strength;
	// Aero gloss — top-bright / bottom-dark gradient
	result += (lighting_grad - 0.4) * gradient_strength;
	// Aero gloss — fresnel edge bloom
	result += fresnel * fresnel_strength;
	// Aero gloss — directional bevel (light top-left, shadow bottom-right)
	result += bevel_hi * bevel_strength;
	result -= bevel_sh * bevel_strength * 0.6;
	// Aero gloss — micro-texture grain
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
