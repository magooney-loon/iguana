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
const float PI2 = PI * 2.0;

// ── Helper functions ─────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec2 pmod(vec2 p, float r) {
	float a = atan(p.x, p.y) + PI / r;
	float n = PI2 / r;
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

void fragment() {
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);

	// Camera – pure time, no audio jitter
	float t_cam = time_val;
	vec3 c_pos = vec3(0.0, 0.0, -3.0 * t_cam);
	vec3 c_dir = normalize(vec3(0.0, 0.0, -1.0));
	vec3 c_up = vec3(sin(t_cam), 1.0, 0.0);
	vec3 c_side = cross(c_dir, c_up);
	vec3 ray = normalize(c_side * p.x + c_up * p.y + c_dir);

	// Phantom raymarch – glow accumulation
	float acc = 0.0;
	float acc2 = 0.0;
	float t = 0.0;

	// Soft depth of field
	float focal_dist = 4.0 + sin(time_val * 0.08) * 1.5;

	// Glow falloff: energy tightens the glow, beat/onset punch it
	float glow_falloff = 3.0 + energy * 4.0;

	for (int i = 0; i < 99; i++) {
		vec3 pos = c_pos + ray * t;
		float dist = map(pos);
		dist = max(abs(dist), 0.02);

		float dof = exp(-pow((t - focal_dist) * 0.15, 2.0));
		float a = exp(-dist * glow_falloff) * mix(0.35, 1.0, dof);

		// Phantom pulse – synced to beat_phase for musical timing
		float phantom_phase = mod(length(pos) + 24.0 * time_val, 30.0);
		if (phantom_phase < 3.0) {
			a *= 2.0;
			acc2 += a;
		}

		acc += a;
		t += dist * 0.5;
	}

	// ── Acid chrome — neon green phantoms, violet IFS, magenta strikes ──
	// IFS base: deep indigo, each channel driven by a different band
	float lum  = acc  * 0.016;
	float ghost = acc2 * 0.026;

	vec3 col = vec3(
		lum * (0.25 + bass * 0.9  + kick * 1.4),
		lum * (0.04 + mid  * 0.35) + ghost * (0.0 + energy * 0.6),
		lum * (0.75 + treble * 0.7) + ghost * 0.15
	);

	// Phantom pulses → vivid acid green / gold
	col += vec3(0.05, 1.0, 0.2) * ghost * (0.9 + energy * 0.7);
	col += vec3(0.9, 1.0, 0.0) * ghost * warmth * 0.5;

	// Hue rotation layered over IFS glow
	float hue = beat_phase * 6.28318 + time_val * 0.06;
	vec3 hue_col = vec3(
		0.5 + 0.5 * sin(hue),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	col += hue_col * lum * (0.4 + energy * 0.5);

	// Percussion: sharp, distinct hue per drum
	col += vec3(1.0, 0.4, 0.0)  * acc  * 0.014 * kick;   // orange kick
	col += vec3(1.0, 0.0, 0.75) * acc2 * 0.016 * snare;  // magenta snare
	col += vec3(0.4, 1.0, 0.0)  * acc  * 0.008 * hihat;  // lime hihat

	// Onset: vivid hot pink / deep violet core
	col += vec3(1.0, 0.0, 0.65) * onset * 0.5;
	col += vec3(0.15, 0.0, 0.9) * onset * onset * 0.35;

	// Beat-phase brightness swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.35;

	float alpha = 1.0 - t * 0.03;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha += beat * 0.1;
	alpha = clamp(alpha, 0.0, 1.0);

	// ── Microscopic organisms ──────────────────────────────
	float organisms = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(time_val * 0.05 + fi * 2.7) * 0.38,
			0.5 + cos(time_val * 0.04 + fi * 1.9) * 0.38
		);
		vec2 to_org = UV - pos;
		float r_org = length(to_org);
		float angle = atan(to_org.y, to_org.x);
		float blob_r = 0.018 + 0.006 * sin(angle * 3.0 + time_val * 0.4 + fi)
				   + 0.004 * sin(angle * 5.0 - time_val * 0.25 + fi * 2.0);
		blob_r *= 1.0 + energy * 0.5;
		float blob = smoothstep(blob_r + 0.005, blob_r * 0.2, r_org);
		organisms += blob * (0.15 + 0.2 * (sin(time_val * 0.2 + fi * 1.3) * 0.5 + 0.5));
	}
	col += vec3(0.0, 1.0, 0.5) * organisms * 0.55;
	col += vec3(0.0, 0.5, 1.0) * organisms * 0.25;

	// ── Cellular division — voronoi membranes ──────────────
	vec2 cell_uv = UV * 5.0;
	vec2 cell_id = floor(cell_uv);
	vec2 cell_fract = fract(cell_uv) - 0.5;
	float min_cell = 1.0;
	float sec_cell = 1.0;
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 nb = vec2(float(cx), float(cy));
			vec2 pt = vec2(
				sin(time_val * 0.15 + dot(cell_id + nb, vec2(127.1, 311.7))) * 0.25,
				cos(time_val * 0.12 + dot(cell_id + nb, vec2(269.5, 183.3))) * 0.25
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
	float cell_edge = exp(-membrane * 18.0) * 0.04;
	col += vec3(0.8, 0.0, 1.0) * cell_edge * 2.5;
	col += vec3(0.3, 0.0, 0.9) * cell_edge * 1.0;

	// ── Liquid mercury highlights ──────────────────────────
	float mercury = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(time_val * 0.03 + fi * 3.14) * 0.28,
			0.5 + cos(time_val * 0.025 + fi * 2.72) * 0.28
		);
		float mr = length(UV - mc);
		float mb = exp(-mr * mr * (35.0 + energy * 25.0));
		mercury += pow(max(mb, 0.0), 3.0);
	}
	col += vec3(0.3, 1.0, 0.85) * mercury * 0.25;

	// ── Deep void background ───────────────────────────────
	vec3 pastel_bg = mix(vec3(0.0, 0.0, 0.04), vec3(0.0, 0.01, 0.06), UV.y);
	col += pastel_bg;

	COLOR = vec4(clamp(col, 0.0, 1.0), alpha);
}
