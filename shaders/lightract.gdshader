shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Lightract
//  @author:        Sabo Sugi (magooney rmx)
//  @website:       codepen.io/sabosugi/full/WbGaBma
//  @description:   Raymarched sine-iteration fractal with space distortion and tanh tonemapping
//
//  Post-processing defaults
//  @exposure:       1.6
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  1.00
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

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

// Interleaved Gradient Noise — structured film-like grain
float ign(vec2 p) {
	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	return fract(magic.z * fract(dot(p, magic.xy)));
}

// Safe tanh — clamp input to prevent exp() overflow / NaN
vec3 safe_tanh(vec3 x) {
	vec3 cx = clamp(x, -10.0, 10.0);
	vec3 e2x = exp(2.0 * cx);
	return (e2x - 1.0) / (e2x + 1.0);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	vec2 res = rect_size;
	vec2 p   = (uv - 0.5) * vec2(res.x / res.y, 1.0);
	float aspect = res.x / res.y;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — gentle drift, no tunnel
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// Slow breathing zoom synced to sub_bass
	center *= 0.995 - sub_bass * 0.003;

	// Micro-rotation from snare
	center *= rot2(0.002 * snare);

	vec2 fb_uv = center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;

	// Gentle sine warp
	vec2 warp = vec2(
		sin(center.y * 5.0 + t * 0.7) * 0.008,
		cos(center.x * 4.0 + t * 0.5) * 0.008
	);
	warp *= 1.0 + bass * 1.0;

	vec2 sample_uv  = fb_uv + warp;
	vec2 edge_d     = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	float decay = mix(0.92, 0.85, energy);
	trail *= decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — raymarched sine-iteration fractal
	// ══════════════════════════════════════════════════════════════════

	// Pixel coordinates centered and aspect-corrected (equivalent to gl_FragCoord calc)
	vec2 frag = p * 2.0;

	// Time scale — energy makes it evolve faster
	float time_scale = 0.29 + energy * 0.15;
	float ft = t * time_scale;

	// Camera sway — offset UV over time, snare adds jitter
	frag += vec2(cos(ft * 2.0) * 0.15, cos(ft) * 0.13);
	frag += vec2(snare * 0.04, hihat * 0.03);

	// Ray direction
	vec3 ray_dir = normalize(vec3(frag, 0.7));

	// IGN dither — cinematic 24fps frame snapping
	float dither_frame = floor(t * 24.0);
	vec2 noise_off = vec2(dither_frame * 127.1, dither_frame * 311.7);
	float dither_noise = ign(uv * res + noise_off);

	// Raymarch parameters
	int ray_steps = 28 + int(energy * 8.0);  // 28–36 steps
	float fractal_iters = 8.0 + bass * 6.0;  // 8–14 iterations
	float fractal_amp = 0.114 + kick * 0.04; // bass pulse expands the fractal

	// Initialize raymarch
	float total_dist = (dither_noise - 0.5) * 0.09;
	vec3 accum = vec3(0.0);

	// Color frequency & phase — audio shifts the palette
	vec3 color_freq = vec3(1.35, 0.688, 1.72);
	color_freq += vec3(warmth * 0.3, activity * 0.15, brightness * 0.3);

	vec3 color_phase = vec3(5.28, 7.49, 3.56);
	color_phase += vec3(flux_bass * 0.8, flux_mid * 0.5, flux_treble * 0.8);

	// ── Raymarching loop ─────────────────────────────────────────
	for (int i = 0; i < 40; i++) {
		if (i >= ray_steps) break;

		vec3 pos = ray_dir * total_dist;

		// Z-axis space distortion
		pos.z = cos(pos.z * (sin(pos.x + ft * 0.7) + 1.5));

		// Fractal sine iteration
		for (float s = 3.0; s < 20.0; s += 1.0) {
			if (s >= fractal_iters) break;
			vec3 phase = 2.6 * ft + pos.yzx * s;
			pos = pos * 1.05 + sin(phase) * fractal_amp;
		}

		// Distance field
		float step_size = 0.01 + 0.1 * abs(length(pos) - 0.8);
		total_dist += step_size;

		// Color accumulation
		vec3 color_base = sin(pos * color_freq - color_phase);
		accum += color_base / step_size;
	}

	// ── Tonemap — safe tanh on squared accumulation ──────────────
	// Scale output low for safe feedback equilibrium
	vec3 new_col = safe_tanh((accum * accum) / 1200000.0) * 0.12;

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + fractal, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════
	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
