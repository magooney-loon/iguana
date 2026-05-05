shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Scatter
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Scattered dot grid with animated wobble and glowing ring
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
//  Original tweet-shader by XorDev — a scattered dot grid with animated
//  wobble and a glowing ring. Grid cells are displaced by ceil()-snapped
//  coordinates with sine wobble, then per-cell tan() singularities
//  scatter some cells wildly. A double-tanh at radius 0.6 creates a
//  colored ring that varies by quadrant. Adapted to the Iguana feedback
//  pipeline with audio-reactive wobble, scatter, ring radius, and color.
//
//  Decompressed algorithm:
//    u = (resolution - 2 * fragCoord) / resolution.y  // centered UV
//    c = ceil((u*100 + sin(u*300 - t)) / (0.1+|u|))  // wobbled grid cell
//    p = u + 0.01 * tan(dot(c, sin(c.yx)))            // scattered offset
//    shaped = tanh(vec4(p-0.3, p))                     // soft color shape
//    ring = tanh(shaped * 0.1 / |length(p) - 0.6|)    // glowing ring
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

	// Zoom — subtle inward pull, onset = hard rush
	float zoom = 0.993 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;

	// Rotation — compounding spiral
	warped = rot2(0.003 + bass * 0.005) * warped;

	// Per-pixel warp field
	vec2 warp = vec2(
		sin(warped.y * 6.0 + t * 0.9) * 0.006,
		cos(warped.x * 5.0 + t * 1.1) * 0.006
	);
	warp *= 1.0 + bass * 2.0 + energy * 1.5;
	warped += warp;

	// Convert back to UV space for sampling
	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	// Edge fade
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Scatter ────────────────────────────────────────

	// Centered UV: original (r - 2*FC.xy) / r.y
	// In our coords: vec2((1-2*UV.x)*aspect, 1-2*UV.y)
	vec2 u = vec2((1.0 - 2.0 * uv.x) * aspect, 1.0 - 2.0 * uv.y);

	// Grid cell index with animated wobble
	// ceil() snaps to integer grid; sin() wobble makes cells drift
	float wobble_freq = 300.0 + energy * 100.0;
	float wobble_amp  = 1.0 + energy * 0.5;
	vec2 wobble = sin(u * wobble_freq - t * (1.0 + energy * 0.3) - kick * 3.0) * wobble_amp;
	vec2 c = ceil((u * 100.0 + wobble) / (0.1 + length(u)));

	// Per-cell scatter offset via tan() singularities
	// Most cells offset slightly; cells near tan poles scatter wildly
	float offset_scale = 0.01 + kick * 0.03;
	float scatter = tan(dot(c, sin(c.yx)));
	vec2 p = u + vec2(offset_scale * scatter);

	// Double-tanh ring with quadrant-varying color
	// vec4(p-0.3, p) creates a warm/cool split between RG and BA channels
	float color_shift = 0.3 - warmth * 0.15;
	vec4 shaped = tanh(vec4(p - color_shift, p + brightness * 0.1));

	// Ring at radius ~0.6 — sub_bass pushes outward, kick pulls inward
	float ring_r = 0.6 + sub_bass * 0.12 - kick * 0.05;
	float ring_dist = max(abs(length(p) - ring_r), 0.0001);

	vec4 ring = tanh(shaped * 0.1 / ring_dist);
	vec3 new_col = ring.rgb;

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay   = 0.93 + energy * 0.03;
	float emission = 0.15 + energy * 0.04;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
