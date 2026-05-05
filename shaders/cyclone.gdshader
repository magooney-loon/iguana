shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Cyclone
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   IFS spiral cyclone with domain-warped sine arms
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.3
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.30
//  @grain_strength: 0.006
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Original tweet-shader by XorDev — a 10-iteration IFS spiral.
//  Each step rotates coordinates by ~-36.87° (mat2 with cos=0.8,
//  sin=-0.6), creating the cyclone pattern. Domain warping via
//  sin(p + sin(p+t).yx) feeds each axis's sine into the other,
//  producing organic flowing spiral arms colored by cosine phases.
//  Adapted to the Iguana feedback pipeline with audio-reactive
//  spiral tightness, warp speed, and color shifting.
//
//  Decompressed algorithm:
//    p = (fragCoord*2 - resolution) / resY / 0.1    // centered UV ×10
//    for 10 iterations:
//      p *= 0.1 * mat2(8,-6,6,8)                    // rotate ~-36.87°
//      glow += cos(p.x + phase) / |domain_warp(p,t)| / 0.2
//    output = tanh(glow / scale)
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

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
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

	float zoom = 0.993 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;
	warped = rot2(0.003 + bass * 0.005) * warped;

	vec2 warp = vec2(
		sin(warped.y * 6.0 + t * 0.9) * 0.006,
		cos(warped.x * 5.0 + t * 1.1) * 0.006
	);
	warp *= 1.0 + bass * 2.0 + energy * 1.5;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Cyclone ────────────────────────────────────────

	// Centered UV scaled ×10
	// Original: (FC.xy*2 - r) / r.y / 0.1
	vec2 p = vec2((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0) * 10.0;

	// Spiral rotation — original 0.1*mat2(8,-6,6,8) is a pure rotation
	// cos(θ)=0.8, sin(θ)=-0.6, θ≈-36.87° = -0.6435 rad
	// Bass tightens/loosens the spiral
	float spiral_angle = -0.6435 + bass * 0.15;
	float cs = cos(spiral_angle);
	float sn = sin(spiral_angle);
	mat2 spiral_mat = mat2(vec2(cs, sn), vec2(-sn, cs));

	// Kick adds slight zoom per iteration
	float spiral_zoom = 1.0 + kick * 0.03;

	// Color phase — warmth shifts red, brightness shifts blue
	vec3 color_phase = vec3(2.0 + warmth * 0.5, 1.0, brightness * 0.3);

	// Time speed — energy accelerates the domain warping
	float t_speed = t * (1.0 + energy * 0.3);

	// Structure brightness — treble sharpens the sine detail
	float struct_scale = 0.2 - treble * 0.05;

	// IFS iteration — 10 rotations with glow accumulation
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 10; i++) {
		// Rotate coordinates (body runs before accumulation)
		p = p * spiral_mat * spiral_zoom;

		// Domain warping: sin(p + sin(p+t).yx)
		// Each axis feeds the other's sine — organic flowing arms
		vec2 warp_src = sin(p + t_speed);
		vec2 domain = sin(p + warp_src.yx);
		float structure = max(length(domain), 0.001);

		// Accumulate — cosine coloring, inverse-structure intensity
		vec3 color = (cos(p.x + color_phase) + 1.0) / structure / max(struct_scale, 0.05);
		glow += color;
	}

	// Tanh tonemapping — scale keeps per-frame output low enough that
	// feedback equilibrium stays ≤ 1.0.  See README § Feedback Brightness.
	float glow_scale = max(300.0 - energy * 100.0, 100.0);
	vec3 new_col = tanh(glow / glow_scale);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.93 + energy * 0.03;
	float emission = 0.10 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
