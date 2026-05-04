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
#define TAU 6.28318530718

// ── Helpers ──────────────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Smooth minimum — organic merging of shapes (the key to metaball look)
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Organic field ────────────────────────────────────────────────────
// Five blobs arranged in a slow spiral, noise-displaced surfaces,
// smooth-min blended so they merge like living tissue.
// Audio drives: spread (bass), displacement (energy), merge radius (beat).
float organic_field(vec3 p, float t) {
	float d = 1e10;

	for (int i = 0; i < 5; i++) {
		float fi = float(i);

		// Spiral arrangement that slowly rotates
		float angle = fi * TAU * 0.4 + t * 0.12;
		float spread = 1.0 + bass * 0.4;
		vec3 center = vec3(
			cos(angle) * 1.1 * spread,
			sin(angle * 0.7 + fi * 0.5) * 0.7,
			fi * 2.0 - 4.0 + sin(t * 0.08 + fi * 0.9) * 0.6
		);

		// Pulsing radius — sub_bass breathes the whole colony
		float r = 0.45 + 0.12 * sin(t * 0.35 + fi * 0.8) + sub_bass * 0.1;

		// Organic surface displacement — noise makes the surface feel alive
		float disp = sin(p.x * 2.5 + t * 0.45 + fi)
		           * cos(p.y * 2.5 - t * 0.3 + fi * 0.7)
		           * sin(p.z * 2.0 + t * 0.35 + fi * 1.1);
		disp *= 0.1 + energy * 0.08;

		float blob = length(p - center) - r + disp;
		// Smooth merge — louder music = more blending between bodies
		d = smin(d, blob, 0.45 + beat * 0.25);
	}

	return d;
}

// ── Caustics ─────────────────────────────────────────────────────────
// Underwater light refraction pattern — overlapping wave interference
float caustics(vec2 uv, float t) {
	float c = 0.0;
	c += sin(uv.x * 10.0 + t * 1.4) * sin(uv.y * 8.0 + t * 1.1);
	c += sin(uv.x * 8.0 - t * 0.75 + 1.0) * sin(uv.y * 12.0 + t * 0.95);
	c += sin((uv.x + uv.y) * 6.0 + t * 0.5) * sin((uv.x - uv.y) * 7.0 - t * 0.65);
	return pow(max(c * 0.1, 0.0), 2.0);
}

