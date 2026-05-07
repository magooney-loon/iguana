shader_type canvas_item;

//  @name:          Phosphorescence
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Neon soft-body tunnel with iridescent plasma fill and volumetric center rays
//
//  @exposure:       1.3
//  @tonemap_knee:   0.0
//  @gamma:          2.1
//  @vignette_dark:  0.40
//  @grain_strength: 0.015
//  @loop_reinhard:  1.0
// ═══════════════════════════════════════════════════════════════════════

// ── Audio engine · auto-driven by AudioAnalyzer ─────────────────────
//
// Frequency bands (0–1, smoothed each frame)
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;  //   20–60 Hz
uniform float bass        : hint_range(0.0, 1.0) = 0.0;  //   60–250 Hz
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;  //  250–800 Hz
uniform float mid         : hint_range(0.0, 1.0) = 0.0;  //  800 Hz–4 kHz
uniform float presence    : hint_range(0.0, 1.0) = 0.0;  //   4–8 kHz
uniform float treble      : hint_range(0.0, 1.0) = 0.0;  //   8–16 kHz
//
// Percussion envelopes (0–1, attack/decay shaped)
uniform float beat        : hint_range(0.0, 1.0) = 0.0;  // general beat pulse
uniform float kick        : hint_range(0.0, 1.0) = 0.0;  // low-frequency kick
uniform float snare       : hint_range(0.0, 1.0) = 0.0;  // mid-frequency snare
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;  // high-frequency hat
//
// Spectral flux / onset (0–1, rate of change per band)
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;  // bass band flux
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;  // mid band flux
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;  // treble band flux
uniform float onset       : hint_range(0.0, 1.0) = 0.0;  // weighted onset strength
//
// Global descriptors (0–1 unless noted)
uniform float energy      : hint_range(0.0, 1.0) = 0.0;  // RMS loudness
uniform float activity    : hint_range(0.0, 1.0) = 0.0;  // spectral activity
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;  // perceptual loudness
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;  // bass ↔ treble ratio
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;  // treble energy ratio
uniform float density     : hint_range(0.0, 1.0) = 0.0;  // spectral flatness
//
// Timing
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;  // 0–1 position in beat
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;  // tracker confidence
uniform float bpm             = 120.0;                          // estimated BPM
uniform float time_val        = 0.0;                             // elapsed seconds

// ── Feedback loop ───────────────────────────────────────────────────
// Previous frame's output — sample this (warped/zoomed/rotated) to
// create MilkDrop-style trails, tunnels, and infinite zoom effects.
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader tuning · configurable in Settings UI ─────────────────
// Reinhard tonemapping applied INSIDE the feedback loop.
// Higher = more compression (dimmer highlights, more detail retained).
// 0 = bypass.  Default is set per-shader in visualizer.gd.
uniform float loop_reinhard : hint_range(0.0, 3.0) = 1.0;

// ── Utility · auto-provided by visualizer.gd ────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);  // viewport resolution in pixels

// ── Constants ───────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Shader-specific helpers ─────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Cosine palette (Inigo Quilez) — mood-driven color
vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

