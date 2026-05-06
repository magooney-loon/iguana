shader_type canvas_item;

// ── UI Material Overlay — Aero Glass ────────────────────────────────────────
// Subtle animated grain, pulsing vignette, and Frutiger Aero gloss
// (curved edge specular with caustics, lighting gradient, fresnel edge,
// directional bevel, micro-texture).  Driven by TIME + audio uniforms
// (beat, energy, bass) for organic, beat-reactive flow.

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
uniform float corner_radius   : hint_range(0.0, 0.15, 0.005) = 0.04;
uniform float beat            : hint_range(0.0, 1.0)          = 0.0;
uniform float energy          : hint_range(0.0, 1.0)          = 0.0;
uniform float bass            : hint_range(0.0, 1.0)          = 0.0;
uniform float wave_seed       : hint_range(0.0, 100.0, 0.1)   = 0.0;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.05;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.025;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;
uniform float caustic_scale    : hint_range(1.0, 20.0, 0.5)  = 8.0;
uniform float iridescence      : hint_range(0.0, 1.0, 0.05)  = 0.5;


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

	// Liquid glass specular — curved edges, wavy flow, audio-reactive
	// Rounded rectangle SDF for curved edge glow matching panel corners
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0); // positive inside, 0 at edge and outside

	// Exponential glow from the curved edge
	float fade = 3.5 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);

	// Directional bias — overhead light makes top brighter, bottom subtler
	float dir_bias = 1.0 + (0.5 - uv.y) * 0.6;
	edge_glow *= dir_bias;

	// Flowing wave animation — organic, audio-reactive, per-panel unique
	float wave_amp = 0.06 + beat * 0.15 + energy * 0.05;
	float ws = wave_seed;
	float wave  = sin(uv.x * 25.0 + t * 1.8 + ws * 6.28 + sin(uv.y * 10.0 + t * 0.7 + ws) * 2.0) * wave_amp;
	wave += sin(uv.y * 18.0 - t * 1.2 + ws * 4.17 + cos(uv.x * 8.0 + t * 0.5 + ws * 0.7) * 1.5) * wave_amp * 0.7;
	edge_glow *= (1.0 + wave);

	// Caustic ripples — light concentrating through curved glass surface
	float c_t = t * 0.12;
	float c1 = sin(uv.x * caustic_scale + sin(uv.y * caustic_scale * 1.3 + c_t) * 2.0);
	float c2 = cos(uv.y * caustic_scale * 0.9 + cos(uv.x * caustic_scale * 0.7 - c_t * 0.7) * 1.8);
	float caustic = abs(c1 + c2) * 0.25 + 0.5;

	// Soft top edge highlight — light catching the glass curve (gentler)
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 300.0) * 0.4;

	// Combine: curved edge glow with caustics + soft top highlight
	float specular = edge_glow * mix(1.0, caustic, 0.4) + top_glow;

	// Iridescent color — warm white center, cool blue at edges
	float edge_f = abs(uv.x - 0.5) * 2.0;
	vec3 spec_color = mix(vec3(1.0, 0.97, 0.94), vec3(0.65, 0.82, 1.0), edge_f * iridescence);

	// Pack for combine
	vec3 aero_spec = specular * spec_color;

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

	// Aero gloss — liquid glass specular with edge-wrapped caustics
	result += aero_spec * specular_strength;
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
