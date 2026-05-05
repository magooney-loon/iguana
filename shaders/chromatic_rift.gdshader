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

// ── Feedback ─────────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Utility ──────────────────────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helper functions ─────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Cosine palette (Inigo Quilez)
vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

// ── Rift SDF — IFS-folded octagonal geometry ─────────────────────────
// Afterimage's iterative fold applied before starfall's octagonal eval.
// 3-fold IFS creates organic morphing; octagonal output gives the
// distinctive starfall interior glow.
float rift_shape(vec3 pos, float g_time) {
	vec3 q = pos;

	// IFS fold — 3 iterations (lighter than afterimage's 5)
	float swing = 2.0 + bass * 1.5;
	float wobble = sin(g_time * 0.35) * swing;
	q.y += wobble;
	q.xy *= rot(0.7 + snare * 0.25);

	for (int i = 0; i < 3; i++) {
		q = abs(q) - 0.9;
		q.xy *= rot(g_time * 0.25);
		q.xz *= rot(g_time * 0.1);
	}
	q.xz *= rot(g_time);

	// Audio-reactive scale
	float scale = 1.8 + sub_bass * 0.8;
	q *= scale;

	// Octagonal box evaluation (starfall interior trick)
	float base = sd_box(q, vec3(0.4, 0.4, 0.1)) / 1.5;
	q.xy *= 5.0;
	q.y -= 3.5;
	q.xy *= rot(0.75);
	return -base;
}

float map(vec3 p, float g_time) {
	// Grid repetition (starfall spacing)
	vec3 q = p;
	q = mod(q - 2.0, 4.0) - 2.0;
	return rift_shape(q, g_time);
}

