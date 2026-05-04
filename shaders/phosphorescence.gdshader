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

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

// ── Constants ────────────────────────────────────────────────────────
#define PI  3.14159265359
#define TAU 6.28318530718

// ── Helpers ──────────────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Smooth minimum — organic merging
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Organic field ────────────────────────────────────────────────────
// Five shapes, each a different geometry, each morphing based on
// its own slow-changing audio driver. No two look alike.
//
//   blob 0  →  sphere ↔ octahedron   driven by brightness
//   blob 1  →  box ↔ sphere           driven by warmth
//   blob 2  →  torus ↔ box            driven by energy
//   blob 3  →  sphere ↔ capsule       driven by bass
//   blob 4  →  sphere ↔ diamond-spike driven by treble

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

		// ── Per-blob shape selection ───────────────────────────
		// Sphere (shared baseline)
		float s_sphere = length(rel) - r;

		// Rounded box
		vec3 bq = abs(rel) - vec3(r * 0.72);
		float s_box = length(max(bq, 0.0)) + min(max(bq.x, max(bq.y, bq.z)), 0.0);

		// Octahedron
		float s_oct = (abs(rel.x) + abs(rel.y) + abs(rel.z) - r * 0.92) / 1.73;

		// Torus
		vec2 tq = vec2(length(rel.xz) - r * 0.55, rel.y);
		float s_torus = length(tq) - r * 0.22;

		// Capsule (elongated sphere along Y)
		float cap_h = r * 0.7;
		vec3 cap_sw = rel;
		cap_sw.y -= clamp(cap_sw.y, -cap_h, cap_h);
		float s_capsule = length(cap_sw) - r * 0.5;

		// Diamond spike (flattened octahedron)
		vec3 d_rel = rel;
		d_rel.y *= 0.55;
		float s_diamond = (abs(d_rel.x) + abs(d_rel.y) + abs(d_rel.z) - r * 0.85) / 1.73;

		// ── Pick morph pair per blob ──────────────────────────
		float shape;
		if (i == 0) {
			shape = mix(s_sphere, s_oct, brightness);       // round → spiky
		} else if (i == 1) {
			shape = mix(s_box, s_sphere, warmth);            // boxy → round
		} else if (i == 2) {
			shape = mix(s_torus, s_box, energy);             // donut → cube
		} else if (i == 3) {
			shape = mix(s_sphere, s_capsule, bass);          // ball → capsule
		} else {
			shape = mix(s_sphere, s_diamond, treble * 0.8);  // ball → diamond
		}

		// Surface displacement — organic texture
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
// Three geometric rings, each with a unique cross-section shape.
// Ring 0: circle   Ring 1: square   Ring 2: trefoil-lobe
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
			// Perfect circle — the baseline
			cross_section = length(q) - thickness;
		} else if (i == 1) {
			// Square cross-section that softens to circle with warmth
			float sq = max(abs(q.x), abs(q.y)) - thickness;
			float ci = length(q) - thickness;
			cross_section = mix(ci, sq, 0.7 - warmth * 0.4);
		} else {
			// Trefoil-lobed cross-section
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
// Two wave sources creating overlapping ripple patterns
float interference(vec2 uv, float t) {
	vec2 src1 = vec2(0.35 + sin(t * 0.08) * 0.08, 0.5 + cos(t * 0.06) * 0.05);
	vec2 src2 = vec2(0.65 + cos(t * 0.07) * 0.08, 0.5 + sin(t * 0.05) * 0.05);
	float d1 = length(uv - src1);
	float d2 = length(uv - src2);
	float wave = sin(d1 * 50.0 - t * 2.5) + sin(d2 * 50.0 - t * 2.5);
	return pow(max(wave * 0.5 + 0.5, 0.0), 4.0) * 0.06;
}

// ── Lissajous curve trace ────────────────────────────────────────────
// Parametric curve drawn as a string of glowing dots
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
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);
	float t = time_val;

	// ── Camera — wandering curve, not a straight line ─────────────
	// Two-frequency sine composition creates a non-repeating drift
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

	// ── Raymarch ─────────────────────────────────────────────────
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

		// ── Per-cell identity ─────────────────────────────────
		// Each repetition cell gets a unique hash from its grid
		// position. This drives rotation, time offset, and scale
		// so cells behave as individuals, not clones.
		vec3 cell_id = floor((raw_pos + 3.0) / 6.0);
		float ch  = fract(sin(dot(cell_id, vec3(127.1, 311.7, 74.7))) * 43758.5);
		float ch2 = fract(sin(dot(cell_id, vec3(269.5, 183.3, 41.1))) * 43758.5);
		float ch3 = fract(sin(dot(cell_id, vec3(53.8, 197.4, 311.2))) * 43758.5);

		vec3 pos = mod(raw_pos - 3.0, 6.0) - 3.0;

		// Each cell rotated to a unique orientation
		pos.xz *= rot(ch * TAU);
		pos.yz *= rot(ch2 * PI);

		// Gentle per-cell scale breathing
		float cell_scale = 1.0 + (ch3 - 0.5) * 0.15 + sin(t * 0.1 + ch3 * 5.0) * 0.05;
		pos *= cell_scale;

		// Time offset per cell — every cell is at a different moment
		float t_cell = t + ch * 5.0;

		// Whole-scene breath
		float breath = 1.0 + sin(t * 0.15) * 0.015 + sub_bass * 0.02;
		pos *= breath;

		float d_blobs = organic_field(pos, t_cell);
		float d_rings = abstract_rings(pos, t_cell);
		float d = smin(d_blobs, d_rings, 0.25);
		d = max(abs(d), 0.01);

		// DOF
		float dof = exp(-pow((march_t - focal_dist) * 0.12, 2.0));
		float glow = exp(-d * glow_falloff) * mix(0.25, 1.0, dof);
		acc += glow;

		// Separate ring accumulation — they get their own color channel
		float ring_glow = exp(-max(abs(d_rings), 0.01) * glow_falloff * 1.3)
		                * mix(0.3, 1.0, dof);
		acc_ring += ring_glow;

		// Phantom pulse wave
		float pulse = sin(march_t * 1.5 - t * 3.0 + beat_phase * TAU);
		pulse = pow(max(pulse, 0.0), 4.0);
		acc_pulse += glow * pulse;

		march_t += d * 0.5;
	}

	// ── Color — deep ocean bioluminescence: electric teal, hot pink, acid green ──
	// Full-range cosine palette: 0–1, vivid saturated neons
	float hue = beat_phase * TAU + t * 0.07;
	vec3 band_color = vec3(
		0.5 + 0.5 * sin(hue + 0.0),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);

	// Bass suppresses red (blobs read blue-green), treble boosts blue
	band_color.r = mix(band_color.r, 0.05 + mid * 0.35, (bass + sub_bass) * 0.5);
	band_color.g += low_mid * 0.25 + mid * 0.2;
	band_color.b += (treble + presence) * 0.35;

	// Vivid mood tints: electric teal (cool) ↔ hot pink (warm)
	vec3 warm_tint = vec3(1.0, 0.04 + sin(t * 0.3) * 0.04, 0.65);
	vec3 cool_tint = vec3(0.0, 0.85 + cos(t * 0.4) * 0.1, 0.85);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	vec3 col = vec3(0.0);

	// Organic blob glow — vivid teal/cyan base, richer multiplier
	col += mix(mood_tint, band_color, 0.4 + energy * 0.6) * acc * 0.024;

	// Abstract rings — neon magenta/hot pink, vivid contrast against teal blobs
	col += vec3(1.0, 0.05, 0.75) * acc_ring * 0.022;
	col += vec3(0.7, 0.0, 1.0)   * acc_ring * kick * 0.018;

	// Phantom pulse — acid green / electric gold
	vec3 pulse_col = mix(vec3(0.1, 1.0, 0.3), vec3(1.0, 0.9, 0.0), warmth);
	col += pulse_col * acc_pulse * 0.028;

	// Percussion: sharp vivid strikes
	col += vec3(0.2, 0.65, 1.0) * acc * kick  * 0.022;  // electric blue kick bloom
	col += vec3(1.0, 0.4, 0.9)  * acc * snare * 0.018;  // pink-white snare
	col += vec3(0.2, 1.0, 0.45) * acc * hihat * 0.014;  // lime hihat shimmer

	// Onset: electric cyan burst, hot pink at peak
	col += vec3(0.0, 1.0, 0.9) * onset * 0.4;
	col += vec3(1.0, 0.0, 0.5) * onset * onset * 0.25;

	// Beat-phase swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.28;

	// ── 2D Overlays (unique to this shader) ──────────────────────

	// ── Caustics ──────────────────────────────────────────────
	float caust = caustics(UV * 3.0, t);
	col += vec3(0.0, 0.7, 1.0)  * caust * (0.3 + energy * 0.45);
	col += vec3(0.6, 0.0, 1.0)  * caust * warmth * 0.22;

	// ── Interference fringes ──────────────────────────────────
	float fringes = interference(UV, t);
	col += vec3(0.0, 1.0, 0.9)  * fringes * (1.1 + energy * 1.3);
	col += vec3(1.0, 0.15, 0.8) * fringes * warmth * 0.7;

	// ── Lissajous curves (3:2 figure) ────────────────────────
	float liss = lissajous(UV, t);
	col += vec3(0.1, 0.5, 1.0) * liss * 2.5;
	col += vec3(1.0, 0.35, 0.2) * liss * warmth * 1.2;

	// ── Second Lissajous (5:4 figure — different shape) ──────
	float liss2 = 0.0;
	for (int i = 0; i < 25; i++) {
		float fi = float(i) * 0.14;
		float s = fi + t * 0.09 + 2.0;
		vec2 pt = vec2(
			0.5 + sin(5.0 * s + 1.2) * 0.22,
			0.5 + sin(4.0 * s + 0.3) * 0.22
		);
		float d = length(UV - pt);
		liss2 += exp(-d * 280.0) * 0.007;
	}
	col += vec3(0.9, 0.1, 1.0) * liss2 * 2.5;
	col += vec3(0.1, 1.0, 0.5) * liss2 * brightness * 1.2;

	// ── Bioluminescent plankton ───────────────────────────────
	float plankton = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.06 + fi * 2.391) * 0.44,
			0.5 + cos(t * 0.05 + fi * 1.731) * 0.44
		);
		float d_p = length(UV - pos);
		float pulse = 0.3 + 0.7 * pow(sin(t * (0.2 + fi * 0.06) + fi * 0.9) * 0.5 + 0.5, 2.0);
		plankton += exp(-d_p * (80.0 + energy * 40.0)) * pulse * 0.022;
	}
	col += vec3(0.0, 0.75, 1.0) * plankton * 2.8;
	col += vec3(0.1, 1.0, 0.45) * plankton * 1.0;

	// ── Liquid mercury highlights ─────────────────────────────
	float mercury = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(t * 0.025 + fi * 3.14) * 0.28,
			0.5 + cos(t * 0.02 + fi * 2.72) * 0.28
		);
		float mr = length(UV - mc);
		float mb = exp(-mr * mr * (30.0 + energy * 20.0));
		mercury += pow(max(mb, 0.0), 3.0);
	}
	col += vec3(0.35, 1.0, 0.9) * mercury * 0.18;

	// ── Organic texture ───────────────────────────────────────
	float n1 = texture(noise_tex, UV * 4.0 + t * 0.025).r;
	float n2 = texture(noise_tex, UV * 8.0 - t * 0.015 + 3.7).r;
	float cellular_tex = abs(n1 - n2) * 0.1;
	col += vec3(0.0, 0.9, 0.75) * cellular_tex * (0.5 + energy * 1.0);

	// ── Deep ocean void background ────────────────────────────
	vec3 pastel_bg = mix(vec3(0.0, 0.01, 0.05), vec3(0.0, 0.015, 0.04), UV.y);
	col += pastel_bg * 0.06;

	// ── Alpha ─────────────────────────────────────────────────
	float alpha = 1.0 - march_t * 0.02;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha += beat * 0.1;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(clamp(col, 0.0, 1.0), alpha);
}
