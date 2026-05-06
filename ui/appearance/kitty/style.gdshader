shader_type canvas_item;

// ── UI Material Overlay — Kitty Satin ───────────────────────────────────────
// Soft satin sheen with flowing ribbon highlights, delicate bubble caustics,
// and a pearlescent shimmer. Warmer and rounder than Aero glass, without the
// hard edges or reptilian texture. Driven by TIME + audio uniforms
// (beat, energy, bass) for gentle, dreamy reactivity.

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.03;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 2.5;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 0.6;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.06;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.85;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.015;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.3;

group_uniforms Satin;
uniform float specular_strength : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float specular_y_pos    : hint_range(0.1, 0.9, 0.05)  = 0.25;
uniform float specular_height   : hint_range(0.02, 0.3, 0.01) = 0.15;
uniform float corner_radius   : hint_range(0.0, 0.15, 0.005) = 0.045;
uniform float beat            : hint_range(0.0, 1.0)          = 0.0;
uniform float energy          : hint_range(0.0, 1.0)          = 0.0;
uniform float bass            : hint_range(0.0, 1.0)          = 0.0;
uniform float wave_seed       : hint_range(0.0, 100.0, 0.1)   = 0.0;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.06;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.030;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;
uniform float caustic_scale    : hint_range(1.0, 20.0, 0.5)  = 6.0;
uniform float iridescence      : hint_range(0.0, 1.0, 0.05)  = 0.55;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise for flowing ribbons
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional Brownian motion — layered noise for soft flowing shapes
float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += vnoise(p) * amp;
		p *= 2.1;
		amp *= 0.5;
	}
	return val;
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  SOFT FILM GRAIN  (gentler than aero, warm tinted)
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 80.0 + fract(t_a * 0.5) * 31.0);
	grain += hash12(g_uv * 160.0 + fract(t_a * 0.9) * 47.0) * 0.5;
	grain = (grain / 1.5) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  SOFT PULSING VIGNETTE  (gentler falloff)
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	float vig_pulse = sin(t * vignette_pulse_spd) * vignette_pulse;
	float vig_r = vignette_radius + vig_pulse;
	float vignette = smoothstep(vig_r, vig_r - 0.5, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  SATIN SHEEN
	//      Flowing ribbon highlights, soft bubble caustics, pearlescent
	//      iridescence with warm pinkish-cast. No hard edges.
	// ══════════════════════════════════════════════════════════════════════

	// Top-to-bottom lighting gradient (softer curve)
	float lighting_grad = pow(1.0 - uv.y, 1.3);

	// Fresnel edge bloom — softer, wider spread
	float f_edge_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fresnel = smoothstep(fresnel_width * 1.5, 0.0, f_edge_d);

	// Gentle bevel — even lighting all around (softer than directional)
	float bv_all = smoothstep(bevel_width, 0.0, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	float bevel_soft = bv_all;

	// Rounded rect SDF for edge glow (same as aero)
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0);

	// ── Flowing satin ribbons ──────────────────────────────────────────
	// Use FBM noise to create soft, undulating ribbon shapes that drift
	// across the surface. Audio makes them pulse and breathe.
	float ws = wave_seed;
	vec2 flow_uv = uv + vec2(
		sin(t * 0.3 + ws) * 0.04,
		cos(t * 0.25 + ws * 1.3) * 0.03
	);
	float ribbon_noise = fbm(flow_uv * 3.5 + t * 0.15 + ws * 0.5);

	// Create 2-3 diagonal ribbon bands that shift with time
	float ribbon1 = sin((uv.x + uv.y) * 8.0 + ribbon_noise * 6.0 + t * 0.4 + ws);
	float ribbon2 = sin((uv.x - uv.y * 0.7) * 6.0 - ribbon_noise * 4.0 + t * 0.3 + ws * 2.1);
	float ribbon = max(ribbon1, ribbon2);
	ribbon = smoothstep(0.3, 1.0, ribbon);

	// Audio reactivity — ribbons breathe with bass, shimmer with energy
	float ribbon_audio = 1.0 + beat * 0.3 + energy * 0.15;
	ribbon *= ribbon_audio;

	// ── Soft bubble caustics ───────────────────────────────────────────
	// Gentler, rounder caustic pattern compared to aero's sharp ones
	float c_t = t * 0.08;
	float c1 = sin(uv.x * caustic_scale * 0.8 + sin(uv.y * caustic_scale + c_t) * 1.5);
	float c2 = cos(uv.y * caustic_scale * 0.7 + cos(uv.x * caustic_scale * 0.6 - c_t * 0.5) * 1.3);
	float caustic = (c1 + c2) * 0.25 + 0.5;
	caustic = caustic * caustic; // softer curve — more bubble, less glass

	// ── Soft top highlight ─────────────────────────────────────────────
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 200.0) * 0.35;

	// Edge glow with ribbon and caustic modulation
	float fade = 2.8 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);
	float dir_bias = 1.0 + (0.5 - uv.y) * 0.4; // subtler than aero
	edge_glow *= dir_bias;

	// Combine specular: edge glow + caustics + top highlight + ribbon
	float specular = edge_glow * mix(1.0, caustic, 0.35) + top_glow;
	specular += ribbon * 0.2;

	// Iridescent color — warm rose-gold center, cool lavender at edges
	float edge_f = abs(uv.x - 0.5) * 2.0;
	vec3 spec_color = mix(
		vec3(1.0, 0.92, 0.90),    // warm rose-white center
		vec3(0.80, 0.75, 1.0),     // soft lavender at edges
		edge_f * iridescence
	);

	// Micro-texture — very fine, soft satin feel
	float gloss_tex = hash12(uv * 400.0 + 3.7) - 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Grain
	result += grain_amt;

	// Vignette
	result -= vig_amt;

	// Satin specular + ribbon highlights
	result += specular * spec_color * specular_strength;
	// Lighting gradient
	result += (lighting_grad - 0.4) * gradient_strength;
	// Fresnel edge bloom
	result += fresnel * fresnel_strength * vec3(1.0, 0.92, 0.95); // warm tint
	// Soft bevel (even, no directional bias)
	result += bevel_soft * bevel_strength * 0.5;
	// Micro-texture
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
