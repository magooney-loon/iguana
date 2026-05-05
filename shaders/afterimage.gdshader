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

// ── Helper functions ─────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec2 pmod(vec2 p, float r) {
	float a = atan(p.x, p.y) + PI / r;
	float n = TAU / r;
	a = floor(a / n) * n;
	return p * rot(-a);
}

float box_sdf(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

// IFS folded box – rotations are pure time for smooth morphing
float ifs_box(vec3 p) {
	for (int i = 0; i < 5; i++) {
		p = abs(p) - 1.0;
		p.xy *= rot(time_val * 0.3);
		p.xz *= rot(time_val * 0.1);
	}
	p.xz *= rot(time_val);
	return box_sdf(p, vec3(0.4, 0.8, 0.3));
}

float map(vec3 p) {
	vec3 p1 = p;
	p1.x = mod(p1.x - 5.0, 10.0) - 5.0;
	p1.y = mod(p1.y - 5.0, 10.0) - 5.0;
	p1.z = mod(p1.z, 16.0) - 8.0;
	p1.xy = pmod(p1.xy, 5.0);
	return ifs_box(p1);
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

	// Zoom: sub_bass breathes inward, onset punches — slightly more aggressive than starfall
	float zoom = 0.970 - sub_bass * 0.014 + onset * 0.010;
	center *= zoom;

	// Rotate: energy + beat drive spiral — acid vibe wants faster spin
	float rot_a = 0.005 + energy * 0.007 + beat * 0.004;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	// Per-pixel warp — Cartesian only, aspect-corrected (no atan)
	// Higher frequency + amplitude for the acid chrome aesthetic
	vec2 warp = vec2(
		sin(center.y * 10.0 + t * 1.4) * 0.012,
		cos(center.x * 8.0  + t * 1.1) * 0.012
	);
	warp *= 1.0 + bass * 2.5 + energy * 1.5;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	// Chromatic aberration — stronger RGB split for the acid aesthetic
	float ca = 0.0012 + energy * 0.0012;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;

	// Decay: louder music sustains trails
	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING CORE — IFS phantom
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	vec3 c_pos = vec3(0.0, 0.0, -3.0 * t);
	vec3 c_dir = normalize(vec3(0.0, 0.0, -1.0));
	vec3 c_up = vec3(sin(t), 1.0, 0.0);
	vec3 c_side = cross(c_dir, c_up);
	vec3 ray = normalize(c_side * p.x + c_up * p.y + c_dir);

	float acc = 0.0;
	float acc2 = 0.0;
	float march_t = 0.0;

	float focal_dist = 4.0 + sin(t * 0.08) * 1.5;
	float glow_falloff = 3.0 + energy * 4.0;

	for (int i = 0; i < 99; i++) {
		vec3 pos = c_pos + ray * march_t;
		float dist = map(pos);
		dist = max(abs(dist), 0.02);

		float dof = exp(-pow((march_t - focal_dist) * 0.15, 2.0));
		float a = exp(-dist * glow_falloff) * mix(0.35, 1.0, dof);

		// Phantom pulse – synced to beat_phase
		float phantom_phase = mod(length(pos) + 24.0 * t, 30.0);
		if (phantom_phase < 3.0) {
			a *= 2.0;
			acc2 += a;
		}

		acc += a;
		march_t += dist * 0.5;
	}

	// ── Raymarching color — acid chrome palette ──
	float lum  = acc  * 0.016;
	float ghost = acc2 * 0.026;

	vec3 rm_col = vec3(
		lum * (0.25 + bass * 0.9  + kick * 1.4),
		lum * (0.04 + mid  * 0.35) + ghost * (0.0 + energy * 0.6),
		lum * (0.75 + treble * 0.7) + ghost * 0.15
	);

	// Phantom pulses → vivid acid green / gold
	rm_col += vec3(0.05, 1.0, 0.2) * ghost * (0.9 + energy * 0.7);
	rm_col += vec3(0.9, 1.0, 0.0) * ghost * warmth * 0.5;

	// Hue rotation layered over IFS glow
	float hue = beat_phase * TAU + t * 0.06;
	vec3 hue_col = vec3(
		0.5 + 0.5 * sin(hue),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	rm_col += hue_col * lum * (0.4 + energy * 0.5);

	// Percussion: sharp, distinct hue per drum
	rm_col += vec3(1.0, 0.4, 0.0)  * acc  * 0.014 * kick;
	rm_col += vec3(1.0, 0.0, 0.75) * acc2 * 0.016 * snare;
	rm_col += vec3(0.4, 1.0, 0.0)  * acc  * 0.008 * hihat;

	// Onset flash
	rm_col += vec3(1.0, 0.0, 0.65) * onset * 0.35;
	rm_col += vec3(0.15, 0.0, 0.9) * onset * onset * 0.20;

	// Beat-phase brightness swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	rm_col *= 1.0 + phase_pulse * beat_confidence * 0.3;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 3: OVERLAY LAYERS
	// ══════════════════════════════════════════════════════════════════
	vec2 uv_c = uv - 0.5;
	uv_c.x *= rect_size.x / rect_size.y;
	float r = length(uv_c);
	float ang = atan(uv_c.y, uv_c.x);

	vec3 overlay = vec3(0.0);

	// ── 3a. Fractal lightning arcs ────────────────────────────────────
	// Noise-jagged electric bolts radiating from center
	float lightning = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float angle = fi * TAU / 5.0 + t * 0.03;
		vec2 dir = vec2(cos(angle), sin(angle));
		float proj = dot(uv_c, dir);
		float perp = abs(length(uv_c - dir * max(proj, 0.0)));
		// Jagged offset from noise makes the bolt zigzag
		float jagged = texture(noise_tex, vec2(proj * 8.0 + t * 0.5 + fi * 0.7, fi * 0.5)).r;
		perp += (jagged - 0.5) * 0.035;
		float bolt = exp(-perp * (180.0 + energy * 80.0)) * 0.018;
		bolt *= smoothstep(0.0, 0.05, proj) * smoothstep(0.55, 0.05, proj);
		lightning += bolt;
	}
	lightning *= (0.4 + energy * 2.0) * activity;
	overlay += vec3(0.3, 0.9, 1.0) * lightning * 1.2;
	overlay += vec3(1.0, 0.8, 0.1) * lightning * kick * 0.8;

	// ── 3b. Pulsing breathing rings ───────────────────────────────────
	// Concentric rings that breathe with kick/sub_bass
	float rings = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ring_r = 0.08 + fi * 0.08 + energy * 0.03 + sub_bass * 0.02;
		float ring = exp(-abs(r - ring_r) * (80.0 + bass * 40.0)) * 0.010;
		// Modulate ring brightness with angle for visual interest
		ring *= 0.7 + 0.3 * sin(ang * 3.0 + fi * 1.5 + t * 0.2);
		rings += ring;
	}
	vec3 ring_col = palette(r * 2.0 + t * 0.03,
		vec3(0.1 + warmth * 0.2, 0.5, 0.7 + brightness * 0.1));
	overlay += ring_col * rings * (0.6 + beat_confidence * 0.6);

	// ── 3c. Spiral vortex arms ────────────────────────────────────────
	// Integer arm count — no atan2 seam
	float arms = floor(5.0 + bass * 3.0);
	float spiral = sin(ang * arms + r * 15.0 - t * 3.0 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 4.0);
	spiral *= 0.012 * (0.3 + energy);
	// Fade at center and edges
	spiral *= smoothstep(0.0, 0.1, r) * smoothstep(0.8, 0.15, r);
	overlay += vec3(0.0, 1.0, 0.4) * spiral * 1.5;
	overlay += vec3(1.0, 0.0, 0.7) * spiral * 0.8;

	// ── 3d. Neon scan lines ───────────────────────────────────────────
	// Horizontal + vertical lines that drift slowly
	float scan = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float y = 0.3 + fi * 0.2 + sin(t * (0.1 + fi * 0.05)) * 0.05;
		float d = abs(uv.y - y);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.006;
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float x = 0.35 + fi * 0.3 + cos(t * (0.08 + fi * 0.04)) * 0.05;
		float d = abs(uv.x - x);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.005;
	}
	scan *= activity;
	overlay += vec3(0.0, 0.8, 1.0) * scan * 1.5;
	overlay += vec3(0.0, 1.0, 0.5) * scan * 0.6;

	// ── 3e. Microscopic organisms ─────────────────────────────────────
	float organisms = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.05 + fi * 2.7) * 0.38,
			0.5 + cos(t * 0.04 + fi * 1.9) * 0.38
		);
		vec2 to_org = uv - pos;
		float r_org = length(to_org);
		float angle = atan(to_org.y, to_org.x);
		float blob_r = 0.018 + 0.006 * sin(angle * 3.0 + t * 0.4 + fi)
				   + 0.004 * sin(angle * 5.0 - t * 0.25 + fi * 2.0);
		blob_r *= 1.0 + energy * 0.5;
		float blob = smoothstep(blob_r + 0.005, blob_r * 0.2, r_org);
		organisms += blob * (0.08 + 0.10 * (sin(t * 0.2 + fi * 1.3) * 0.5 + 0.5));
	}
	overlay += vec3(0.0, 1.0, 0.5) * organisms * 0.45;
	overlay += vec3(0.0, 0.5, 1.0) * organisms * 0.20;

	// ── 3f. Cellular division — voronoi membranes ─────────────────────
	vec2 cell_uv = uv * 5.0;
	vec2 cell_id = floor(cell_uv);
	vec2 cell_fract = fract(cell_uv) - 0.5;
	float min_cell = 1.0;
	float sec_cell = 1.0;
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 nb = vec2(float(cx), float(cy));
			vec2 pt = vec2(
				sin(t * 0.15 + dot(cell_id + nb, vec2(127.1, 311.7))) * 0.25,
				cos(t * 0.12 + dot(cell_id + nb, vec2(269.5, 183.3))) * 0.25
			);
			float cd = length(nb + pt - cell_fract);
			if (cd < min_cell) {
				sec_cell = min_cell;
				min_cell = cd;
			} else if (cd < sec_cell) {
				sec_cell = cd;
			}
		}
	}
	float membrane = sec_cell - min_cell;
	float cell_edge = exp(-membrane * 18.0) * 0.03;
	overlay += vec3(0.8, 0.0, 1.0) * cell_edge * 2.0;
	overlay += vec3(0.3, 0.0, 0.9) * cell_edge * 0.8;

	// ── 3g. Liquid mercury highlights ─────────────────────────────────
	float mercury = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(t * 0.03 + fi * 3.14) * 0.28,
			0.5 + cos(t * 0.025 + fi * 2.72) * 0.28
		);
		float mr = length(uv - mc);
		float mb = exp(-mr * mr * (35.0 + energy * 25.0));
		mercury += pow(max(mb, 0.0), 3.0);
	}
	overlay += vec3(0.3, 1.0, 0.85) * mercury * 0.20;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 4: COMPOSITE — trail + new geometry
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;

	// Deep void background (dim — feedback handles persistence)
	new_col += mix(vec3(0.0, 0.0, 0.02), vec3(0.0, 0.005, 0.04), uv.y);

	vec3 col = trail + new_col;

	COLOR = vec4(col, 1.0);
}
