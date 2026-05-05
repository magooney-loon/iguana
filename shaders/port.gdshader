shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Port
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Fractal portal raymarch with curl-noise detail
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.4
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.30
//  @grain_strength: 0.006
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Original tweet-shader by XorDev — a 100-step raymarch through
//  a portal defined by length(cos(p.xz))-0.4, with 5 iterations of
//  curl-noise-like fractal refinement per step. The inner loop
//  displaces w via sin(w.zxy*f - 9*exp(-d/0.1) + t)/f, adding
//  harmonic detail that intensifies near the surface (where d is
//  small, exp(-d/0.1) approaches 1). Glow accumulates from the
//  y-component of the blended position mix(p,w,0.1), creating
//  colored horizontal bands through the portal.
//  Adapted to the Iguana feedback pipeline with audio-reactive
//  fractal detail, portal size, and warp speed.
//
//  Decompressed algorithm:
//    rdir = (fragCoord*2 - resolution) / resY    // unnormalized ray
//    for 100 steps:
//      p = z * rdir + vec3(1)                    // position along ray
//      for 5 fractal iters:
//        w += sin(w.zxy * f - 9*exp(-d/0.1) + t) / f  // curl detail
//      glow += 0.03 / |mix(p,w,0.1).y + color_offset| * d
//      d = 0.3 * (length(cos(p.xz)) - 0.4)      // portal SDF
//      z += d
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

	// ── 1. FEEDBACK — portal pulls inward ───────────────────────────
	// Fast zoom (portal sucks you in), minimal rotation (axial structure),
	// vertical-biased warp (the portal bands are horizontal).

	float zoom = 0.970 - sub_bass * 0.015 - onset * 0.01;
	vec2 warped = center * zoom;
	warped = rot2(0.001 + energy * 0.002) * warped;  // barely rotate

	vec2 warp = vec2(
		sin(warped.y * 10.0 + t * 1.5) * 0.004,   // vertical emphasis
		cos(warped.y *  4.0 + t * 0.6) * 0.008
	);
	warp *= 1.0 + kick * 2.0 + energy * 1.0;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Port ───────────────────────────────────────────

	// Unnormalized ray direction
	// Original: (FC.rgb*2 - r.xyy) / r.y
	vec3 rdir = vec3((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0, -1.0);

	// Audio-reactive — keep it minimal, let the original character through
	float portal_size = 0.4 - kick * 0.08;              // kick opens portal
	float t_speed     = t * (1.0 + energy * 0.3);       // energy speeds fractal

	// Raymarch — 100 steps
	float z = 0.0;
	float d = 0.1;  // initial step
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 100; i++) {
		// Position along ray (unnormalized direction)
		vec3 p = z * rdir + vec3(1.0);

		// Fractal refinement — 5 iterations of curl-like displacement
		// Detail concentrates near the surface: exp(-d/0.1) → ~1 when d small
		vec3 w = p;
		for (int fi = 0; fi < 5; fi++) {
			float f = float(fi + 1);
			w += sin(w.zxy * f - 9.0 * exp(-d / 0.1) + t_speed) / f;
		}

		// Glow from blended y-position — original: 0.03/abs(mix(p,w,.1).y + vec4(0,1,2,3)/1e2)*d
		vec3 band_y = mix(p, w, 0.1).y + vec3(0.0, 0.01, 0.02);
		glow += 0.03 / max(abs(band_y), 0.001) * d;

		// Portal SDF: length(cos(p.xz)) - portal_size
		// Creates infinite cylindrical openings along Y
		d = 0.3 * (length(cos(p.xz)) - portal_size);

		// Advance
		z += d;
	}

	// Original: tanh(o) with no scaling — glow values are naturally ~0.3-20
	vec3 new_col = tanh(glow);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	// Shorter trails keep the portal structure clean
	float decay = 0.88 + energy * 0.06;
	// emission 0.07 keeps equilibrium at 1.0 for bright (tanh≈1) pixels:
	//   0.07 * 1.0 / (1 - 0.88) = 0.07 / 0.12 ≈ 0.58
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
