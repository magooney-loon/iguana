shader_type canvas_item;

// ── Audio engine uniforms ────────────────────────────────────────────
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;

uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;

uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;

uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;

uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm         = 120.0;
uniform float time_val    = 0.0;

uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define TAU 6.28318530718
#define PI  3.14159265359

// ── Utility ──────────────────────────────────────────────────────────
mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// ── Deep color palettes — never white, always saturated ──────────────
// Cycles through deep indigo → violet → magenta → crimson
vec3 deep_palette(float t) {
	vec3 a = vec3(0.22, 0.05, 0.32);
	vec3 b = vec3(0.30, 0.18, 0.35);
	vec3 c = vec3(1.0, 0.7, 0.5);
	vec3 d = vec3(0.00, 0.15, 0.20);
	return clamp(a + b * cos(TAU * (c * t + d)), 0.0, 1.0);
}

// Teal / cyan accent — cycles through deep ocean tones
vec3 teal_palette(float t) {
	vec3 a = vec3(0.02, 0.12, 0.18);
	vec3 b = vec3(0.08, 0.28, 0.30);
	vec3 c = vec3(1.0, 0.8, 0.6);
	vec3 d = vec3(0.10, 0.25, 0.15);
	return clamp(a + b * cos(TAU * (c * t + d)), 0.0, 1.0);
}

// Warm accent — deep crimson / amber
vec3 warm_palette(float t) {
	vec3 a = vec3(0.25, 0.04, 0.06);
	vec3 b = vec3(0.30, 0.12, 0.10);
	vec3 c = vec3(0.8, 0.6, 0.5);
	vec3 d = vec3(0.05, 0.10, 0.25);
	return clamp(a + b * cos(TAU * (c * t + d)), 0.0, 1.0);
}

// ── Morphing shape: continuously interpolates between polygons ───────
// sides: continuous float (3.0=triangle, 4.0=square, 5.0=pentagon, etc.)
// star_depth: 0=polygon, positive=star points grow outward
// roundness: 0=polygon, 1=circle
// wobble: organic radius perturbation amplitude
float morph_shape(vec2 p, float radius, float sides, float star_depth,
                  float roundness, float wobble, float t_off, float thick) {
	float r = length(p);
	float a = atan(p.y, p.x);

	float n = max(sides, 3.0);
	float an = TAU / n;
	float da = mod(a + an * 0.5, an) - an * 0.5;

	// Polygon polar radius
	float poly_r = radius * cos(PI / n) / max(cos(da), 0.001);

	// Star: extends at vertices, retracts between
	float star = 1.0 + star_depth * 0.4 * cos(n * a);

	// Organic wobble: slow breathing perturbation
	float w = 1.0 + wobble * (
		sin(a * 3.0 + t_off * 0.7) * 0.15 +
		sin(a * 5.0 - t_off * 1.1) * 0.10 +
		sin(a * 8.0 + t_off * 0.4) * 0.05
	);

	float shaped = poly_r * star * w;
	float circular = radius * star * w;
	float target_r = mix(shaped, circular, roundness);

	float d = abs(r - target_r);
	return exp(-d * thick);
}

// Soft inner fill for the same shape
float morph_fill(vec2 p, float radius, float sides, float star_depth,
                 float roundness, float wobble, float t_off) {
	float r = length(p);
	float a = atan(p.y, p.x);

	float n = max(sides, 3.0);
	float an = TAU / n;
	float da = mod(a + an * 0.5, an) - an * 0.5;
	float poly_r = radius * cos(PI / n) / max(cos(da), 0.001);
	float star = 1.0 + star_depth * 0.4 * cos(n * a);
	float w = 1.0 + wobble * (
		sin(a * 3.0 + t_off * 0.7) * 0.15 +
		sin(a * 5.0 - t_off * 1.1) * 0.10
	);
	float shaped = poly_r * star * w;
	float circular = radius * star * w;
	float target_r = mix(shaped, circular, roundness);

	return smoothstep(target_r + 0.002, target_r - 0.03, r);
}

