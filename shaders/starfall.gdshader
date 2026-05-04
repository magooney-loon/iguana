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

float oct_box(vec3 pos, float scale) {
	pos *= scale;
	float base = sd_box(pos, vec3(0.4, 0.4, 0.1)) / 1.5;
	pos.xy *= 5.0;
	pos.y -= 3.5;
	pos.xy *= rot(0.75);
	return -base;
}

float box_set(vec3 pos, float g_time) {
	vec3 pos_origin = pos;

	float swing = 2.5 + bass * 2.0;
	float scale_mod = 1.5 + sub_bass * 1.2;
	float wobble = sin(g_time * 0.4) * swing;

	pos = pos_origin;
	pos.y += wobble;
	pos.xy *= rot(0.8 + snare * 0.3);
	float box1 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.y -= wobble;
	pos.xy *= rot(0.8 - snare * 0.2);
	float box2 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.x += wobble;
	pos.xy *= rot(0.8 + kick * 0.4);
	float box3 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.x -= wobble;
	pos.xy *= rot(0.8 - kick * 0.3);
	float box4 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.xy *= rot(0.8);
	float box5 = oct_box(pos, 0.5) * 6.0;

	pos = pos_origin;
	float box6 = oct_box(pos, 0.5) * 6.0;

	return max(max(max(max(max(box1, box2), box3), box4), box5), box6);
}

float map(vec3 pos, float g_time) {
	return box_set(pos, g_time);
}

// Cosine palette (Inigo Quilez) — mood-driven color
vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

