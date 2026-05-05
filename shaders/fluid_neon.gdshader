shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Fluid Neon
//  @author:        Sabo Sugi (magooney rmx)
//  @website:       codepen.io/sabosugi/pen/XJjypjm
//  @description:   Harmonic vortex fluid IFS with neon ribbons and ACES tonemapping
//
//  Post-processing defaults
//  @exposure:       1.55
//  @tonemap_knee:   0.0
//  @gamma:          2.0
//  @vignette_dark:  0.25
//  @grain_strength: 0.01
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════

// ── Audio · all values 0–1, pushed every frame by AudioAnalyzer ─────
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
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float beat_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float kick_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float snare_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float hihat_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;
uniform int   frame           = 0;

// ── Feedback loop ────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.0;

// ── Utility ──────────────────────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Spectral rows ────────────────────────────────────────────────────
uniform float peak_00 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_01 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_02 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_03 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_04 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_05 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_06 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_07 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_08 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_09 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_10 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_11 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_12 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_13 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_14 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_15 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_16 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_17 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_18 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_19 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_20 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_21 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_22 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_23 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_24 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_25 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_26 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_27 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_28 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_29 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_30 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_31 : hint_range(0.0, 1.0) = 0.0;

// ── Constants ────────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helpers ──────────────────────────────────────────────────────────

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// IFS rotation — matches original's mat2(c, -s, s, c) convention
mat2 ifs_rot(float a) {
	float s = sin(a), c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

// ACES filmic tonemap (approximation)
vec3 aces(vec3 x) {
	return x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	vec2 res = rect_size;
	float aspect = res.x / res.y;
	vec2 p   = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 original_p = p;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — soft spiral with energy-driven decay
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// Gentle zoom — sub_bass breathing
	center *= 0.993 - sub_bass * 0.004;

	// Slow rotation — energy builds spiral
	center *= rot2(0.003 + energy * 0.005);

	vec2 fb_uv = center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;

	// Warp — bass drives amplitude
	vec2 warp = vec2(
		sin(center.y * 6.0 + t * 0.8) * 0.01,
		cos(center.x * 5.0 + t * 0.6) * 0.01
	);
	warp *= 1.0 + bass * 1.5 + energy * 0.8;

	vec2 sample_uv  = fb_uv + warp;
	vec2 edge_d     = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	float decay = mix(0.92, 0.84, energy);
	trail *= decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — harmonic vortex fluid IFS with neon ribbons
	// ══════════════════════════════════════════════════════════════════

	// Aspect-corrected coords at double range (matches original's gl_FragCoord calc)
	vec2 fp = p * 2.0;

	// Time — energy speeds up evolution
	float speed = 0.3 + energy * 0.2;
	float ft = t * speed * 0.5;

	// Initial cinematic tilt
	fp *= ifs_rot(0.2);

	// Audio-reactive parameters
	float iterations = 6.0 + activity * 6.0 + onset * 3.0;  // 6–15 folds
	float dens = 3.2535 + bass * 1.0;                        // bass thickens folds
	float intensity = 0.03758 + kick * 0.015;                 // kicks brighten neon

	// Neon colors — shift with warmth/brightness
	vec3 color1 = vec3(0.0, 0.33, 1.0);   // electric blue
	vec3 color2 = vec3(1.0, 0.0, 0.67);   // hot pink
	// Warmth shifts toward pink, brightness shifts toward cyan
	color1 = mix(color1, vec3(0.0, 0.8, 0.6), brightness * 0.4);
	color2 = mix(color2, vec3(1.0, 0.4, 0.1), warmth * 0.5);

	vec3 final_color = vec3(0.0);

	// ── IFS folding loop ─────────────────────────────────────────
	for (float i = 1.0; i <= 20.0; i += 1.0) {
		if (i > iterations) break;

		// Organic rotation per iteration
		fp *= ifs_rot(sin(ft * 0.05) * 0.1 + 0.08);

		// Harmonic vortex twist
		vec2 q = fp;
		float dist = length(fp);
		q *= ifs_rot(dist * dens * 0.25 - ft * 0.3);

		// Layer 1 folds — base frequency
		float freq = dens * 0.8;
		q.x += sin(q.y * freq + ft * 0.5 + i * 0.15) * 0.5;
		q.y += cos(q.x * freq - ft * 0.5 - i * 0.15) * 0.5;

		// Layer 2 ripples — double frequency, half amplitude
		vec2 r = q;
		r.x += sin(q.y * freq * 2.0 - ft * 0.8) * 0.25;
		r.y += cos(q.x * freq * 2.0 + ft * 0.8) * 0.25;

		// Synchronized ribbon wave
		float wave = sin(r.x * freq * 1.5 + ft) * 0.6
		           + cos(r.y * freq * 0.5 - ft * 0.7) * 0.4;

		// Distance to warped boundary
		float d = abs(r.y - wave);

		// Hard core glow + dual soft halos
		float core = 0.005 / max(d, 0.002);
		float soft1 = exp(-d * 8.0) * 0.6;
		float soft2 = exp(-d * 2.0) * 0.2;

		// Chromatic dispersion
		float mix_factor = sin(r.x * 3.0 + r.y * 2.0 + ft + i * 1.6) * 0.5 + 0.5;
		vec3 layer_color = mix(color1, color2, mix_factor);

		// Attenuation — deeper layers contribute less
		float atten = 1.0 / (i * 0.6 + 1.0);

		final_color += layer_color * (core + soft1 + soft2) * intensity * atten * 30.0;

		// Fractal zoom for next iteration
		fp = r * 1.05;
	}

	// ── Deep background tint ─────────────────────────────────────
	vec3 bg_color = vec3(0.02, 0.01, 0.04);
	final_color += bg_color * 0.5;

	// ── ACES filmic tonemap inside shader ────────────────────────
	final_color = aces(final_color);

	// ── Scale down for safe feedback equilibrium ─────────────────
	// ACES maps [0,∞) → [0,1], so max output is 1.0
	// × 0.12 keeps equilibrium safe with decay 0.92
	vec3 new_col = final_color * 0.12;

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + neon fluid, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════
	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
