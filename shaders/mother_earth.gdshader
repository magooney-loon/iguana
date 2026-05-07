shader_type canvas_item;

//  @name:          Mother Earth
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Agressive sacred geometry phantom witness fly-through
//
//  @exposure:       3.00
//  @tonemap_knee:   0.0
//  @gamma:          2.69
//  @vignette_dark:  0.00
//  @grain_strength: 0.01
//  @loop_reinhard:  2.05
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
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.77;

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

vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

// ── SDF primitives ──────────────────────────────────────────────────
float sd_capsule(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// ── Metatron's Cube — hex-folded for speed ──────────────────────────
// pmod folds XY into a 60° wedge; only 6 SDF primitives needed
// instead of ~55. Unfolds to full 13-node + strut pattern via glow.
float metatron(vec3 p) {
	vec2 fp = pmod(p.xy, 6.0);
	vec3 pf = vec3(fp, p.z);
	float d = 1e10;
	float nr = 0.1 + bass * 0.04;
	float sr = 0.025 + sub_bass * 0.01;

	// Center node
	d = min(d, length(fp) - nr);

	// Inner ring node — all 6 fold to (1, 0)
	vec3 n1 = vec3(1.0, 0.0, 0.0);
	d = min(d, length(fp - n1.xy) - nr);

	// Outer ring node — all 6 fold to (1.732, -1.0)
	vec3 n2 = vec3(1.732, -1.0, 0.0);
	d = min(d, length(fp - n2.xy) - nr);

	// Strut: center → inner
	d = min(d, sd_capsule(pf, vec3(0.0), n1, sr));

	// Strut: inner → outer
	d = min(d, sd_capsule(pf, n1, n2, sr));

	// Hex edge stub: inner → sector boundary (suggests hex ring)
	vec3 n_edge = vec3(0.5, 0.866, 0.0);
	d = min(d, sd_capsule(pf, n1, n_edge, sr * 0.8));

	return d;
}

// ── Sri Yantra — reduced to 4 key triangles ─────────────────────────
float tri_outline(vec2 p, float sc, bool up) {
	float s = up ? 1.0 : -1.0;
	vec2 v0 = vec2(0.0, s * sc);
	vec2 v1 = vec2(-sc * 0.866, -s * sc * 0.5);
	vec2 v2 = vec2( sc * 0.866, -s * sc * 0.5);
	float d = 1e10;
	vec2 pts[3] = vec2[3](v0, v1, v2);
	vec2 pts2[3] = vec2[3](v1, v2, v0);
	for (int j = 0; j < 3; j++) {
		vec2 pa = p - pts[j], ba = pts2[j] - pts[j];
		float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		d = min(d, length(pa - ba * h));
	}
	float thick = 0.035 + mid * 0.015;
	return abs(d) - thick;
}

float sri_yantra(vec2 p) {
	float d = 1e10;
	// 2 upward (largest Shiva triangles)
	d = min(d, tri_outline(p, 1.0, true));
	d = min(d, tri_outline(p, 0.6, true));
	// 2 downward (largest Shakti triangles)
	d = min(d, tri_outline(p, 0.9, false));
	d = min(d, tri_outline(p, 0.5, false));
	// Bindu + outer ring
	d = min(d, abs(length(p) - 0.06) - 0.015);
	d = min(d, abs(length(p) - 1.08) - 0.01);
	return d;
}

// ── Scene map — tiled infinite sacred geometry ───────────────────────
float map(vec3 p) {
	// Metatron layer — tile Z, rotate XY
	vec3 p1 = p;
	p1.z = mod(p1.z, 12.0) - 6.0;
	p1.xy *= rot(time_val * 0.15);
	float met = metatron(p1);

	// Sri Yantra layer — offset Z, counter-rotate
	vec3 p2 = p;
	p2.z = mod(p2.z + 6.0, 12.0) - 6.0;
	p2.xy *= rot(-time_val * 0.1);
	float sri = sri_yantra(p2.xy);
	float yz = abs(p2.z);
	sri = max(sri, yz - 0.15 - bass * 0.05);

	return min(met, sri);
}

void fragment() {
	vec2 uv = UV;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 1: FEEDBACK LOOP
	// ══════════════════════════════════════════════════════════════════
	vec2 center = uv - 0.5;
	center.x *= rect_size.x / rect_size.y;

	float zoom = 0.970 - sub_bass * 0.014 + onset * 0.010;
	center *= zoom;

	float rot_a = 0.005 + energy * 0.007 + beat * 0.004;
	center = rot(rot_a) * center;

	vec2 feedback_uv = center;
	feedback_uv.x /= (rect_size.x / rect_size.y);
	feedback_uv += 0.5;

	vec2 warp = vec2(
		sin(center.y * 10.0 + t * 1.4) * 0.012,
		cos(center.x * 8.0  + t * 1.1) * 0.012
	);
	warp *= 1.0 + bass * 2.5 + energy * 1.5;

	vec2 sample_uv = feedback_uv + warp;
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	float ca = 0.0012 + energy * 0.0012;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca, 0.0)).r;
	trail.g = texture(prev_frame, sample_uv).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca, 0.0)).b;
	trail *= (0.92 + energy * 0.04) * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  PHASE 2: RAYMARCHING — phantom sacred geometry fly-through
	// ══════════════════════════════════════════════════════════════════
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (uv * 2.0 - 1.0) * (rect_size / min_dim);

	vec3 c_pos = vec3(0.0, 0.0, -3.0 * t);
	vec3 c_dir = normalize(vec3(0.0, 0.0, -1.0));
	vec3 c_up = vec3(sin(t * 0.08), 1.0, sin(t * 0.05) * 0.3);
	vec3 c_side = cross(c_dir, c_up);
	vec3 ray = normalize(c_side * p.x + c_up * p.y + c_dir);

	float acc = 0.0;
	float acc2 = 0.0;
	float march_t = 0.0;
	float focal_dist = 4.0 + sin(t * 0.08) * 1.5;
	float glow_falloff = 3.5 + energy * 4.0;

	for (int i = 0; i < 64; i++) {
		if (march_t > 20.0) break;
		vec3 pos = c_pos + ray * march_t;
		float dist = map(pos);
		dist = max(abs(dist), 0.02);

		float dof = exp(-pow((march_t - focal_dist) * 0.15, 2.0));
		float a = exp(-dist * glow_falloff) * mix(0.35, 1.0, dof);

		float phantom_phase = mod(length(pos) + 24.0 * t, 30.0);
		if (phantom_phase < 3.0) {
			a *= 2.0;
			acc2 += a;
		}

		acc += a;
		march_t += dist * 0.5;
	}

	float lum = acc * 0.005;
	float ghost = acc2 * 0.008;

	// High channel separation — prevents muddy gray, keeps colors vivid
	vec3 rm_col = vec3(
		lum * (0.5  + bass * 0.9  + kick * 1.5),
		lum * (0.04 + mid  * 0.3) + ghost * (0.0 + energy * 0.6),
		lum * (0.6  + treble * 0.8) + ghost * 0.15
	);

	// Phantom pulses — vivid emerald / gold, not pastel
	rm_col += vec3(0.0, 1.0, 0.25) * ghost * (1.0 + energy * 0.8);
	rm_col += vec3(1.0, 0.8, 0.0)  * ghost * warmth * 0.7;

	// Hue rotation — earth-biased but still saturated
	float hue = beat_phase * TAU + t * 0.06;
	vec3 hue_col = vec3(
		0.5 + 0.5 * sin(hue),
		0.5 + 0.5 * sin(hue + 2.09),
		0.5 + 0.5 * sin(hue + 4.19)
	);
	rm_col += hue_col * lum * (0.25 + energy * 0.3);

	// Percussion — pure saturated hues, no cross-contamination
	rm_col += vec3(1.0, 0.35, 0.0)  * acc  * 0.016 * kick;
	rm_col += vec3(0.95, 0.0, 0.45) * acc2 * 0.018 * snare;
	rm_col += vec3(0.2, 1.0, 0.3)   * acc  * 0.009 * hihat;

	// Onset — sharp gold flash, not white
	rm_col += vec3(1.0, 0.75, 0.05) * onset * 0.40;
	rm_col += vec3(0.0, 0.8, 0.2)   * onset * onset * 0.22;

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
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float angle = fi * TAU / 5.0 + t * 0.03;
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
	overlay += vec3(0.2, 0.9, 0.3) * lightning * 1.4;
	overlay += vec3(0.9, 0.7, 0.1) * lightning * kick;

	// ── 3b. Sacred breath rings ──────────────────────────────────────
	float rings = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ring_r = 0.06 + fi * 0.08 + energy * 0.03;
		float ring = exp(-abs(r - ring_r) * (80.0 + bass * 40.0)) * 0.012;
		ring *= 0.7 + 0.3 * sin(ang * 6.0 + fi * 1.5 + t * 0.2);
		rings += ring;
	}
	vec3 ring_col = palette(r * 2.0 + t * 0.03,
		vec3(0.15 + warmth * 0.2, 0.45, 0.35));
	overlay += ring_col * rings * (0.8 + beat_confidence * 0.6);

	// ── 3c. Spiral vortex arms ───────────────────────────────────────
	float arms = floor(6.0 + bass * 3.0);
	float spiral = sin(ang * arms + r * 18.0 - t * 3.0 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 4.0);
	spiral *= 0.015 * (0.3 + energy);
	spiral *= smoothstep(0.0, 0.1, r) * smoothstep(0.85, 0.15, r);
	overlay += vec3(0.05, 0.9, 0.3) * spiral * 1.8;
	overlay += vec3(0.9, 0.6, 0.05) * spiral * 0.9;

	// ── 3d. Metatron mandala — seed of life ──────────────────────────
	float mandala = 0.0;
	float mr = 0.15 + energy * 0.04 + sub_bass * 0.03;

	mandala += exp(-abs(r - mr * 0.33) * (120.0 + bass * 40.0)) * 0.012;

	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.035;
		vec2 cp = vec2(cos(angle), sin(angle)) * mr;
		float d = abs(length(uv_c - cp) - mr);
		mandala += exp(-d * (100.0 + bass * 40.0)) * 0.010;

		vec2 nd = normalize(cp);
		float proj_l = dot(uv_c, nd);
		float perp_l = length(uv_c - nd * clamp(proj_l, 0.0, mr));
		mandala += exp(-perp_l * (200.0 + energy * 80.0)) * 0.005
		          * smoothstep(0.0, 0.02, proj_l) * smoothstep(mr * 1.05, mr * 0.5, proj_l);
	}

	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + PI / 6.0 + t * 0.035;
		vec2 cp = vec2(cos(angle), sin(angle)) * mr * 2.0;
		float d = abs(length(uv_c - cp) - mr);
		mandala += exp(-d * (80.0 + bass * 30.0)) * 0.007;

		vec2 inner_p = vec2(cos(angle - PI / 6.0), sin(angle - PI / 6.0)) * mr;
		vec2 dir_ln = normalize(cp - inner_p);
		float proj_ln = dot(uv_c - inner_p, dir_ln);
		float perp_ln = length(uv_c - inner_p - dir_ln * clamp(proj_ln, 0.0, length(cp - inner_p)));
		mandala += exp(-perp_ln * (180.0 + energy * 60.0)) * 0.004;
	}

	mandala += exp(-abs(r - mr * 2.2) * (60.0 + energy * 25.0)) * 0.006;
	mandala += exp(-abs(r - mr * 3.0) * (40.0 + energy * 15.0)) * 0.004;

	vec3 met_col = vec3(0.9, 0.7, 0.1);
	met_col = mix(met_col, vec3(0.9, 0.4, 0.1), warmth * 0.4);
	overlay += met_col * mandala * (1.0 + beat_confidence * 0.6);

	// ── 3e. Sri Yantra triangle overlay ──────────────────────────────
	float sri_overlay = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float sc = 0.35 - fi * 0.12;
		float a_off = t * 0.02 + fi * 0.01;
		for (int vi = 0; vi < 3; vi++) {
			float v = float(vi);
			float va = a_off + v * TAU / 3.0 + PI / 2.0;
			float va2 = a_off + (v + 1.0) * TAU / 3.0 + PI / 2.0;
			vec2 tv0 = vec2(cos(va), sin(va)) * sc;
			vec2 tv1 = vec2(cos(va2), sin(va2)) * sc;
			vec2 dir_e = tv1 - tv0;
			float proj_e = dot(uv_c - tv0, dir_e) / dot(dir_e, dir_e);
			float perp_e = length(uv_c - tv0 - dir_e * clamp(proj_e, 0.0, 1.0));
			sri_overlay += exp(-perp_e * (160.0 + bass * 50.0)) * 0.007;
		}
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float sc = 0.30 - fi * 0.10;
		float a_off = -t * 0.015 - fi * 0.008;
		for (int vi = 0; vi < 3; vi++) {
			float v = float(vi);
			float va = a_off + v * TAU / 3.0 - PI / 2.0;
			float va2 = a_off + (v + 1.0) * TAU / 3.0 - PI / 2.0;
			vec2 tv0 = vec2(cos(va), sin(va)) * sc;
			vec2 tv1 = vec2(cos(va2), sin(va2)) * sc;
			vec2 dir_e = tv1 - tv0;
			float proj_e = dot(uv_c - tv0, dir_e) / dot(dir_e, dir_e);
			float perp_e = length(uv_c - tv0 - dir_e * clamp(proj_e, 0.0, 1.0));
			sri_overlay += exp(-perp_e * (160.0 + bass * 50.0)) * 0.007;
		}
	}

	float bindu_glow = exp(-r * (100.0 + energy * 50.0)) * 0.018;
	sri_overlay += bindu_glow;

	vec3 sri_col = vec3(0.1, 0.85, 0.3);
	sri_col = mix(sri_col, vec3(0.9, 0.2, 0.4), warmth * 0.3);
	overlay += sri_col * sri_overlay * (0.8 + beat_confidence * 0.6);

	// ── 3f. Neon sacred scan lines ───────────────────────────────────
	float scan = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float y = 0.25 + fi * 0.22 + sin(t * (0.1 + fi * 0.05)) * 0.06;
		float d = abs(uv.y - y);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.007;
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float x = 0.3 + fi * 0.3 + cos(t * (0.08 + fi * 0.04)) * 0.05;
		float d = abs(uv.x - x);
		scan += exp(-d * (280.0 + energy * 120.0)) * 0.006;
	}
	scan *= activity;
	overlay += vec3(0.0, 0.9, 0.5) * scan * 1.6;
	overlay += vec3(0.9, 0.7, 0.0) * scan * 0.7;

	// ── 3g. Sacred pollen organisms ──────────────────────────────────
	float organisms = 0.0;
	for (int i = 0; i < 8; i++) {
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

	// ── 3h. Liquid gold highlights ───────────────────────────────────
	float gold_drop = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 mc = vec2(
			0.5 + sin(t * 0.03 + fi * 3.14) * 0.30,
			0.5 + cos(t * 0.025 + fi * 2.72) * 0.30
		);
		float mr2 = length(uv - mc);
		float mb = exp(-mr2 * mr2 * (35.0 + energy * 25.0));
		gold_drop += mb * mb * mb;
	}
	overlay += vec3(0.9, 0.7, 0.1) * gold_drop * 0.25;
	overlay += vec3(0.1, 0.8, 0.3) * gold_drop * 0.10;

	// ── 3i. Flower of Life arcs ──────────────────────────────────────
	float flower = 0.0;
	float fr = 0.10 + energy * 0.03;
	flower += exp(-abs(r - fr) * (150.0 + bass * 50.0)) * 0.008;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float fa = fi * TAU / 6.0 + t * 0.025;
		vec2 fc = vec2(cos(fa), sin(fa)) * fr;
		float fd = abs(length(uv_c - fc) - fr);
		flower += exp(-fd * (150.0 + bass * 50.0)) * 0.008;
	}
	overlay += vec3(0.7, 0.5, 0.05) * flower * 1.2;
	overlay += vec3(0.1, 0.7, 0.25) * flower * 0.6;

	// ── 3j. Onset shockwave ──────────────────────────────────────────
	float shock_phase = fract(beat_phase);
	float shock_r = shock_phase * 0.55;
	float shock_w = 0.025 + (1.0 - shock_phase) * 0.035;
	float shock = exp(-pow((r - shock_r) / shock_w, 2.0)) * onset * 0.05;
	overlay += vec3(0.15, 0.9, 0.35) * shock;
	overlay += vec3(0.95, 0.7, 0.1) * shock * kick * 1.5;

	// ── 3k. Energy tendrils ──────────────────────────────────────────
	float tendrils = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float angle = fi * TAU / 6.0 + t * 0.02;
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
	//  PHASE 4: COMPOSITE
	// ══════════════════════════════════════════════════════════════════
	vec3 new_col = rm_col + overlay;
	new_col += mix(vec3(0.01, 0.005, 0.0), vec3(0.0, 0.01, 0.005), uv.y);

	// Hybrid composite — trail modulates new_col instead of stacking additively.
	// Pure `trail + new_col` blows out at low reinhard; this keeps trails visible
	// without double-counting brightness.
	float trail_lum = dot(trail, vec3(0.299, 0.587, 0.114));
	vec3 col = new_col * (1.0 + trail_lum * 0.9) + trail * 0.20;

	// Tonemap
	col = col / (1.0 + col * loop_reinhard);

	// Post-tonemap saturation boost — Reinhard desaturates; counteract it
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(gray), col, 1.55);

	// Final clamp for safety
	col = clamp(col, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