// ── Organic field ────────────────────────────────────────────────────
float organic_field(vec3 p, float t_offset) {
	float d = 1e10;
	float t = t_offset;

	for (int i = 0; i < 5; i++) {
		float fi = float(i);

		float angle = fi * TAU * 0.4 + t * 0.12;
		float spread = 1.0 + bass * 0.4;
		vec3 center = vec3(
			cos(angle) * 1.1 * spread,
			sin(angle * 0.7 + fi * 0.5) * 0.7,
			fi * 2.0 - 4.0 + sin(t * 0.08 + fi * 0.9) * 0.6
		);

		float r = 0.45 + 0.12 * sin(t * 0.35 + fi * 0.8) + sub_bass * 0.1;
		vec3 rel = p - center;

		float s_sphere = length(rel) - r;

		vec3 bq = abs(rel) - vec3(r * 0.72);
		float s_box = length(max(bq, 0.0)) + min(max(bq.x, max(bq.y, bq.z)), 0.0);

		float s_oct = (abs(rel.x) + abs(rel.y) + abs(rel.z) - r * 0.92) / 1.73;

		vec2 tq = vec2(length(rel.xz) - r * 0.55, rel.y);
		float s_torus = length(tq) - r * 0.22;

		float cap_h = r * 0.7;
		vec3 cap_sw = rel;
		cap_sw.y -= clamp(cap_sw.y, -cap_h, cap_h);
		float s_capsule = length(cap_sw) - r * 0.5;

		vec3 d_rel = rel;
		d_rel.y *= 0.55;
		float s_diamond = (abs(d_rel.x) + abs(d_rel.y) + abs(d_rel.z) - r * 0.85) / 1.73;

		float shape;
		if (i == 0) {
			shape = mix(s_sphere, s_oct, brightness);
		} else if (i == 1) {
			shape = mix(s_box, s_sphere, warmth);
		} else if (i == 2) {
			shape = mix(s_torus, s_box, energy);
		} else if (i == 3) {
			shape = mix(s_sphere, s_capsule, bass);
		} else {
			shape = mix(s_sphere, s_diamond, treble * 0.8);
		}

		float disp = sin(p.x * 2.5 + t * 0.45 + fi)
		           * cos(p.y * 2.5 - t * 0.3 + fi * 0.7)
		           * sin(p.z * 2.0 + t * 0.35 + fi * 1.1);
		disp *= 0.1 + energy * 0.08;

		float blob = shape + disp;
		d = smin(d, blob, 0.45 + beat * 0.25);
	}

	return d;
}

// ── Abstract rings ───────────────────────────────────────────────────
float abstract_rings(vec3 p, float t_offset) {
	float d = 1e10;
	float t = t_offset;

	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec3 rp = p;

		rp -= vec3(
			sin(t * 0.15 + fi * 2.1) * 1.3,
			cos(t * 0.12 + fi * 1.7) * 0.8,
			cos(t * 0.1 + fi * 2.8) * 1.3
		);
		rp.xz *= rot(t * 0.2 + fi * 1.0);
		rp.yz *= rot(t * 0.15 + fi * 0.7);

		float ring_R = 0.45;
		float thickness = 0.018 + energy * 0.006;
		vec2 q = vec2(length(rp.xz) - ring_R, rp.y);

		float cross_section;
		if (i == 0) {
			cross_section = length(q) - thickness;
		} else if (i == 1) {
			float sq = max(abs(q.x), abs(q.y)) - thickness;
			float ci = length(q) - thickness;
			cross_section = mix(ci, sq, 0.7 - warmth * 0.4);
		} else {
			float a = atan(q.y, q.x);
			float lobe = sin(a * 3.0 + t * 0.25) * thickness * 0.5;
			cross_section = length(q) - thickness + lobe;
		}

		d = min(d, cross_section);
	}

	return d;
}

// ── Caustics ─────────────────────────────────────────────────────────
float caustics(vec2 uv, float t) {
	float c = 0.0;
	c += sin(uv.x * 10.0 + t * 1.4) * sin(uv.y * 8.0 + t * 1.1);
	c += sin(uv.x * 8.0 - t * 0.75 + 1.0) * sin(uv.y * 12.0 + t * 0.95);
	c += sin((uv.x + uv.y) * 6.0 + t * 0.5) * sin((uv.x - uv.y) * 7.0 - t * 0.65);
	return pow(max(c * 0.1, 0.0), 2.0);
}

// ── Interference fringes ─────────────────────────────────────────────
float interference(vec2 uv, float t) {
	vec2 src1 = vec2(0.35 + sin(t * 0.08) * 0.08, 0.5 + cos(t * 0.06) * 0.05);
	vec2 src2 = vec2(0.65 + cos(t * 0.07) * 0.08, 0.5 + sin(t * 0.05) * 0.05);
	float d1 = length(uv - src1);
	float d2 = length(uv - src2);
	float wave = sin(d1 * 50.0 - t * 2.5) + sin(d2 * 50.0 - t * 2.5);
	return pow(max(wave * 0.5 + 0.5, 0.0), 4.0) * 0.06;
}

