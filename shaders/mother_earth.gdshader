shader_type canvas_item;

//  @name:          Mother Earth
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Metatron's Cube × Sri Yantra — sacred geometry phantom fly-through
//
//  @exposure:       3.00
//  @tonemap_knee:   0.0
//  @gamma:          2.69
//  @vignette_dark:  0.25
//  @grain_strength: 0.01
//  @loop_reinhard:  1.72
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
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader tuning ───────────────────────────────────────────────
uniform float loop_reinhard : hint_range(0.0, 3.0) = 2.36;

// ── Utility · auto-provided by visualizer.gd ────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

// ── Constants ───────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helpers ─────────────────────────────────────────────────────────
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

// Cosine palette (Inigo Quilez)
vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

// ── SDF primitives ──────────────────────────────────────────────────
float sd_sphere(vec3 p, vec3 c, float r) {
	return length(p - c) - r;
}

float sd_cylinder(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float sd_torus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

float sd_box(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

// ── Metatron's Cube SDF ─────────────────────────────────────────────
float metatron(vec3 p) {
	float d = 1e10;
	float node_r = 0.08 + bass * 0.03;
	float strut_r = 0.02 + sub_bass * 0.01;

	// Center node
	d = min(d, sd_sphere(p, vec3(0.0), node_r));

	// Inner hexagonal ring: 6 nodes at radius 1.0
	vec3 inner[6];
	for (int i = 0; i < 6; i++) {
		float angle = float(i) * TAU / 6.0;
		inner[i] = vec3(cos(angle), sin(angle), 0.0);
		d = min(d, sd_sphere(p, inner[i], node_r));
	}

	// Outer hexagonal ring: 6 nodes at radius 2.0, offset 30°
	vec3 outer[6];
	for (int i = 0; i < 6; i++) {
		float angle = float(i) * TAU / 6.0 + PI / 6.0;
		outer[i] = vec3(cos(angle) * 2.0, sin(angle) * 2.0, 0.0);
		d = min(d, sd_sphere(p, outer[i], node_r));
	}

	// Struts: center → inner
	for (int i = 0; i < 6; i++) {
		d = min(d, sd_cylinder(p, vec3(0.0), inner[i], strut_r));
	}
	// Struts: inner hexagon edges
	for (int i = 0; i < 6; i++) {
		d = min(d, sd_cylinder(p, inner[i], inner[(i + 1) % 6], strut_r));
	}
	// Struts: inner → outer radial
	for (int i = 0; i < 6; i++) {
		d = min(d, sd_cylinder(p, inner[i], outer[i], strut_r));
		d = min(d, sd_cylinder(p, inner[i], outer[(i + 5) % 6], strut_r));
	}
	// Struts: outer hexagon
	for (int i = 0; i < 6; i++) {
		d = min(d, sd_cylinder(p, outer[i], outer[(i + 1) % 6], strut_r));
	}
	// Cross bracing — full Metatron depth
	for (int i = 0; i < 6; i++) {
		d = min(d, sd_cylinder(p, inner[i], inner[(i + 2) % 6], strut_r * 0.7));
		d = min(d, sd_cylinder(p, outer[i], outer[(i + 2) % 6], strut_r * 0.5));
	}

	return d;
}

// ── Sri Yantra triangle ring ────────────────────────────────────────
float sri_triangle_edge(vec2 p, float radius, float rot_off, bool upward) {
	vec2 v0, v1, v2;
	if (upward) {
		v0 = vec2(0.0, radius);
		v1 = vec2(-radius * 0.866, -radius * 0.5);
		v2 = vec2(radius * 0.866, -radius * 0.5);
	} else {
		v0 = vec2(0.0, -radius);
		v1 = vec2(-radius * 0.866, radius * 0.5);
		v2 = vec2(radius * 0.866, radius * 0.5);
	}
	mat2 rm = rot(rot_off);
	v0 = rm * v0; v1 = rm * v1; v2 = rm * v2;

	// Sum distances to 3 edges → outline only
	float d = 1e10;
	vec2 edges[3] = vec2[3](v0, v1, v2);
	vec2 edges2[3] = vec2[3](v1, v2, v0);
	for (int i = 0; i < 3; i++) {
		vec2 a_pt = edges[i];
		vec2 b_pt = edges2[i];
		vec2 pa = p - a_pt, ba = b_pt - a_pt;
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		d = min(d, length(pa - ba * h));
	}
	float thickness = 0.03 + mid * 0.015;
	return abs(d) - thickness;
}

float sri_yantra(vec2 p) {
	float d = 1e10;
	// 4 upward (Shiva) at descending scales
	float up_sc[4] = float[4](1.0, 0.78, 0.58, 0.38);
	float up_rt[4] = float[4](0.0, 0.02, -0.01, 0.015);
	for (int i = 0; i < 4; i++) {
		d = min(d, sri_triangle_edge(p, up_sc[i], up_rt[i], true));
	}
	// 5 downward (Shakti)
	float dn_sc[5] = float[5](0.92, 0.72, 0.52, 0.32, 0.14);
	float dn_rt[5] = float[5](0.01, -0.015, 0.008, -0.012, 0.0);
	for (int i = 0; i < 5; i++) {
		d = min(d, sri_triangle_edge(p, dn_sc[i], dn_rt[i], false));
	}
	// Bindu center
	d = min(d, abs(length(p) - 0.06) - 0.015);
	// Outer containment
	d = min(d, abs(length(p) - 1.08) - (0.01 + energy * 0.005));
	return d;
}

// ── Scene map — tiled infinite sacred geometry ───────────────────────
float map(vec3 p) {
	// Tile in Z for infinite fly
	vec3 p1 = p;
	p1.z = mod(p1.z, 12.0) - 6.0;

	// Metatron's Cube layer — slowly rotates
	p1.xy *= rot(time_val * 0.15);
	float met = metatron(p1);

	// Sri Yantra layer — offset Z, counter-rotates
	vec3 p2 = p;
	p2.z = mod(p2.z + 6.0, 12.0) - 6.0;
	p2.xy *= rot(-time_val * 0.1);
	float yantra_z = abs(p2.z);
	float sri = sri_yantra(p2.xy);
	// Extrude 2D into thin Z slab
	sri = max(sri, yantra_z - 0.15 - bass * 0.05);

	// Sacred torus rings — orbiting the path
	vec3 p3 = p;
	p3.xy *= rot(time_val * 0.08);
	p3.xz *= rot(time_val * 0.06);
	float tor = sd_torus(p3, vec2(3.0 + sin(time_val * 0.2) * 0.5, 0.03 + energy * 0.02));

	return min(min(met, sri), tor);
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
	float zoom = 0.970 - sub_bass * 0.014 + onset * 0.010;
	center *= zoom;

	// Rotate: energy + beat drive spiral
	float rot_a = 0.005 + energy * 0.007 + beat * 0.004;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	// Per-pixel warp — aggressive like phantom_star
	vec2 warp = vec2(
		sin(center.y * 10.0 + t * 1.4) * 0.012,
		cos(center.x * 8.0  + t * 1.1) * 0.012
	);
	warp *= 1.0 + bass * 2.5 + energy * 1.5;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	// Chromatic aberration
	float ca = 0.0012 + energy * 0.0012;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;

	// Decay: louder music sustains trails
	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING — phantom sacred geometry fly-through
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	// Camera — phantom_star style full camera rig
	vec3 c_pos = vec3(0.0, 0.0, -3.0 * t);
	vec3 c_dir = normalize(vec3(0.0, 0.0, -1.0));
	vec3 c_up = vec3(sin(t * 0.08), 1.0, sin(t * 0.05) * 0.3);
	vec3 c_side = cross(c_dir, c_up);
	vec3 ray = normalize(c_side * p.x + c_up * p.y + c_dir);

	float acc = 0.0;
	float acc2 = 0.0;  // phantom pulse accumulator
	float march_t = 0.0;

	float focal_dist = 4.0 + sin(t * 0.08) * 1.5;
	float glow_falloff = 3.5 + energy * 4.0;

	for (int i = 0; i < 99; i++) {
		vec3 pos = c_pos + ray * march_t;
		float dist = map(pos);
		dist = max(abs(dist), 0.02);

		float dof = exp(-pow((march_t - focal_dist) * 0.15, 2.0));
		float a = exp(-dist * glow_falloff) * mix(0.35, 1.0, dof);

		// Phantom pulse — sacred geometry heartbeat synced to beat_phase
		float phantom_phase = mod(length(pos) + 24.0 * t, 30.0);
		if (phantom_phase < 3.0) {
			a *= 2.0;
			acc2 += a;
		}

		acc += a;
		march_t += dist * 0.5;
	}

	// ── Raymarching color — earth + cosmic gold ──
	float lum = acc * 0.005;
	float ghost = acc2 * 0.008;

	vec3 rm_col = vec3(
		lum * (0.35 + bass * 0.8 + kick * 1.2),
		lum * (0.15 + mid * 0.4) + ghost * (0.1 + energy * 0.5),
		lum * (0.05 + treble * 0.3) + ghost * 0.1
	);

	// Phantom pulses → sacred emerald / gold flashes
	rm_col += vec3(0.1, 0.9, 0.3) * ghost * (0.9 + energy * 0.7);
	rm_col += vec3(0.9, 0.75, 0.1) * ghost * warmth * 0.6;

	// Hue rotation layered over glow
	float hue = beat_phase * TAU + t * 0.06;
	vec3 hue_col = vec3(
		0.5 + 0.5 * sin(hue),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	// Earth bias: greens and golds dominate
	hue_col = mix(hue_col, vec3(0.3, 0.7, 0.2), 0.3 + low_mid * 0.2);
	rm_col += hue_col * lum * (0.2 + energy * 0.25);

	// Percussion: distinct earth-tone per drum
	rm_col += vec3(1.0, 0.5, 0.05)  * acc  * 0.014 * kick;
	rm_col += vec3(0.9, 0.15, 0.4)  * acc2 * 0.016 * snare;
	rm_col += vec3(0.3, 0.9, 0.5)   * acc  * 0.008 * hihat;

	// Onset flash
	rm_col += vec3(1.0, 0.85, 0.2) * onset * 0.35;
	rm_col += vec3(0.1, 0.7, 0.3)  * onset * onset * 0.20;

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

	// ── 3a. Fractal lightning roots ──────────────────────────────────
	float lightning = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float angle = fi * TAU / 7.0 + t * 0.03;
		vec2 dir = vec2(cos(angle), sin(angle));
		float proj = dot(uv_c, dir);
		float perp = abs(length(uv_c - dir * max(proj, 0.0)));
		float jagged = texture(noise_tex, vec2(proj * 8.0 + t * 0.5 + fi * 0.7, fi * 0.5)).r;
		perp += (jagged - 0.5) * 0.04;
		float bolt = exp(-perp * (160.0 + energy * 80.0)) * 0.020;
		bolt *= smoothstep(0.0, 0.05, proj) * smoothstep(0.6, 0.05, proj);
		lightning += bolt;
	}
	lightning *= (0.4 + energy * 2.5) * activity;
	overlay += vec3(0.2, 0.9, 0.3) * lightning * 1.4;  // green roots
	overlay += vec3(0.9, 0.7, 0.1) * lightning * kick * 1.0;  // gold on kick

	// ── 3b. Pulsing sacred breath rings ──────────────────────────────
	float rings = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float ring_r = 0.06 + fi * 0.07 + energy * 0.03 + sub_bass * 0.02;
		float ring = exp(-abs(r - ring_r) * (80.0 + bass * 40.0)) * 0.012;
		ring *= 0.7 + 0.3 * sin(ang * 6.0 + fi * 1.5 + t * 0.2);
		rings += ring;
	}
	vec3 ring_col = palette(r * 2.0 + t * 0.03,
		vec3(0.15 + warmth * 0.2, 0.45, 0.35 + brightness * 0.1));
	overlay += ring_col * rings * (0.8 + beat_confidence * 0.6);

	// ── 3c. Sri Yantra spiral vortex ─────────────────────────────────
	float arms = floor(6.0 + bass * 3.0);
	float spiral = sin(ang * arms + r * 18.0 - t * 3.0 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 4.0);
	spiral *= 0.015 * (0.3 + energy);
	spiral *= smoothstep(0.0, 0.1, r) * smoothstep(0.85, 0.15, r);
	overlay += vec3(0.05, 0.9, 0.3) * spiral * 1.8;  // emerald spiral
	overlay += vec3(0.9, 0.6, 0.05) * spiral * 0.9;

	// ── 3d. Metatron's Cube mandala — seed of life circles ───────────
	float mandala = 0.0;
	float mr = 0.15 + energy * 0.04 + sub_bass * 0.03;

	// Center circle
	mandala += exp(-abs(r - mr * 0.33) * (120.0 + bass * 40.0)) * 0.012;

	// 6 inner circles + radial lines
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.035;
		vec2 cp = vec2(cos(angle), sin(angle)) * mr;
		float d = abs(length(uv_c - cp) - mr);
		mandala += exp(-d * (100.0 + bass * 40.0)) * 0.010;

		// Radial line: center → node
		vec2 nd = normalize(cp);
		float proj_l = dot(uv_c, nd);
		float perp_l = length(uv_c - nd * clamp(proj_l, 0.0, mr));
		mandala += exp(-perp_l * (200.0 + energy * 80.0)) * 0.005
		          * smoothstep(0.0, 0.02, proj_l) * smoothstep(mr * 1.05, mr * 0.5, proj_l);
	}

	// 6 outer circles
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + PI / 6.0 + t * 0.035;
		vec2 cp = vec2(cos(angle), sin(angle)) * mr * 2.0;
		float d = abs(length(uv_c - cp) - mr);
		mandala += exp(-d * (80.0 + bass * 30.0)) * 0.007;

		// Connecting lines: inner → outer
		vec2 inner_p = vec2(cos(angle - PI / 6.0), sin(angle - PI / 6.0)) * mr;
		vec2 dir_ln = normalize(cp - inner_p);
		float proj_ln = dot(uv_c - inner_p, dir_ln);
		float perp_ln = length(uv_c - inner_p - dir_ln * clamp(proj_ln, 0.0, length(cp - inner_p)));
		mandala += exp(-perp_ln * (180.0 + energy * 60.0)) * 0.004;
	}

	// Containment circles
	mandala += exp(-abs(r - mr * 2.2) * (60.0 + energy * 25.0)) * 0.006;
	mandala += exp(-abs(r - mr * 3.0) * (40.0 + energy * 15.0)) * 0.004;

	vec3 met_col = vec3(0.9, 0.7, 0.1);  // sacred gold
	met_col = mix(met_col, vec3(0.9, 0.4, 0.1), warmth * 0.4);
	overlay += met_col * mandala * (1.0 + beat_confidence * 0.6);

	// ── 3e. Sri Yantra triangle overlay ──────────────────────────────
	float sri_overlay = 0.0;

	// 4 upward triangles (Shiva)
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float sc = 0.35 - fi * 0.07;
		float a_off = t * 0.02 + fi * 0.005;
		for (int vi = 0; vi < 3; vi++) {
			float v = float(vi);
			float va = a_off + v * TAU / 3.0 + PI / 2.0;
			float va2 = a_off + (v + 1.0) * TAU / 3.0 + PI / 2.0;
			vec2 tv0 = vec2(cos(va), sin(va)) * sc;
			vec2 tv1 = vec2(cos(va2), sin(va2)) * sc;
			vec2 dir_e = tv1 - tv0;
			float proj_e = dot(uv_c - tv0, dir_e) / dot(dir_e, dir_e);
			float perp_e = length(uv_c - tv0 - dir_e * clamp(proj_e, 0.0, 1.0));
			sri_overlay += exp(-perp_e * (160.0 + bass * 50.0)) * 0.006;
		}
	}

	// 5 downward triangles (Shakti)
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float sc = 0.32 - fi * 0.055;
		float a_off = -t * 0.015 - fi * 0.004;
		for (int vi = 0; vi < 3; vi++) {
			float v = float(vi);
			float va = a_off + v * TAU / 3.0 - PI / 2.0;
			float va2 = a_off + (v + 1.0) * TAU / 3.0 - PI / 2.0;
			vec2 tv0 = vec2(cos(va), sin(va)) * sc;
			vec2 tv1 = vec2(cos(va2), sin(va2)) * sc;
			vec2 dir_e = tv1 - tv0;
			float proj_e = dot(uv_c - tv0, dir_e) / dot(dir_e, dir_e);
			float perp_e = length(uv_c - tv0 - dir_e * clamp(proj_e, 0.0, 1.0));
			sri_overlay += exp(-perp_e * (160.0 + bass * 50.0)) * 0.006;
		}
	}

	// Bindu glow
	float bindu_glow = exp(-r * (100.0 + energy * 50.0)) * 0.018;
	sri_overlay += bindu_glow;

	vec3 sri_col = vec3(0.1, 0.85, 0.3);
	sri_col = mix(sri_col, vec3(0.9, 0.2, 0.4), warmth * 0.3);
	overlay += sri_col * sri_overlay * (0.8 + beat_confidence * 0.6);

	// ── 3f. Neon sacred scan lines ───────────────────────────────────
	float scan = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float y = 0.25 + fi * 0.17 + sin(t * (0.1 + fi * 0.05)) * 0.06;
		float d = abs(uv.y - y);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.007;
	}
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float x = 0.3 + fi * 0.2 + cos(t * (0.08 + fi * 0.04)) * 0.05;
		float d = abs(uv.x - x);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.006;
	}
	scan *= activity;
	overlay += vec3(0.0, 0.9, 0.5) * scan * 1.6;
	overlay += vec3(0.9, 0.7, 0.0) * scan * 0.7;

	// ── 3g. Microscopic organisms — sacred pollen ────────────────────
	float organisms = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		vec2 pos = vec2(
			0.5 + sin(t * 0.05 + fi * 2.7) * 0.40,
			0.5 + cos(t * 0.04 + fi * 1.9) * 0.40
		);
		vec2 to_org = uv - pos;
		float r_org = length(to_org);
		float angle = atan(to_org.y, to_org.x);
		float blob_r = 0.018 + 0.006 * sin(angle * 3.0 + t * 0.4 + fi)
				   + 0.004 * sin(angle * 5.0 - t * 0.25 + fi * 2.0);
		blob_r *= 1.0 + energy * 0.6;
		float blob = smoothstep(blob_r + 0.005, blob_r * 0.2, r_org);
		organisms += blob * (0.08 + 0.12 * (sin(t * 0.2 + fi * 1.3) * 0.5 + 0.5));
	}
	overlay += vec3(0.0, 0.9, 0.4) * organisms * 0.50;
	overlay += vec3(0.85, 0.7, 0.0) * organisms * 0.25;

	// ── 3h. Cellular division — voronoi membranes ────────────────────
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
	float cell_edge = exp(-membrane * 18.0) * 0.018;
	overlay += vec3(0.1, 0.8, 0.3) * cell_edge * 1.6;
	overlay += vec3(0.7, 0.5, 0.0) * cell_edge * 0.6;

	// ── 3i. Liquid gold highlights ───────────────────────────────────
	float gold_drop = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(t * 0.03 + fi * 3.14) * 0.30,
			0.5 + cos(t * 0.025 + fi * 2.72) * 0.30
		);
		float mr2 = length(uv - mc);
		float mb = exp(-mr2 * mr2 * (35.0 + energy * 25.0));
		gold_drop += pow(max(mb, 0.0), 3.0);
	}
	overlay += vec3(0.9, 0.7, 0.1) * gold_drop * 0.25;
	overlay += vec3(0.1, 0.8, 0.3) * gold_drop * 0.10;

	// ── 3j. Fibonacci spiral arms ────────────────────────────────────
	float phi = 1.61803398875;
	float fib = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float spiral_angle = ang + log(max(r, 0.001)) / log(phi) * 4.0 - t * 0.5 + fi * TAU / 6.0;
		float spiral_line = abs(sin(spiral_angle));
		spiral_line = pow(max(1.0 - spiral_line, 0.0), 6.0);
		spiral_line *= 0.014 * (0.3 + energy);
		spiral_line *= smoothstep(0.0, 0.08, r) * smoothstep(0.75, 0.12, r);
		fib += spiral_line;
	}
	overlay += vec3(0.85, 0.65, 0.05) * fib * 1.5;
	overlay += vec3(0.15, 0.6, 0.2) * fib * 0.8;

	// ── 3k. Flower of Life — nested vesica piscis arcs ───────────────
	float flower = 0.0;
	float fr = 0.10 + energy * 0.03;
	// Center
	flower += exp(-abs(r - fr) * (150.0 + bass * 50.0)) * 0.008;
	// 6 petals around center
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float fa = fi * TAU / 6.0 + t * 0.025;
		vec2 fc = vec2(cos(fa), sin(fa)) * fr;
		float fd = abs(length(uv_c - fc) - fr);
		flower += exp(-fd * (150.0 + bass * 50.0)) * 0.008;
	}
	// Second ring: 12 petals
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float fa = fi * TAU / 12.0 + t * 0.02;
		vec2 fc = vec2(cos(fa), sin(fa)) * fr * 2.0;
		float fd = abs(length(uv_c - fc) - fr);
		flower += exp(-fd * (100.0 + energy * 40.0)) * 0.005;
	}
	overlay += vec3(0.7, 0.5, 0.05) * flower * 1.2;
	overlay += vec3(0.1, 0.7, 0.25) * flower * 0.6;

	// ── 3l. Onset shockwave ──────────────────────────────────────────
	float shock_phase = fract(beat_phase);
	float shock_r = shock_phase * 0.55;
	float shock_w = 0.025 + (1.0 - shock_phase) * 0.035;
	float shock = exp(-pow((r - shock_r) / shock_w, 2.0)) * onset * 0.05;
	overlay += vec3(0.15, 0.9, 0.35) * shock;
	overlay += vec3(0.95, 0.7, 0.1) * shock * kick * 1.5;

	// ── 3m. Energy tendrils — noise-based root branching ─────────────
	float tendrils = 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float angle = fi * TAU / 8.0 + t * 0.02;
		vec2 dir = vec2(cos(angle), sin(angle));
		float proj = dot(uv_c, dir);
		float perp = length(uv_c - dir * max(proj, 0.0));
		float noise_v = texture(noise_tex, vec2(proj * 3.0 + t * 0.08 + fi * 0.45, fi * 0.37)).r;
		float branch = exp(-perp * (22.0 + noise_v * 35.0)) * noise_v * 0.014;
		branch *= smoothstep(0.0, 0.06, proj) * smoothstep(0.65, 0.08, proj);
		tendrils += branch;
	}
	tendrils *= (0.5 + energy * 2.0) * activity;
	overlay += vec3(0.4, 0.25, 0.05) * tendrils * 1.2;
	overlay += vec3(0.15, 0.7, 0.15) * tendrils * 0.6;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 4: COMPOSITE — trail + new geometry (additive like phantom_star)
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;

	// Deep earth void background
	new_col += mix(vec3(0.01, 0.005, 0.0), vec3(0.0, 0.01, 0.005), uv.y);

	// Additive composite — trails layer under new geometry
	vec3 col = trail + new_col;
	col = col / (1.0 + col * loop_reinhard);

	COLOR = vec4(col, 1.0);
}