void fragment() {
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);

	float t = time_val;

	// ── Camera — slow drift through the colony ────────────────────
	vec3 ro = vec3(
		sin(t * 0.08) * 1.2,
		cos(t * 0.06) * 0.8,
		t * 2.0
	);
	vec3 ray = normalize(vec3(p, 1.5));

	// Gentle sway (from Starfall DNA)
	float sway_xy = sin(t * 0.018) * 0.18 + sin(t * 0.006) * 0.08;
	float sway_yz = cos(t * 0.013) * 0.05 + sin(t * 0.004) * 0.03;
	ray.xy *= rot(sway_xy);
	ray.yz *= rot(sway_yz);

	// ── Raymarch with DOF + phantom pulses ────────────────────────
	float march_t = 0.0;
	float acc = 0.0;
	float acc_pulse = 0.0;

	// Soft DOF — focal plane drifts (from both parents)
	float focal_dist = 4.5 + sin(t * 0.09) * 1.5;
	float glow_falloff = 4.0 + energy * 5.0 + beat * 3.0;

	int max_steps = 55 + int(density * 25.0);
	for (int i = 0; i < 80; i++) {
		if (i >= max_steps) break;

		vec3 pos = ro + ray * march_t;

		// Tile for infinite repetition (from Afterimage DNA)
		pos = mod(pos - 3.0, 6.0) - 3.0;

		float d = organic_field(pos, t);
		d = max(abs(d), 0.01);

		// DOF — glow accumulates strongest near focal plane
		float dof = exp(-pow((march_t - focal_dist) * 0.12, 2.0));
		float glow = exp(-d * glow_falloff) * mix(0.25, 1.0, dof);
		acc += glow;

		// Phantom pulse wave synced to beat (from Afterimage DNA)
		float pulse = sin(march_t * 1.5 - t * 3.0 + beat_phase * TAU);
		pulse = pow(max(pulse, 0.0), 4.0);
		acc_pulse += glow * pulse;

		march_t += d * 0.5;
	}

	// ── Color — pastel palette (rose / lavender / mint / peach) ────
	float hue = beat_phase * TAU;
	vec3 band_color = vec3(
		0.72 + 0.28 * sin(hue + 0.3),
		0.72 + 0.28 * sin(hue + 2.4),
		0.72 + 0.28 * sin(hue + 4.5)
	);

	// Frequency band coloring
	band_color.r += (bass + sub_bass) * 0.3;
	band_color.g += low_mid * 0.18 + mid * 0.12;
	band_color.b += (treble + presence) * 0.25;

	// Mood tint (from Starfall DNA)
	vec3 warm_tint = vec3(0.22, 0.08, 0.28 + sin(t) * 0.1);
	vec3 cool_tint = vec3(0.06, 0.18, 0.42 + cos(t * 0.5) * 0.1);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	// Primary glow
	vec3 col = vec3(0.0);
	col += mix(mood_tint, band_color, 0.5 + energy * 0.5) * acc * 0.013;

	// Phantom pulse — warm peach/lavender
	vec3 pulse_col = mix(
		vec3(0.8, 0.6, 0.85),
		vec3(0.9, 0.7, 0.6),
		warmth
	);
	col += pulse_col * acc_pulse * 0.014;

	// Kick adds rose bloom
	col += vec3(0.55, 0.28, 0.45) * acc * kick * 0.008;
	// Hihat adds mint shimmer
	col += vec3(0.28, 0.65, 0.5) * acc * hihat * 0.005;

	// Onset flash — soft pastel
	col += vec3(0.4, 0.32, 0.5) * onset * 0.15;

	// Beat-phase brightness swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.15;

	// ── 2D Overlay layers ─────────────────────────────────────────

	// ── Caustics — underwater refraction ───────────────────────
	float caust = caustics(UV * 3.0, t);
	col += vec3(0.55, 0.78, 0.9) * caust * (0.12 + energy * 0.15);
	col += vec3(0.75, 0.65, 0.9) * caust * warmth * 0.08;

	// ── Bioluminescent plankton ────────────────────────────────
	float plankton = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.06 + fi * 2.391) * 0.44,
			0.5 + cos(t * 0.05 + fi * 1.731) * 0.44
		);
		float d_p = length(UV - pos);
		float pulse = 0.3 + 0.7 * pow(sin(t * (0.2 + fi * 0.06) + fi * 0.9) * 0.5 + 0.5, 2.0);
		plankton += exp(-d_p * (80.0 + energy * 40.0)) * pulse * 0.025;
	}
	col += vec3(0.5, 0.78, 1.0) * plankton;
	col += vec3(0.68, 1.0, 0.75) * plankton * 0.4;

	// ── Flowing silk ribbons ───────────────────────────────────
	float silk = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float phase = fi * 1.618 + t * (0.05 + fi * 0.012);
		float y = 0.5
			+ sin(UV.x * (2.0 + fi * 0.7) + phase) * (0.05 + fi * 0.012)
			+ cos(UV.x * (3.5 + fi * 0.4) - phase * 0.6) * 0.025;
		float s_d = abs(UV.y - y);
		silk += exp(-s_d * (200.0 + energy * 100.0)) * (0.006 + energy * 0.003);
	}
	col += vec3(0.95, 0.8, 0.88) * silk;
	col += vec3(0.8, 0.75, 1.0) * silk * 0.5;

	// ── Microscopic organisms (from Afterimage DNA) ────────────
	float organisms = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.045 + fi * 2.7) * 0.38,
			0.5 + cos(t * 0.035 + fi * 1.9) * 0.38
		);
		vec2 to_org = UV - pos;
		float r_org = length(to_org);
		float angle = atan(to_org.y, to_org.x);
		float blob_r = 0.018 + 0.006 * sin(angle * 3.0 + t * 0.35 + fi)
		               + 0.004 * sin(angle * 5.0 - t * 0.22 + fi * 2.0);
		blob_r *= 1.0 + energy * 0.5;
		float blob = smoothstep(blob_r + 0.005, blob_r * 0.2, r_org);
		organisms += blob * (0.12 + 0.18 * (sin(t * 0.18 + fi * 1.3) * 0.5 + 0.5));
	}
	col += vec3(0.55, 0.82, 0.7) * organisms * 0.14;
	col += vec3(0.4, 0.6, 0.88) * organisms * 0.07;

	// ── Cellular division — voronoi membranes ──────────────────
	vec2 cell_uv = UV * 5.0;
	vec2 cell_id = floor(cell_uv);
	vec2 cell_fract = fract(cell_uv) - 0.5;
	float min_cell = 1.0;
	float sec_cell = 1.0;
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 nb = vec2(float(cx), float(cy));
			vec2 pt = vec2(
				sin(t * 0.12 + dot(cell_id + nb, vec2(127.1, 311.7))) * 0.25,
				cos(t * 0.1  + dot(cell_id + nb, vec2(269.5, 183.3))) * 0.25
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
	float cell_edge = exp(-membrane * 20.0) * 0.035;
	col += vec3(0.65, 0.85, 0.7) * cell_edge;
	col += vec3(0.55, 0.65, 0.88) * cell_edge * 0.4;

	// ── Liquid mercury highlights ──────────────────────────────
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
	col += vec3(0.75, 0.8, 0.88) * mercury * 0.05;

	// ── Organic cellular texture ───────────────────────────────
	float n1 = texture(noise_tex, UV * 4.0 + t * 0.025).r;
	float n2 = texture(noise_tex, UV * 8.0 - t * 0.015 + 3.7).r;
	float cellular_tex = abs(n1 - n2) * 0.1;
	col += vec3(0.85, 0.92, 0.9) * cellular_tex * (0.3 + energy * 0.6);

	// ── Pastel gradient underlay ───────────────────────────────
	vec3 pastel_bg = mix(
		vec3(0.08, 0.04, 0.12),
		vec3(0.04, 0.07, 0.12),
		UV.y
	);
	col += pastel_bg * 0.1;

	// ── Alpha — depth fade + beat punch ────────────────────────
	float alpha = 1.0 - march_t * 0.02;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha += beat * 0.1;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(clamp(col, 0.0, 1.0), alpha);
}