// ── Lissajous curve trace ────────────────────────────────────────────
float lissajous(vec2 uv, float t) {
	float curve = 0.0;
	for (int i = 0; i < 25; i++) {
		float fi = float(i) * 0.15;
		float s = fi + t * 0.12;
		vec2 pt = vec2(
			0.5 + sin(3.0 * s + 0.7) * 0.28,
			0.5 + sin(2.0 * s) * 0.28
		);
		float d = length(uv - pt);
		curve += exp(-d * 280.0) * 0.01;
	}
	return curve;
}

void fragment() {
	vec2 uv = UV;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 1: FEEDBACK LOOP — MilkDrop warp / zoom / rotate
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= rect_size.x / rect_size.y;

	// Zoom: gentle for the meditative ocean vibe
	float zoom = 0.978 - sub_bass * 0.010 + onset * 0.006;
	center *= zoom;

	// Rotate: slow, hypnotic spiral
	float rot_a = 0.003 + energy * 0.005 + beat * 0.002;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	// Per-pixel warp — Cartesian only, aspect-corrected (no atan)
	vec2 warp = vec2(
		sin(center.y * 7.0 + t * 1.0) * 0.008,
		cos(center.x * 5.0 + t * 0.8) * 0.008
	);
	warp *= 1.0 + bass * 2.0 + energy * 1.2;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	// Chromatic aberration — underwater light dispersion
	float ca = 0.0010 + energy * 0.0010;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;

	// Decay
	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING CORE — organic blobs + abstract rings
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	vec3 ro = vec3(
		sin(t * 0.07) * 1.8 + sin(t * 0.03) * 0.6,
		cos(t * 0.05) * 1.0 + cos(t * 0.02) * 0.3,
		t * 1.5
	);
	vec3 ray = normalize(vec3(p, 1.5));

	float sway_xy = sin(t * 0.018) * 0.15 + sin(t * 0.006) * 0.06;
	float sway_yz = cos(t * 0.013) * 0.04 + sin(t * 0.004) * 0.02;
	ray.xy *= rot(sway_xy);
	ray.yz *= rot(sway_yz);

	float march_t = 0.0;
	float acc = 0.0;
	float acc_ring = 0.0;
	float acc_pulse = 0.0;

	float focal_dist = 4.5 + sin(t * 0.09) * 1.5;
	float glow_falloff = 4.0 + energy * 5.0 + beat * 3.0;

	int max_steps = 55 + int(density * 25.0);
	for (int i = 0; i < 80; i++) {
		if (i >= max_steps) break;

		vec3 raw_pos = ro + ray * march_t;

		vec3 cell_id = floor((raw_pos + 3.0) / 6.0);
		float ch  = fract(sin(dot(cell_id, vec3(127.1, 311.7, 74.7))) * 43758.5);
		float ch2 = fract(sin(dot(cell_id, vec3(269.5, 183.3, 41.1))) * 43758.5);
		float ch3 = fract(sin(dot(cell_id, vec3(53.8, 197.4, 311.2))) * 43758.5);

		vec3 pos = mod(raw_pos - 3.0, 6.0) - 3.0;

		pos.xz *= rot(ch * TAU);
		pos.yz *= rot(ch2 * PI);

		float cell_scale = 1.0 + (ch3 - 0.5) * 0.15 + sin(t * 0.1 + ch3 * 5.0) * 0.05;
		pos *= cell_scale;

		float t_cell = t + ch * 5.0;

		float breath = 1.0 + sin(t * 0.15) * 0.015 + sub_bass * 0.02;
		pos *= breath;

		float d_blobs = organic_field(pos, t_cell);
		float d_rings = abstract_rings(pos, t_cell);
		float d = smin(d_blobs, d_rings, 0.25);
		d = max(abs(d), 0.01);

		float dof = exp(-pow((march_t - focal_dist) * 0.12, 2.0));
		float glow = exp(-d * glow_falloff) * mix(0.25, 1.0, dof);
		acc += glow;

		float ring_glow = exp(-max(abs(d_rings), 0.01) * glow_falloff * 1.3)
		                * mix(0.3, 1.0, dof);
		acc_ring += ring_glow;

		float pulse = sin(march_t * 1.5 - t * 3.0 + beat_phase * TAU);
		pulse = pow(max(pulse, 0.0), 4.0);
		acc_pulse += glow * pulse;

		march_t += d * 0.5;
	}

	// ── Raymarching color — deep ocean bioluminescence ──
	float hue = beat_phase * TAU + t * 0.07;
	vec3 band_color = vec3(
		0.5 + 0.5 * sin(hue + 0.0),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	band_color.r = mix(band_color.r, 0.05 + mid * 0.35, (bass + sub_bass) * 0.5);
	band_color.g += low_mid * 0.25 + mid * 0.2;
	band_color.b += (treble + presence) * 0.35;

	vec3 warm_tint = vec3(1.0, 0.04 + sin(t * 0.3) * 0.04, 0.65);
	vec3 cool_tint = vec3(0.0, 0.85 + cos(t * 0.4) * 0.1, 0.85);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	vec3 rm_col = vec3(0.0);

	// Organic blob glow
	rm_col += mix(mood_tint, band_color, 0.4 + energy * 0.6) * acc * 0.004;

	// Abstract rings — neon magenta/hot pink
	rm_col += vec3(1.0, 0.05, 0.75) * acc_ring * 0.004;
	rm_col += vec3(0.7, 0.0, 1.0)   * acc_ring * kick * 0.003;

	// Phantom pulse — acid green / electric gold
	vec3 pulse_col = mix(vec3(0.1, 1.0, 0.3), vec3(1.0, 0.9, 0.0), warmth);
	rm_col += pulse_col * acc_pulse * 0.005;

	// Percussion strikes
	rm_col += vec3(0.2, 0.65, 1.0) * acc * kick  * 0.018;
	rm_col += vec3(1.0, 0.4, 0.9)  * acc * snare * 0.015;
	rm_col += vec3(0.2, 1.0, 0.45) * acc * hihat * 0.012;

	// Onset flash
	rm_col += vec3(0.0, 1.0, 0.9) * onset * 0.30;
	rm_col += vec3(1.0, 0.0, 0.5) * onset * onset * 0.18;

	// Beat-phase swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	rm_col *= 1.0 + phase_pulse * beat_confidence * 0.25;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 3: OVERLAY LAYERS
	// ══════════════════════════════════════════════════════════════════
	vec2 uv_c = uv - 0.5;
	uv_c.x *= rect_size.x / rect_size.y;
	float r = length(uv_c);
	float ang = atan(uv_c.y, uv_c.x);

	vec3 overlay = vec3(0.0);

	// ── 3a. Bioluminescent shockwave ring ─────────────────────────────
	// Expanding pressure wave on onset — like a deep-sea creature pulsing
	float shock_phase = fract(beat_phase);
	float shock_r = shock_phase * 0.5;
	float shock_w = 0.02 + (1.0 - shock_phase) * 0.025;
	float shock = exp(-pow((r - shock_r) / shock_w, 2.0)) * onset * 0.04;
	overlay += vec3(0.0, 1.0, 0.85) * shock;
	overlay += vec3(0.3, 0.0, 1.0)  * shock * kick * 1.2;

	// ── 3b. Abyssal whirlpool spiral ──────────────────────────────────
	// Integer arm count — no atan2 seam
	float arms = floor(6.0 + bass * 2.0);
	float spiral = sin(ang * arms + r * 12.0 - t * 2.5 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 3.0);
	spiral *= 0.010 * (0.3 + energy);
	spiral *= smoothstep(0.0, 0.12, r) * smoothstep(0.85, 0.2, r);
	overlay += vec3(0.0, 0.8, 1.0) * spiral * 1.2;
	overlay += vec3(0.5, 0.0, 1.0) * spiral * 0.6;

	// ── 3c. Kelp forest strands ───────────────────────────────────────
	// Vertical flowing ribbons — underwater plant motion
	float kelp = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float x_base = 0.08 + fi * 0.13 + sin(t * 0.02 + fi * 0.8) * 0.03;
		float wave = sin(uv.y * (2.0 + fi * 0.3) + t * (0.3 + fi * 0.05) + fi * 1.5) * (0.03 + fi * 0.008);
		float x = x_base + wave;
		float d = abs(uv.x - x);
		float strand = exp(-d * (300.0 + energy * 100.0)) * 0.007;
		strand *= smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.6, uv.y);
		kelp += strand;
	}
	kelp *= activity;
	overlay += vec3(0.0, 0.6, 0.3) * kelp * 2.0;
	overlay += vec3(0.1, 0.9, 0.4) * kelp * 0.8;

	// ── 3d. Photon sparkles — drifting point lights ───────────────────
	float sparkles = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		vec2 spos = vec2(
			fract(sin(fi * 127.1 + t * 0.01) * 43758.5),
			fract(cos(fi * 311.7 + t * 0.008) * 43758.5)
		);
		float sd = length(uv - spos);
		float twinkle = pow(sin(t * (1.5 + fi * 0.3) + fi * 2.7) * 0.5 + 0.5, 4.0);
		sparkles += exp(-sd * (400.0 + energy * 200.0)) * twinkle * 0.012;
	}
	sparkles *= activity;
	overlay += vec3(0.5, 0.9, 1.0) * sparkles * 1.5;
	overlay += vec3(0.2, 1.0, 0.7) * sparkles * 0.6;

	// ── 3e. Caustics ──────────────────────────────────────────────────
	float caust = caustics(uv * 3.0, t);
	overlay += vec3(0.0, 0.7, 1.0)  * caust * (0.15 + energy * 0.20);
	overlay += vec3(0.6, 0.0, 1.0)  * caust * warmth * 0.12;

	// ── 3f. Interference fringes ──────────────────────────────────────
	float fringes = interference(uv, t);
	overlay += vec3(0.0, 1.0, 0.9)  * fringes * (0.2 + energy * 0.25);
	overlay += vec3(1.0, 0.15, 0.8) * fringes * warmth * 0.2;

	// ── 3g. Lissajous curves (3:2 figure) ─────────────────────────────
	float liss = lissajous(uv, t);
	overlay += vec3(0.1, 0.5, 1.0) * liss * 0.8;
	overlay += vec3(1.0, 0.35, 0.2) * liss * warmth * 0.4;

	// ── 3h. Second Lissajous (5:4 figure) ─────────────────────────────
	float liss2 = 0.0;
	for (int i = 0; i < 25; i++) {
		float fi = float(i) * 0.14;
		float s = fi + t * 0.09 + 2.0;
		vec2 pt = vec2(
			0.5 + sin(5.0 * s + 1.2) * 0.22,
			0.5 + sin(4.0 * s + 0.3) * 0.22
		);
		float d = length(uv - pt);
		liss2 += exp(-d * 280.0) * 0.007;
	}
	overlay += vec3(0.9, 0.1, 1.0) * liss2 * 0.8;
	overlay += vec3(0.1, 1.0, 0.5) * liss2 * brightness * 0.4;

	// ── 3i. Bioluminescent plankton ───────────────────────────────────
	float plankton = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.06 + fi * 2.391) * 0.44,
			0.5 + cos(t * 0.05 + fi * 1.731) * 0.44
		);
		float d_p = length(uv - pos);
		float pulse = 0.3 + 0.7 * pow(sin(t * (0.2 + fi * 0.06) + fi * 0.9) * 0.5 + 0.5, 2.0);
		plankton += exp(-d_p * (80.0 + energy * 40.0)) * pulse * 0.018;
	}
	overlay += vec3(0.0, 0.75, 1.0) * plankton * 2.2;
	overlay += vec3(0.1, 1.0, 0.45) * plankton * 0.8;

	// ── 3j. Liquid mercury highlights ─────────────────────────────────
	float mercury = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(t * 0.025 + fi * 3.14) * 0.28,
			0.5 + cos(t * 0.02 + fi * 2.72) * 0.28
		);
		float mr = length(uv - mc);
		float mb = exp(-mr * mr * (30.0 + energy * 20.0));
		mercury += pow(max(mb, 0.0), 3.0);
	}
	overlay += vec3(0.35, 1.0, 0.9) * mercury * 0.15;

	// Cellular texture disabled — per-pixel broadband emission causes uniform fog
	// through the feedback loop (same reason as starfall).

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 4: COMPOSITE — trail + new geometry
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;

	// Deep ocean void background (very dim — feedback handles persistence)
	new_col += mix(vec3(0.0, 0.005, 0.03), vec3(0.0, 0.008, 0.025), uv.y) * 0.04;

	vec3 col = trail + new_col;
	col = col / (1.0 + col * loop_reinhard);

	COLOR = vec4(col, 1.0);
}
