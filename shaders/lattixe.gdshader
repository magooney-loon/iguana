shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Lattixe
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Voronoi crystal lattice. Cells breathe with reactivity.
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       0.86
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.00
//  @grain_strength: 0.01
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Algorithm:
//    Voronoi with animated cell centers (Lissajous-phase hash offsets).
//    Each fragment finds its two nearest cell centers to compute d1
//    (interior distance) and edge_dist = d2 - d1 (boundary proximity).
//    Interior glows with sub_bass; edges ignite with treble/presence.
//    A radial ripple term rides the kick. Colors use a cosine palette
//    keyed on d1 so neighboring cells get distinct hues.
//    Feedback uses pure zoom + wave-warp (no rotation) so trails
//    accumulate as expanding halos rather than spirals.
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

// ── Feedback loop ────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader Reinhard · tunable in Settings UI ────────────────────
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.0;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Constants ────────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helpers ──────────────────────────────────────────────────────────

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

// Low-cost hash: maps a cell grid coord to a pseudo-random vec2 in [0,1)
vec2 hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK ──────────────────────────────────────────────────
	// No rotation — avoids spiral buildup in trails.
	// Pure zoom + wave-warp so feedback halos expand outward uniformly.

	float zoom = 0.993 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;

	vec2 warp = vec2(
		sin(warped.y * 6.0 + t * 0.9) * 0.005,
		cos(warped.x * 5.0 + t * 1.1) * 0.005
	);
	warp *= 1.0 + bass * 1.5 + energy * 1.0;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb * edge_fade;

	// ── 2. GEOMETRY — Voronoi Lattice ─────────────────────────────────

	float dist_c = length(center);

	// Kick deforms space radially (shockwave expanding from origin)
	float kick_deform = kick * 0.3 * exp(-dist_c * 3.5);
	// Bass breathes cell size — low end makes cells bigger/smaller
	vec2 p = center * (1.0 + kick_deform) * (4.5 + bass * 2.0);

	// Cell animation speed — energy can push it slightly faster
	float t_anim = t * 0.35 + energy * 0.1;

	// ── Voronoi: 5×5 grid search ─────────────────────────────────────
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0, d2 = 8.0;

	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g  = vec2(float(i), float(j));
			vec2 h  = hash2(ip + g);
			// Each cell center traces its own Lissajous path
			vec2 o  = 0.5 + 0.45 * sin(t_anim + TAU * h);
			vec2 r  = g + o - fp;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; }
			else if (d < d2) { d2 = d; }
		}
	}

	d1 = sqrt(d1);
	d2 = sqrt(d2);
	float edge_dist = d2 - d1;  // approaches 0 at cell boundaries

	// ── Interior glow — sub_bass + beat breathe the cell bodies ──────
	float interior = exp(-d1 * 2.5) * (0.25 + sub_bass * 0.5 + beat * 0.2);

	// ── Edge glow — treble/presence/hihat ignite cell walls ──────────
	float edge_w = 0.06 + treble * 0.05;
	float edges  = (1.0 - smoothstep(0.0, edge_w, edge_dist))
	             * (0.65 + presence * 0.45 + hihat * 0.3 + snare * 0.2);

	// ── Concentric ripple radiating from center on kick ───────────────
	float ripple = sin(dist_c * 18.0 - t * 3.5 + kick * PI) * 0.5 + 0.5;
	ripple *= exp(-dist_c * 2.5) * (kick * 0.4 + bass * 0.1);

	// ── Color palette — cosine, keyed on cell seed via d1 ────────────
	float hue      = d1 * 3.5 + t * 0.12 + warmth;
	vec3 col_inner = cos(vec3(0.0, 2.094, 4.189) + hue) * 0.5 + 0.5;
	vec3 col_edge  = cos(vec3(0.8, 2.9, 5.0)    + hue + brightness * 1.5) * 0.5 + 0.5;

	// Snare: edges tint brighter but don't blow to white
	col_edge = mix(col_edge, vec3(1.0, 0.95, 0.8), snare * 0.3);

	vec3 new_col = col_inner * (interior + ripple) + col_edge * edges;

	// Kick center burst — warm flash from origin
	new_col += vec3(1.0, 0.75, 0.4) * kick * exp(-dist_c * 5.0) * 0.4;

	// Gentler tanh knee — keeps saturation without blowing to white
	new_col = tanh(new_col * 2.2);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.93 + energy * 0.03;
	float emission = 0.10 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
