shader_type canvas_item;

// ── UI Material Overlay — Iguana Glass ──────────────────────────────────────
// Warmer, more organic glass feel — deeper vignette, softer specular,
// earthy iridescence, gentle caustic ripples.  Less "tech gloss" than
// Aero, more "living leaf" — warm amber highlights, cool moss shadows.
// Driven by TIME + audio uniforms (beat, energy, bass).

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.03;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 2.5;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 0.6;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.07;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.80;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.015;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.25;

group_uniforms Glass;
uniform float specular_strength : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float specular_y_pos    : hint_range(0.1, 0.9, 0.05)  = 0.25;
uniform float specular_height   : hint_range(0.02, 0.3, 0.01) = 0.15;
uniform float corner_radius     : hint_range(0.0, 0.15, 0.005) = 0.05;
uniform float beat              : hint_range(0.0, 1.0)          = 0.0;
uniform float energy            : hint_range(0.0, 1.0)          = 0.0;
uniform float bass              : hint_range(0.0, 1.0)          = 0.0;
uniform float wave_seed         : hint_range(0.0, 100.0, 0.1)   = 0.0;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.06;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.0;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;
uniform float caustic_scale     : hint_range(1.0, 20.0, 0.5)  = 6.0;
uniform float iridescence       : hint_range(0.0, 1.0, 0.05)  = 0.55;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash12_animated(vec2 p, float t_offset) {
	return hash12(p + fract(t_offset) * 47.0);
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  FILM GRAIN  — softer, slower, more filmic than Aero
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 80.0 + fract(t_a * 0.5) * 31.0);
	grain += hash12(g_uv * 160.0 + fract(t_a * 0.9) * 47.0) * 0.5;
	grain += hash12(g_uv * 320.0 + fract(t_a * 1.5) * 67.0) * 0.25;
	grain = (grain / 1.75) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  PULSING VIGNETTE  — wider, softer breathing
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	// Breathing driven by bass for a living feel
	float vig_breath = sin(t * vignette_pulse_spd + wave_seed * 0.1) * vignette_pulse;
	vig_breath += bass * 0.01;
	float vig_r = vignette_radius + vig_breath;
	float vignette = smoothstep(vig_r, vig_r - 0.5, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  IGUANA GLASS  — organic warmth, living depth
	//      Softer specular, earthy iridescence, mossy caustics.
	// ══════════════════════════════════════════════════════════════════════

	// Top-to-bottom gradient — warm light from above
	float lighting_grad = 1.0 - uv.y;

	// Fresnel — softer, wider spread like light catching a leaf edge
	float f_edge_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fresnel = smoothstep(fresnel_width * 1.4, 0.0, f_edge_d);

	// Directional bevel — warm light top-left, cool shadow bottom-right
	float bv_top    = smoothstep(bevel_width, 0.0, uv.y);
	float bv_left   = smoothstep(bevel_width, 0.0, uv.x);
	float bv_bottom = smoothstep(bevel_width, 0.0, 1.0 - uv.y);
	float bv_right  = smoothstep(bevel_width, 0.0, 1.0 - uv.x);
	float bevel_hi  = bv_top * 0.5 + bv_left * 0.5;
	float bevel_sh  = bv_bottom * 0.5 + bv_right * 0.5;

	// Organic specular — rounded rectangle SDF like Aero but softer decay
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0);

	// Gentler exponential glow — more spread, less concentrated
	float fade = 2.8 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);

	// Soft overhead bias
	float dir_bias = 1.0 + (0.5 - uv.y) * 0.4;
	edge_glow *= dir_bias;

	// Living wave — slower, wider undulation, bass-reactive
	float wave_amp = 0.04 + beat * 0.10 + bass * 0.06;
	float ws = wave_seed;
	float wave  = sin(uv.x * 18.0 + t * 1.2 + ws * 6.28 + sin(uv.y * 8.0 + t * 0.5 + ws) * 1.5) * wave_amp;
	wave += sin(uv.y * 12.0 - t * 0.8 + ws * 3.14 + cos(uv.x * 6.0 + t * 0.3 + ws * 0.5) * 1.0) * wave_amp * 0.6;
	edge_glow *= (1.0 + wave);

	// Mossy caustics — slower, wider ripples like light through foliage
	float c_t = t * 0.08;
	float c1 = sin(uv.x * caustic_scale + sin(uv.y * caustic_scale * 1.1 + c_t) * 1.6);
	float c2 = cos(uv.y * caustic_scale * 0.8 + cos(uv.x * caustic_scale * 0.6 - c_t * 0.5) * 1.4);
	float caustic = abs(c1 + c2) * 0.2 + 0.5;

	// Soft top highlight — warmer than Aero
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 250.0) * 0.35;

	// Combine specular layers
	float specular = edge_glow * mix(1.0, caustic, 0.3) + top_glow;

	// Earthy iridescence — warm amber center, cool moss green at edges
	float edge_f = abs(uv.x - 0.5) * 2.0;
	vec3 spec_color = mix(
		vec3(1.0, 0.92, 0.80),   // warm amber center
		vec3(0.55, 0.78, 0.60),   // mossy green edges
		edge_f * iridescence
	);

	vec3 glass_spec = specular * spec_color;

	// Micro-texture — slightly coarser, more organic grain
	float gloss_tex = hash12(uv * 400.0 + 11.7) - 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Grain
	result += grain_amt;

	// Vignette
	result -= vig_amt;

	// Glass specular — warm organic glow
	result += glass_spec * specular_strength;

	// Warm top → cool bottom gradient
	result += (lighting_grad - 0.4) * gradient_strength;

	// Fresnel — subtle edge bloom
	result += fresnel * fresnel_strength * vec3(0.85, 0.95, 0.80);

	// Bevel — warm highlight, cool shadow
	result += bevel_hi * bevel_strength * vec3(1.0, 0.95, 0.85);
	result -= bevel_sh * bevel_strength * 0.5 * vec3(0.8, 0.9, 0.75);

	// Organic micro-texture
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