void fragment() {
	vec2 uv = UV;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 1: FEEDBACK LOOP
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= rect_size.x / rect_size.y;

	float zoom = 0.973 - sub_bass * 0.012 + onset * 0.008;
	center *= zoom;

	float rot_a = 0.004 + energy * 0.006 + beat * 0.003;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	vec2 warp = vec2(
		sin(center.y * 9.0 + t * 1.3) * 0.011,
		cos(center.x * 7.0 + t * 1.0) * 0.011
	);
	warp *= 1.0 + bass * 2.2 + energy * 1.2;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	float ca = 0.0010 + energy * 0.0010;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;

	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING — IFS-rift with phantom pulse
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	// Wandering camera (starfall style)
	vec3 ro = vec3(0.0, -0.2, t * 4.0);
	vec3 ray = normalize(vec3(p, 1.5));

	float sway_xy = sin(t * 0.02) * 0.25 + sin(t * 0.007) * 0.1;
	float sway_yz = cos(t * 0.015) * 0.06 + sin(t * 0.005) * 0.04;
	ray.xy = ray.xy * rot(sway_xy);
	ray.yz = ray.yz * rot(sway_yz);

	float march_t = 0.1;
	float acc = 0.0;
	float acc_phantom = 0.0;

	float focal_dist = 5.0 + sin(t * 0.1) * 2.0;
	float glow_falloff = 20.0 + beat * 20.0 + onset * 12.0;

	int steps = 60 + int(density * 35.0);
	for (int i = 0; i < 90; i++) {
		if (i >= steps) break;

		vec3 pos = ro + ray * march_t;
		float g_time = t - float(i) * 0.01;

		float d = map(pos, g_time);
		d = max(abs(d), 0.01);

		float dof = exp(-pow((march_t - focal_dist) * 0.12, 2.0));
		float glow = exp(-d * glow_falloff) * mix(0.3, 1.0, dof);
		acc += glow;

		// Phantom pulse (afterimage style) — beat-synced glow wave
		float phantom_phase = mod(length(pos) + 20.0 * t, 28.0);
		if (phantom_phase < 3.0) {
			acc_phantom += glow;
		}

		march_t += d * (0.55 - beat * 0.03);
	}

	// ── Raymarching color — chromatic rift palette ──
	// Bridges starfall's cosmic tones with afterimage's acid chrome
	float hue = beat_phase * TAU + t * 0.07;
	vec3 band_color = vec3(
		0.5 + 0.5 * sin(hue + 0.0),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	band_color.r = mix(band_color.r, 0.85 + sub_bass * 0.15, (bass + sub_bass) * 0.45);
	band_color.g = mix(band_color.g, mid * 0.6, low_mid * 0.35);
	band_color.b = mix(band_color.b, 0.8 + treble * 0.2, (treble + presence) * 0.4);

	// Mood: cosmic indigo (cool) ↔ acid gold (warm)
	vec3 warm_tint = vec3(0.85, 0.7, 0.0);
	vec3 cool_tint = vec3(0.1, 0.2, 0.9);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	float lum = acc * 0.005;
	float phantom_lum = acc_phantom * 0.008;

	vec3 rm_col = mix(mood_tint, band_color, 0.4 + energy * 0.5) * lum;
	rm_col += mood_tint * lum * (0.10 + energy * 0.15);

	// Phantom glow — acid green / electric gold (afterimage character)
	rm_col += vec3(0.05, 0.9, 0.2) * phantom_lum * (0.8 + energy * 0.5);
	rm_col += vec3(0.9, 0.85, 0.0) * phantom_lum * warmth * 0.4;

	// Percussion strikes — distinct per drum
	rm_col += vec3(1.0, 0.4, 0.0)  * acc * 0.014 * kick;
	rm_col += vec3(1.0, 0.0, 0.7)  * acc * 0.012 * snare;
	rm_col += vec3(0.3, 1.0, 0.4)  * acc * 0.008 * hihat;

	// Onset flash
	rm_col += vec3(0.1, 0.7, 1.0) * onset * 0.30;
	rm_col += vec3(1.0, 0.05, 0.65) * onset * onset * 0.18;

	// Beat-phase pulse
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	rm_col *= 1.0 + phase_pulse * beat_confidence * 0.28;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 3: OVERLAY LAYERS
	// ══════════════════════════════════════════════════════════════════
	vec2 uv_c = uv - 0.5;
	uv_c.x *= rect_size.x / rect_size.y;
	float r = length(uv_c);
	float ang = atan(uv_c.y, uv_c.x);

	vec3 overlay = vec3(0.0);

	// ── 3a. Fractal lightning arcs (afterimage, cosmic colors) ────────
	float lightning = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float angle = fi * TAU / 5.0 + t * 0.03;
		vec2 dir = vec2(cos(angle), sin(angle));
		float proj = dot(uv_c, dir);
		float perp = abs(length(uv_c - dir * max(proj, 0.0)));
		float noise = texture(noise_tex, vec2(proj * 8.0 + t * 0.5 + fi * 0.7, fi * 0.5)).r;
		perp += (noise - 0.5) * 0.032;
		float bolt = exp(-perp * (180.0 + energy * 80.0)) * 0.016;
		bolt *= smoothstep(0.0, 0.05, proj) * smoothstep(0.55, 0.05, proj);
		lightning += bolt;
	}
	lightning *= (0.4 + energy * 1.8) * activity;
	overlay += vec3(0.2, 0.7, 1.0) * lightning * 1.0;
	overlay += vec3(1.0, 0.7, 0.1) * lightning * kick * 0.6;

	// ── 3b. Sacred geometry hex rings (starfall variant) ──────────────
	float hex_r = 0.14 + energy * 0.04 + sub_bass * 0.025;
	float hex_outlines = 0.0;

	// 6 circles at hexagonal vertices
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.04;
		vec2 cp = vec2(cos(angle), sin(angle)) * hex_r;
		float d = abs(length(uv_c - cp) - hex_r);
		hex_outlines += exp(-d * (90.0 + bass * 40.0)) * 0.008;
	}
	// Center circle
	hex_outlines += exp(-abs(r - hex_r) * (90.0 + bass * 40.0)) * 0.008;
	// Outer ring
	hex_outlines += exp(-abs(r - hex_r * 2.2) * (45.0 + energy * 20.0)) * 0.005;

	vec3 hex_col = palette(ang / TAU + t * 0.02,
		vec3(warmth * 0.15, 0.33, 0.67 + brightness * 0.15));
	overlay += hex_col * hex_outlines * (0.7 + beat_confidence * 0.5);

	// ── 3c. Spiral vortex arms (afterimage, rift colors) ──────────────
	float arms = floor(5.0 + bass * 3.0);
	float spiral = sin(ang * arms + r * 14.0 - t * 2.8 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 3.0);
	spiral *= 0.012 * (0.3 + energy);
	spiral *= smoothstep(0.0, 0.1, r) * smoothstep(0.8, 0.15, r);
	overlay += vec3(0.0, 0.8, 1.0) * spiral * 1.3;
	overlay += vec3(1.0, 0.15, 0.65) * spiral * 0.7;

	// ── 3d. Bioluminescent plankton (starfall, warmer tones) ──────────
	float plankton = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.06 + fi * 2.391) * 0.42 + cos(t * 0.04 + fi * 0.7) * 0.07,
			0.5 + cos(t * 0.05 + fi * 1.731) * 0.42 + sin(t * 0.035 + fi * 1.1) * 0.07
		);
		float d_p = length(uv - pos);
		float pulse = 0.3 + 0.7 * pow(sin(t * (0.22 + fi * 0.06) + fi * 0.9) * 0.5 + 0.5, 2.0);
		plankton += exp(-d_p * (85.0 + energy * 45.0)) * pulse * 0.020;
	}
	overlay += vec3(0.0, 0.45, 1.0) * plankton * 2.0;
	overlay += vec3(0.9, 0.1, 0.55) * plankton * 0.7;

	// ── 3e. Neon scan lines (afterimage, rift-tinted) ─────────────────
	float scan = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float y = 0.3 + fi * 0.2 + sin(t * (0.1 + fi * 0.05)) * 0.045;
		float d = abs(uv.y - y);
		scan += exp(-d * (260.0 + energy * 110.0)) * 0.005;
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float x = 0.35 + fi * 0.3 + cos(t * (0.08 + fi * 0.04)) * 0.04;
		float d = abs(uv.x - x);
		scan += exp(-d * (260.0 + energy * 110.0)) * 0.004;
	}
	scan *= activity;
	overlay += vec3(0.0, 0.7, 1.0) * scan * 1.3;
	overlay += vec3(0.7, 0.0, 1.0) * scan * 0.5;

	// ── 3f. Noise nebula — drifting localized clouds (UNIQUE) ──────────
	// Patches of noise create a nebula atmosphere without broad fog.
	// pow(n, 2) localizes intensity; smoothstep contains the patch.
	float nebula = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 neb_pos = vec2(
			0.5 + sin(t * 0.03 + fi * 2.7) * 0.35,
			0.5 + cos(t * 0.025 + fi * 1.9) * 0.35
		);
		vec2 neb_uv = (uv - neb_pos) * (3.0 + fi * 0.5);
		float n = texture(noise_tex, neb_uv + t * 0.01 + fi * 0.7).r;
		float cloud = pow(n, 2.0) * 0.015;
		cloud *= smoothstep(0.45, 0.0, length(uv - neb_pos));
		nebula += cloud;
	}
	nebula *= 0.2 + energy * 0.4;
	overlay += palette(t * 0.03, vec3(0.1 + warmth * 0.2, 0.4, 0.6)) * nebula * 0.6;
	overlay += vec3(0.05, 0.6, 0.9) * nebula * 0.3;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 4: COMPOSITE
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;
	new_col += mix(vec3(0.0, 0.0, 0.015), vec3(0.0, 0.003, 0.03), uv.y);

	vec3 col = trail + new_col;
	col = col / (1.0 + col);   // Reinhard inside loop — prevents white saturation

	COLOR = vec4(col, 1.0);
}