// ── Orbital position (Lissajous-like) ────────────────────────────────
vec2 orbit_pos(float fi, float t, float spread) {
	float speed1 = 0.07 + fi * 0.023;
	float speed2 = speed1 * (0.6 + fi * 0.07);
	float rx = (0.12 + fi * 0.035) * spread;
	float ry = (0.08 + fi * 0.025) * spread;
	return vec2(
		sin(t * speed1 + fi * 0.897) * rx + cos(t * speed2 * 0.5 + fi * 2.1) * rx * 0.3,
		cos(t * speed2 + fi * 1.234) * ry + sin(t * speed1 * 0.4 + fi * 0.6) * ry * 0.3
	);
}

void fragment() {
	vec2 uv = UV;
	float aspect = rect_size.x / rect_size.y;
	vec2 uv_c = uv - 0.5;
	uv_c.x *= aspect;

	float t = time_val;

	// ── Feedback loop ───────────────────────────────────────────────
	vec2 fb_center = uv - 0.5;
	fb_center.x *= aspect;

	float zoom = 0.968 - sub_bass * 0.015;
	fb_center *= zoom;

	fb_center *= rot2(0.005 + energy * 0.007);

	vec2 warp = vec2(
		sin(fb_center.y * 10.0 + t * 1.5) * 0.007,
		cos(fb_center.x * 8.0  + t * 1.2) * 0.007
	);
	warp *= 0.5 + activity * 0.8;

	vec2 fb_uv = fb_center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;
	vec2 sample_uv = fb_uv + warp;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	float decay = 0.925 + energy * 0.05;
	trail *= decay * edge_fade;

	// Kick inversion: briefly flip feedback into negative-space
	float invert = smoothstep(0.65, 0.95, kick) * beat_confidence;
	trail = mix(trail, vec3(0.25, 0.05, 0.35) - trail, invert * 0.25);

	// ── Deep void background (not pure black — faint pulsing indigo) ─
	vec3 bg = vec3(0.015, 0.003, 0.035) * (1.0 + sub_bass * 0.4 + energy * 0.2);
	vec3 col = bg;

	// Outline thickness: soft glow, not razor-sharp
	float thick = 35.0 + energy * 20.0;
	float thick_fine = 55.0 + energy * 30.0;

	// Kick-explosion: all shapes briefly expand on kick
	float kick_pulse = kick * 0.06 * beat_confidence;
	// Snare-spike: shapes grow star points on snare
	float snare_star = snare * 0.5 * beat_confidence;

	// ── 1. CENTRAL MANDALA — slow morph, multiple nested layers ─────
	{
		// Sides slowly cycle: 3 → 5 → 8 → 5 → 3 over ~40 seconds
		float sides_base = 3.0 + 2.5 * (1.0 + sin(t * 0.08))
		                     + 1.5 * (1.0 + sin(t * 0.05 + 1.0));
		// Beat can snap sides toward integer for one frame
		float sides_snap = beat * beat_confidence * 2.0;
		float sides = sides_base + sides_snap;

		float star = 0.3 + 0.25 * sin(t * 0.25) + snare_star;
		float roundness = 0.15 + 0.15 * sin(t * 0.18 + 0.5);
		float wobble = 0.3 + energy * 0.4;

		// Outer ring
		float r_outer = 0.18 + energy * 0.04 + sub_bass * 0.03 + kick_pulse;
		r_outer *= 1.0 + 0.08 * sin(beat_phase * TAU) * beat_confidence;

		vec2 p = uv_c * rot2(t * 0.06);
		float outline = morph_shape(p, r_outer, sides, star, roundness, wobble, t, thick);
		float fill = morph_fill(p, r_outer * 0.92, sides, star, roundness, wobble, t);

		vec3 mandala_col = deep_palette(t * 0.06);
		col += mandala_col * outline * 0.065;
		col += mandala_col * fill * 0.012;

		// Middle ring — different morph phase
		float r_mid = r_outer * 0.55;
		float sides_mid = sides + 2.0 + sin(t * 0.12) * 1.5;
		float star_mid = 0.15 + 0.2 * sin(t * 0.3 + 1.0) + snare_star * 0.6;
		vec2 p_mid = uv_c * rot2(-t * 0.04 + 0.3);
		float outline_mid = morph_shape(p_mid, r_mid, sides_mid, star_mid,
		                                roundness * 0.5, wobble * 0.6, t + 3.0, thick_fine);
		vec3 mid_col = teal_palette(t * 0.08 + 0.4);
		col += mid_col * outline_mid * 0.05;

		// Inner ring — small, fast morph
		float r_inner = r_outer * 0.28;
		float sides_inner = 4.0 + 3.0 * sin(t * 0.15 + 2.0);
		float star_inner = 0.5 + 0.3 * sin(t * 0.35);
		vec2 p_inner = uv_c * rot2(t * 0.1);
		float outline_inner = morph_shape(p_inner, r_inner, sides_inner, star_inner,
		                                  0.05, wobble * 0.8, t + 7.0, thick_fine);
		vec3 inner_col = warm_palette(t * 0.07 + 0.2);
		col += inner_col * outline_inner * 0.04;
	}

	// ── 2. ORBITING MORPHING SHAPES ─────────────────────────────────
	float spread = 0.8 + energy * 0.4;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);

		vec2 center = orbit_pos(fi, t, spread);

		// Each shape morphs independently at its own rate
		float morph_rate = 0.08 + fi * 0.04;
		float sides = 3.0 + fract(t * morph_rate + fi * 0.37) * 5.0;

		float star = 0.2 + 0.35 * sin(t * 0.2 + fi * 1.3) + snare_star * (0.3 + fi * 0.05);
		float roundness = 0.1 + 0.25 * sin(t * 0.13 + fi * 0.9);
		float wobble = 0.2 + energy * 0.3;

		float radius = 0.035 + fi * 0.006 + energy * 0.012 + kick_pulse * (0.5 + fi * 0.1);
		float shape_rot = t * (0.08 + fi * 0.025) * (1.0 - fi * 0.03) + fi * PI / 8.0;

		vec2 p = uv_c - center;
		p *= rot2(shape_rot);

		float outline = morph_shape(p, radius, sides, star, roundness, wobble, t + fi * 2.0, thick);
		float fill = morph_fill(p, radius * 0.9, sides, star, roundness, wobble * 0.5, t + fi * 2.0);

		// Color: cycle each shape through palette with unique offset
		float color_t = fi / 8.0 + t * 0.04;
		// Alternate between deep and teal palettes
		vec3 shape_col = mix(
			deep_palette(color_t),
			teal_palette(color_t + 0.3),
			sin(fi * 0.8 + t * 0.03) * 0.5 + 0.5
		);

		col += shape_col * outline * 0.06;
		col += shape_col * fill * 0.008;
	}

	// ── 3. OUTER RING — large slow shapes far from center ───────────
	for (int i = 0; i < 4; i++) {
		float fi = float(i);

		// Wide orbit
		float angle = t * (0.03 + fi * 0.01) + fi * TAU / 4.0;
		float orbit_r = 0.35 + energy * 0.08 + sin(t * 0.05 + fi) * 0.03;
		vec2 center = vec2(cos(angle), sin(angle)) * orbit_r;

		float sides = 5.0 + 3.0 * sin(t * 0.06 + fi * 1.7);
		float star = 0.4 + 0.3 * sin(t * 0.15 + fi * 0.9) + snare_star;
		float roundness = 0.2 + 0.2 * cos(t * 0.1 + fi);
		float wobble = 0.4 + bass * 0.3;

		float radius = 0.07 + fi * 0.01 + sub_bass * 0.02 + kick_pulse;

		vec2 p = uv_c - center;
		p *= rot2(-t * 0.04 + fi * PI / 4.0);

		float outline = morph_shape(p, radius, sides, star, roundness, wobble,
		                            t + fi * 4.0, thick * 0.8);
		float fill = morph_fill(p, radius * 0.85, sides, star, roundness,
		                        wobble * 0.4, t + fi * 4.0);

		vec3 ring_col = warm_palette(fi / 4.0 + t * 0.03 + 0.5);
		col += ring_col * outline * 0.05;
		col += ring_col * fill * 0.006;
	}

	// ── 4. SPIRAL TENDRILS — organic, breathing ─────────────────────
	{
		float r = length(uv_c);
		float a = atan(uv_c.y, uv_c.x);

		// Primary spiral (integer arms — seamless)
		float arms1 = floor(3.0 + bass * 2.0);
		float freq1 = 10.0 + energy * 8.0;
		float spiral1 = sin(a * arms1 + r * freq1 - t * 1.2);
		spiral1 = pow(max(spiral1, 0.0), 2.5);

		// Fade with distance — strongest at mid-range
		float fade1 = smoothstep(0.0, 0.1, r) * exp(-r * 2.0) * 0.2;

		vec3 spiral_col1 = teal_palette(t * 0.05) * spiral1 * fade1;
		col += spiral_col1 * 0.07;

		// Counter-spiral (different arm count)
		float arms2 = floor(5.0 + mid * 2.0);
		float freq2 = 8.0 + energy * 5.0;
		float spiral2 = sin(a * arms2 - r * freq2 * 0.6 + t * 0.9);
		spiral2 = pow(max(spiral2, 0.0), 3.0);

		float fade2 = smoothstep(0.0, 0.08, r) * exp(-r * 1.8) * 0.15;

		vec3 spiral_col2 = deep_palette(t * 0.04 + 0.3) * spiral2 * fade2;
		col += spiral_col2 * 0.06;

		// Tertiary: slow, wide, warm
		float arms3 = floor(2.0 + warmth * 3.0);
		float spiral3 = sin(a * arms3 + r * 5.0 - t * 0.6);
		spiral3 = pow(max(spiral3, 0.0), 4.0);
		float fade3 = exp(-r * 3.0) * 0.1;
		col += warm_palette(t * 0.03) * spiral3 * fade3 * 0.05;
	}

	// ── 5. BREATHING RINGS — concentric, pulsing ────────────────────
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float r = length(uv_c);

		// Ring radius expands with index, breathes with audio
		float ring_r = 0.04 + fi * 0.045
		             + sub_bass * 0.02
		             + sin(t * 0.6 + fi * 0.8) * 0.015;
		ring_r += kick_pulse * 0.5;

		// Slight elliptical deformation
		float a = atan(uv_c.y, uv_c.x);
		ring_r *= 1.0 + 0.04 * sin(a * 2.0 + t * 0.3 + fi);

		float ring = exp(-abs(r - ring_r) * 30.0);

		// Visibility oscillates per ring
		float vis = 0.4 + 0.6 * pow(sin(t * 0.4 + fi * 0.95) * 0.5 + 0.5, 2.0);
		ring *= vis;

		// Color shifts per ring
		float ct = fi / 7.0 + t * 0.025;
		vec3 ring_col = mix(deep_palette(ct), teal_palette(ct + 0.5), fi / 7.0);
		col += ring_col * ring * 0.03;
	}

	// ── 6. ORGANIC MOIRÉ GRID — deep colored, subtle ───────────────
	{
		float spacing = 0.14 + bass * 0.03;

		// Two overlapping warped grids
		vec2 p1 = uv_c * rot2(t * 0.04);
		// Add organic curvature to grid
		p1 += vec2(sin(p1.y * 5.0 + t * 0.3), cos(p1.x * 4.0 + t * 0.2)) * 0.01 * activity;
		vec2 q1 = mod(p1, spacing) - spacing * 0.5;
		float g1 = max(exp(-abs(q1.x) * 25.0), exp(-abs(q1.y) * 25.0));

		vec2 p2 = uv_c * rot2(-t * 0.03 + 0.5);
		p2 += vec2(cos(p2.y * 4.0 - t * 0.25), sin(p2.x * 5.0 + t * 0.15)) * 0.01 * activity;
		vec2 q2 = mod(p2, spacing * 1.08) - spacing * 0.54;
		float g2 = max(exp(-abs(q2.x) * 25.0), exp(-abs(q2.y) * 25.0));

		// Interference = product of the two grids
		float moire = g1 * g2;

		// Color the grid in deep teal, modulated by warmth
		vec3 moire_col = teal_palette(t * 0.06 + 0.6);
		moire_col = mix(moire_col, warm_palette(t * 0.04 + 0.1), warmth * 0.3);
		col += moire_col * moire * 0.025 * activity;
	}

	// ── 7. MORPHING FLOWER — polar shape that blooms ────────────────
	{
		float r = length(uv_c);
		float a = atan(uv_c.y, uv_c.x);

		// Petals: number morphs over time
		float petals = 4.0 + 3.0 * sin(t * 0.07) + 2.0 * sin(t * 0.11 + 1.0);
		float bloom = 0.5 + 0.3 * sin(t * 0.15) + energy * 0.2;

		// Flower radius modulated by petals
		float flower_r = 0.08 + energy * 0.05 + kick_pulse;
		flower_r *= 1.0 + bloom * cos(petals * a + t * 0.2);

		// Draw as ring
		float d = abs(r - flower_r);
		float glow = exp(-d * 30.0) + exp(-d * 8.0) * 0.3;  // outline + soft halo

		// Fill
		float fill = smoothstep(flower_r + 0.003, flower_r - 0.015, r);

		vec3 flower_col = deep_palette(t * 0.05 + 0.15);
		col += flower_col * glow * 0.045;
		col += flower_col * fill * 0.006;

		// Second bloom layer, smaller, counter-rotating
		float petals2 = 6.0 + 4.0 * sin(t * 0.09 + 2.0);
		float flower_r2 = 0.05 + energy * 0.03 + kick_pulse * 0.7;
		flower_r2 *= 1.0 + 0.3 * cos(petals2 * a - t * 0.15);

		float d2 = abs(r - flower_r2);
		float glow2 = exp(-d2 * 40.0);

		vec3 flower_col2 = teal_palette(t * 0.06 + 0.8);
		col += flower_col2 * glow2 * 0.04;
	}

	// ── Percussion accents ──────────────────────────────────────────
	vec3 kick_col = warm_palette(t * 0.08);
	col += kick_col * kick * 0.05;

	vec3 snare_col = teal_palette(t * 0.07 + 0.2);
	col += snare_col * snare * 0.04;

	vec3 hihat_col = deep_palette(t * 0.1 + 0.5);
	col += hihat_col * hihat * 0.025;

	// Onset: deep flash, not white
	col += deep_palette(t * 0.04) * onset * 0.06;

	// ── Beat-phase pulse ────────────────────────────────────────────
	float phase_pulse = pow(1.0 - abs(fract(beat_phase) - 0.5) * 2.0, 4.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.2;

	// ── Warmth / brightness color shift ─────────────────────────────
	// Warm music → push everything slightly warmer
	col.r += warmth * 0.012 * energy;
	col.g += brightness * 0.006 * energy;

	// ── COMPOSITE with feedback ─────────────────────────────────────
	vec3 final_col = trail + col;

	// Reinhard tonemap — keeps deep colors rich, prevents blowout
	final_col = final_col / (1.0 + final_col * 0.6);

	// Vignette: deep edges
	float vig = 1.0 - smoothstep(0.35, 1.05, length(uv - 0.5) * 1.5);
	final_col *= mix(0.5, 1.0, vig);

	COLOR = vec4(clamp(final_col, 0.0, 1.0), 1.0);
}
