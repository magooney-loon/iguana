shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Cell Culture
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Living Voronoi cell colony with mitosis pulses, vein networks and bioluminescent membranes
//
//  Post-processing defaults
//  @exposure:       2.07
//  @tonemap_knee:   0.25
//  @gamma:          3.00
//  @vignette_dark:  0.40
//  @grain_strength: 0.02
//  @loop_reinhard:  0.00
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
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.9;

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

// Cosine palette (Inigo Quilez)
vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	return a + b * cos(TAU * (c * t + d));
}

// Hash function for Voronoi cell centers
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// ── Voronoi with organic features ────────────────────────────────────
// Returns: xy = cell center offset, z = F1 distance, w = F2 distance
vec4 voronoi(vec2 uv, float t) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);

	float d1 = 8.0;  // F1 — distance to nearest cell center
	float d2 = 8.0;  // F2 — distance to second-nearest
	vec2 closest = vec2(0.0);

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			// Cell center: animated drift, breathing with bass
			vec2 cell = hash2(i + neighbor);
			// Organic pulsing — each cell breathes at its own phase
			cell = 0.5 + 0.5 * sin(t * 0.4 + TAU * cell);
			// Kick causes a mitosis-like expansion pulse
			cell += 0.08 * kick * sin(t * 2.0 + TAU * hash2(i + neighbor + 100.0));
			vec2 diff = neighbor + cell - f;
			float d = length(diff);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				closest = i + neighbor;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec4(closest, d1, d2);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	vec2 res = rect_size;
	vec2 p   = (uv - 0.5) * vec2(res.x / res.y, 1.0);
	float aspect = res.x / res.y;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — microscope slide drift + organic spread
	// ══════════════════════════════════════════════════════════════════
	// No tunnel, no spiral. The culture drifts and grows like a real
	// petri dish under a slowly panning microscope.

	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── Outward expansion (culture growing), not inward tunnel ──────
	// Slow breathing cycle + kick-triggered growth spurt
	float breathe = sin(t * 0.3) * 0.003;
	float grow    = kick * 0.008 + sub_bass * 0.004;
	center *= 1.0 + breathe + grow;

	// ── Wandering drift instead of rotation ────────────────────────
	// Two overlapping sine paths = smooth Brownian-like wander
	vec2 drift = vec2(
		sin(t * 0.17) * 0.006 + cos(t * 0.31) * 0.004,
		cos(t * 0.23) * 0.006 + sin(t * 0.37) * 0.004
	);
	drift *= 1.0 + energy * 1.5;   // louder = faster pan
	center -= drift;

	vec2 fb_uv = center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;

	// ── Polar organic warp — radial/circular flow ──────────────────
	// Displacement in polar coords creates the circular petri dish feel
	float r_c = length(center);
	float a_c = atan(center.y, center.x);
	float warp_r = sin(a_c * 5.0 + t * 0.7 + r_c * 8.0) * 0.010
	             + sin(a_c * 3.0 - t * 0.5 + r_c * 4.0) * 0.006;
	float warp_a = cos(a_c * 4.0 + t * 0.9 + r_c * 6.0) * 0.010
	             + cos(a_c * 7.0 - t * 0.3 + r_c * 3.0) * 0.005;
	// Convert polar warp back to cartesian
	vec2 warp = vec2(
		warp_r * cos(a_c) - warp_a * sin(a_c),
		warp_r * sin(a_c) + warp_a * cos(a_c)
	);
	warp *= 1.0 + bass * 1.5 + energy * 0.8;

	vec2 sample_uv  = fb_uv + warp;
	vec2 edge_d     = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	// Decay: higher energy = shorter trails (faster fade)
	float decay = mix(0.93, 0.86, energy);
	trail *= decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — living Voronoi cell culture
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = vec3(0.0);

	// Cell scale: more activity = denser culture, onset causes mitosis splits
	float cell_scale = 5.0 + activity * 4.0 + onset * 2.0;

	// Two layers of Voronoi at different scales for visual depth
	for (int layer = 0; layer < 2; layer++) {
		float scale = cell_scale * (layer == 0 ? 1.0 : 0.45);
		float t_off = layer == 0 ? 0.0 : 7.3;
		float weight = layer == 0 ? 1.0 : 0.35;

		vec2 vp = p * scale;
		// Slow domain rotation per layer
		vp *= rot2(t * 0.03 * (layer == 0 ? 1.0 : -0.7));

		vec4 vor = voronoi(vp, t + t_off);
		float f1 = vor.z;
		float f2 = vor.w;
		vec2 cell_id = vor.xy;

		// ── Cell membranes (edges between cells) ─────────────────────
		float edge_dist = f2 - f1;  // thin near edges
		float membrane = 1.0 - smoothstep(0.0, 0.08 + bass * 0.06, edge_dist);

		// Mitosis pulse: on strong kicks, membranes glow bright
		float mitosis_glow = kick * 0.6 * smoothstep(0.02, 0.06, edge_dist);

		// ── Cell interior coloring ───────────────────────────────────
		// Each cell gets a unique color from its ID
		float cell_hash = fract(sin(dot(cell_id, vec2(127.1, 311.7))) * 43758.5453);
		float cell_hash2 = fract(sin(dot(cell_id + 50.0, vec2(269.5, 183.3))) * 43758.5453);

		// Nucleus — bright dot at cell center
		float nucleus_r = 0.12 + 0.06 * sin(t * 1.5 + cell_hash * TAU);
		float nucleus = smoothstep(nucleus_r, nucleus_r * 0.3, f1);

		// Nucleolus — even smaller bright core
		float nucleolus = smoothstep(0.04, 0.01, f1) * 0.8;

		// ── Vein network (thin lines from center toward edges) ───────
		// Use angular modulation around the cell center
		float angle = atan(
			fract(vp.x + cell_id.x) - 0.5 + sin(cell_hash * 5.0) * 0.2,
			fract(vp.y + cell_id.y) - 0.5 + cos(cell_hash2 * 5.0) * 0.2
		);
		float veins = abs(sin(angle * (4.0 + cell_hash * 4.0)));
		veins = smoothstep(0.95, 1.0, veins) * smoothstep(0.4, 0.1, f1);
		// Veins pulse with the heartbeat (bass)
		veins *= 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2.5 + cell_hash * TAU)) * (0.5 + bass * 0.5);

		// ── Color palette selection ──────────────────────────────────
		// Bioluminescent greens, cyans, and magentas
		vec3 membrane_col;
		vec3 interior_col;
		vec3 nucleus_col;

		if (layer == 0) {
			// Outer layer: cool greens and cyans
			membrane_col = palette(
				cell_hash + t * 0.02,
				vec3(0.2, 0.5, 0.4),
				vec3(0.2, 0.3, 0.3),
				vec3(1.0, 1.0, 1.0),
				vec3(0.0, 0.15, 0.10)
			);
			interior_col = palette(
				cell_hash + t * 0.015,
				vec3(0.05, 0.15, 0.12),
				vec3(0.05, 0.15, 0.10),
				vec3(1.0, 0.8, 0.7),
				vec3(0.1, 0.2, 0.15)
			);
			nucleus_col = vec3(0.4, 0.9, 0.7) + 0.3 * vec3(
				sin(t * 1.2 + cell_hash * 3.0),
				sin(t * 0.9 + cell_hash * 5.0),
				sin(t * 1.5 + cell_hash * 7.0)
			);
		} else {
			// Inner layer: warm magentas and golds — chromatin
			membrane_col = palette(
				cell_hash + t * 0.03,
				vec3(0.5, 0.2, 0.35),
				vec3(0.3, 0.2, 0.2),
				vec3(1.0, 1.0, 0.7),
				vec3(0.0, 0.05, 0.15)
			);
			nucleus_col = vec3(0.9, 0.5, 0.8);
		}

		// ── Composite this layer ─────────────────────────────────────
		// Membranes
		// Membranes: narrow feature, safe at 0.06 per pixel
		vec3 mem_color = membrane_col * membrane * 0.09;
		mem_color += membrane_col * 0.18 * mitosis_glow;  // subtle mitosis flash

		// Interior glow
		float interior = smoothstep(0.5, 0.0, f1) * 0.04 * (1.0 + warmth * 0.3);
		vec3 int_color = interior_col * interior;

		// Nucleus
		// Nucleus: point source, safe slightly higher but keep under 0.10
		vec3 nuc_color = nucleus_col * (nucleus * 0.07 + nucleolus * 0.14);

		// Veins
		vec3 vein_color = nucleus_col * veins * 0.04;

		new_col += (mem_color + int_color + nuc_color + vein_color) * weight;
	}

	// ── Bioluminescent glow bloom on beats ────────────────────────────
	// A radial pulse emanates from center on each kick
	float dist = length(p);
	float beat_ring = smoothstep(0.03, 0.0, abs(dist - 0.3 - beat_phase * 0.5));
	beat_ring *= onset * 0.08;
	vec3 bloom_col = vec3(0.3, 0.8, 0.6) * beat_ring;
	new_col += bloom_col;

	// ── Spectral band glow — each frequency band lights up a ring ────
	// Map 8 bands to 8 concentric rings for an equalizer petri dish
	for (int i = 0; i < 8; i++) {
		float band;
		if (i == 0) band = peak_00;
		else if (i == 1) band = peak_04;
		else if (i == 2) band = peak_08;
		else if (i == 3) band = peak_12;
		else if (i == 4) band = peak_16;
		else if (i == 5) band = peak_20;
		else if (i == 6) band = peak_24;
		else band = peak_28;

		float ring_r = 0.15 + float(i) * 0.08;
		float ring = exp(-abs(dist - ring_r) * 30.0) * band * 0.03;
		vec3 ring_col = palette(
			float(i) / 8.0,
			vec3(0.2, 0.5, 0.4),
			vec3(0.3, 0.3, 0.2),
			vec3(1.0, 1.0, 1.0),
			vec3(0.0, 0.33, 0.67)
		);
		new_col += ring_col * ring;
	}

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + new geometry, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════
	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