void fragment() {
	vec2 uv = UV;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 1: FEEDBACK LOOP — MilkDrop warp / zoom / rotate
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= rect_size.x / rect_size.y;

	// Zoom: sub_bass breathes inward, onset punches
	float zoom = 0.975 - sub_bass * 0.012 + onset * 0.008;
	center *= zoom;

	// Rotate: energy + beat drive spiral rate
	float rot_a = 0.004 + energy * 0.006 + beat * 0.003;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	// Per-pixel warp — Cartesian only, aspect-corrected center (no atan)
	vec2 warp = vec2(
		sin(center.y * 8.0 + t * 1.2) * 0.010,
		cos(center.x * 6.0 + t * 0.9) * 0.010
	);
	warp *= 1.0 + bass * 2.0 + energy * 1.0;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	// Chromatic aberration on the feedback trail — RGB channels sample slightly apart
	float ca = 0.0008 + energy * 0.0008;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;

	// Decay: louder music sustains trails longer
	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING CORE
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	vec3 ro = vec3(0.0, -0.2, t * 4.0);
	vec3 ray = normalize(vec3(p, 1.5));

	float sway_xy = sin(t * 0.02) * 0.25 + sin(t * 0.007) * 0.1;
	float sway_yz = cos(t * 0.015) * 0.06 + sin(t * 0.005) * 0.04;
	ray.xy = ray.xy * rot(sway_xy);
	ray.yz = ray.yz * rot(sway_yz);

	float dist = 0.1;
	float ac = 0.0;
	float focal_dist = 5.0 + sin(t * 0.1) * 2.0;

	int steps = 60 + int(density * 39.0);
	for (int i = 0; i < 99; i++) {
		if (i >= steps) break;

		vec3 pos = ro + ray * dist;
		pos = mod(pos - 2.0, 4.0) - 2.0;
		float g_time = t - float(i) * 0.01;

		float d = map(pos, g_time);
		d = max(abs(d), 0.01);

		float glow_str = 23.0 + beat * 25.0 + onset * 15.0;
		float dof = exp(-pow((dist - focal_dist) * 0.12, 2.0));
		ac += exp(-d * glow_str) * mix(0.3, 1.0, dof);

		dist += d * (0.55 - beat * 0.03);
	}

	// ── Raymarching color ──
	float hue = beat_phase * TAU + t * 0.08;
	vec3 band_color = vec3(
		0.5 + 0.5 * sin(hue + 0.0),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	band_color.r = mix(band_color.r, 0.9 + sub_bass * 0.1, (bass + sub_bass) * 0.5);
	band_color.g = mix(band_color.g, mid * 0.7,             low_mid * 0.4);
	band_color.b = mix(band_color.b, 0.8 + treble * 0.2,   (treble + presence) * 0.5);

	vec3 warm_tint = vec3(0.65 + sin(t * 0.3) * 0.1, 0.0, 1.0);
	vec3 cool_tint = vec3(0.0, 0.75 + cos(t * 0.4) * 0.1, 1.0);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	float lum = ac * 0.018;
	vec3 rm_col = mix(vec3(0.0), band_color, min(lum * 3.0, 1.0)) * lum;
	rm_col += mood_tint * lum * (0.3 + energy * 0.5);

	// Percussion strikes
	rm_col += vec3(1.0, 0.42, 0.0) * ac * 0.012 * kick;
	rm_col += vec3(0.2, 1.0, 0.9) * ac * 0.009 * snare;
	rm_col += vec3(0.4, 1.0, 0.2) * ac * 0.006 * hihat;

	// Onset flash
	rm_col += vec3(0.1, 0.8, 1.0) * onset * 0.35;
	rm_col += vec3(1.0, 0.05, 0.7) * onset * onset * 0.20;

	// Beat-phase brightness pulse
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	rm_col *= 1.0 + phase_pulse * beat_confidence * 0.3;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 3: OVERLAY LAYERS
	// ══════════════════════════════════════════════════════════════════
	vec2 uv_c = uv - 0.5;
	uv_c.x *= rect_size.x / rect_size.y;
	float r = length(uv_c);
	float a = atan(uv_c.y, uv_c.x);

	vec3 overlay = vec3(0.0);

	// ── 3a. Sacred geometry mandala — seed of life ───────────────────
	// 7 circles: 1 center + 6 surrounding, plus outer containment rings.
	// Radius driven by energy + sub_bass for kick-breathing.
	float mandala = 0.0;
	float mr = 0.15 + energy * 0.05 + sub_bass * 0.03;

	// Center circle
	mandala += exp(-abs(r - mr) * (90.0 + bass * 40.0)) * 0.010;

	// 6 surrounding circles (integer count — no atan2 seam)
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.04;
		vec2 cp = vec2(cos(angle), sin(angle)) * mr;
		float d = abs(length(uv_c - cp) - mr);
		mandala += exp(-d * (90.0 + bass * 40.0)) * 0.010;
	}

	// Outer containment ring (2× radius)
	mandala += exp(-abs(r - mr * 2.0) * (50.0 + energy * 25.0)) * 0.006;

	// Third ring (3× radius) — faint expansion
	mandala += exp(-abs(r - mr * 3.0) * (30.0 + energy * 15.0)) * 0.003;

	vec3 mandala_col = palette(a / TAU + t * 0.02,
		vec3(warmth * 0.15, 0.33, 0.67 + brightness * 0.15));
	overlay += mandala_col * mandala * (0.8 + beat_confidence * 0.5);

	// ── 3b. Aurora borealis curtains ─────────────────────────────────
	float aurora = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float y_base = 0.25 + fi * 0.10;
		float wave = sin(uv.x * (2.5 + fi * 0.7) + t * (0.12 + fi * 0.025) + fi * 1.7) * 0.07;
		wave += cos(uv.x * (4.0 + fi * 1.1) - t * 0.08 + fi * 2.3) * 0.035;
		float y = y_base + wave;
		float d = abs(uv.y - y);
		float band = exp(-d * (35.0 + energy * 20.0)) * (0.008 + energy * 0.004);
		band *= smoothstep(0.0, 0.2, r) * smoothstep(0.9, 0.3, r);
		aurora += band;
	}
	overlay += vec3(0.1, 0.7, 0.3) * aurora * 1.5;
	overlay += vec3(0.25, 0.05, 0.7) * aurora * sin(t * 0.25 + uv.x * 2.0) * 0.8;

	// ── 3c. Onset shockwave ring ─────────────────────────────────────
	// Expands outward with beat_phase, triggered by onset strength
	float shock_phase = fract(beat_phase);
	float shock_r = shock_phase * 0.55;
	float shock_w = 0.02 + (1.0 - shock_phase) * 0.03;
	float shock = exp(-pow((r - shock_r) / shock_w, 2.0)) * onset * 0.05;
	overlay += vec3(0.15, 0.85, 1.0) * shock;
	overlay += vec3(1.0, 0.3, 0.1) * shock * kick * 1.5;

	// ── 3d. Energy tendrils — noise-based branching ──────────────────
	float tendrils = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.02;
		vec2 dir = vec2(cos(angle), sin(angle));
		float proj = dot(uv_c, dir);
		float perp = length(uv_c - dir * max(proj, 0.0));
		float noise = texture(noise_tex, vec2(proj * 2.5 + t * 0.08 + fi * 0.5, fi * 0.37)).r;
		float branch = exp(-perp * (25.0 + noise * 35.0)) * noise * 0.012;
		branch *= smoothstep(0.0, 0.08, proj) * smoothstep(0.7, 0.1, proj);
		tendrils += branch;
	}
	tendrils *= (0.5 + energy * 1.5) * activity;
	overlay += vec3(0.3, 0.6, 1.0) * tendrils * 1.0;
	overlay += vec3(1.0, 0.2, 0.5) * tendrils * 0.5;

	// ── 3e. Bioluminescent plankton ──────────────────────────────────
	float plankton = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.07 + fi * 2.391) * 0.42 + cos(t * 0.05 + fi * 0.7) * 0.08,
			0.5 + cos(t * 0.06 + fi * 1.731) * 0.42 + sin(t * 0.04 + fi * 1.1) * 0.08
		);
		float d_p = length(uv - pos);
		float pulse = 0.3 + 0.7 * pow(sin(t * (0.25 + fi * 0.07) + fi * 0.9) * 0.5 + 0.5, 2.0);
		plankton += exp(-d_p * (90.0 + energy * 50.0)) * pulse * 0.025;
	}
	overlay += vec3(0.0, 0.5, 1.0) * plankton * 2.0;
	overlay += vec3(0.0, 1.0, 0.55) * plankton * 0.7;

	// ── 3f. Flowing silk ribbons ─────────────────────────────────────
	float silk = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float phase = fi * 1.618 + t * (0.06 + fi * 0.015);
		float y = 0.5
			+ sin(uv.x * (2.0 + fi * 0.7) + phase) * (0.06 + fi * 0.015)
			+ cos(uv.x * (3.5 + fi * 0.4) - phase * 0.6) * 0.03;
		float s_d = abs(uv.y - y);
		silk += exp(-s_d * (220.0 + energy * 100.0)) * (0.006 + energy * 0.003);
	}
	overlay += vec3(1.0, 0.05, 0.85) * silk * 2.0;
	overlay += vec3(0.45, 0.0, 1.0) * silk * 1.0;

	// ── 3g. Organic cellular texture ─────────────────────────────────
	float n1 = texture(noise_tex, uv * 4.0 + t * 0.03).r;
	float n2 = texture(noise_tex, uv * 8.0 - t * 0.02 + 3.7).r;
	float cellular = abs(n1 - n2) * 0.10;
	overlay += vec3(0.0, 0.9, 0.8) * cellular * (0.4 + energy * 0.8);

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 4: COMPOSITE — trail + new geometry
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;

	// Subtle deep-space background (very dim — feedback handles persistence now)
	new_col += mix(vec3(0.0, 0.0, 0.02), vec3(0.0, 0.003, 0.04), uv.y);

	vec3 col = trail + new_col;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 5: POST-PROCESSING (mild — lives inside the feedback loop)
	// ══════════════════════════════════════════════════════════════════
	// Reinhard with soft knee — prevents runaway without flattening color
	col = col / (1.0 + col * 0.35);

	// Mild gamma lift (0.93 not 0.4545 — heavy gamma in feedback causes drift)
	col = pow(max(col, vec3(0.0)), vec3(0.93));

	// Vignette — safe in feedback, only darkens edges
	col *= mix(0.35, 1.0, 1.0 - smoothstep(0.25, 1.3, length(uv - 0.5) * 1.8));

	// Film grain — tiny dither prevents banding in feedback accumulation
	col += (texture(noise_tex, uv * 300.0 + fract(t * 0.07)).r - 0.5) * 0.012;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
