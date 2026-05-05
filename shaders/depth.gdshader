shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Depth
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Volumetric depth-of-field raymarch through a repeated grid
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.4
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.30
//  @grain_strength: 0.006
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
//
//  Original tweet-shader by XorDev — a 40-step volumetric raymarch
//  through a repeated grid of rounded shapes with depth-of-field focus.
//  Glow accumulates inversely proportional to step distance, colored
//  by cycling cosine palettes. Adapted to the Iguana feedback pipeline
//  with audio-reactive focal distance, shape size, and color shifting.
//
//  Decompressed algorithm:
//    for each pixel:
//      rdir = normalize(screen_pos * 2 - resolution)   // ray direction
//      z = 0                                            // march distance
//      for 40 steps:
//        p = z * rdir                                   // world position
//        focal = abs(z - 3 + cos(t)/0.7) / 20          // focal-plane distance
//        sdf = length(abs(fract(p/v - 0.5) * v - 0.1)  // repeated grid SDF
//        step = 0.6 * max(focal, sdf - focal)           // adaptive step
//        z += step
//        glow += color / step²                          // accumulate
//      output = tanh(glow / 30000)
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
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.9;

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

	// ── 2. GEOMETRY — Depth raymarch ─────────────────────────────────

	// Ray direction from screen coordinates
	// Original: normalize(FC.rgb * 2.0 - r.xyy)
	//   FC.rgb = vec3(pixelX, pixelY, 0), r.xyy = vec3(resX, resY, resY)
	//   → vec3(2*px - resX, 2*py - resY, -resY) normalized
	//   ≈ vec3((2*UV.x-1)*aspect, 2*UV.y-1, -1) normalized
	vec2 centered = uv * 2.0 - 1.0;
	vec3 rdir = normalize(vec3(centered.x * aspect, centered.y, -1.0));

	// Repetition vector — y-stretched grid cells
	// Audio: bass stretches vertical period, creating taller/wider cells
	vec3 v = vec3(1.0, 2.0 + bass * 0.5, 1.0);

	// Focal plane — oscillates with time, audio shifts distance
	// Original: abs(z - 3.0 + cos(t) / 0.7) / 20.0
	float focal_dist = 3.0 + sub_bass * 0.8;
	float focal_osc  = 1.0 + energy * 0.4;

	// Shape size — kick inflates the grid elements
	float shape_size = 0.1 + kick * 0.03;

	// Color phase offsets — warmth/brightness shift the palette
	// Original: vec3(2, 1, 6) — arbitrary phase offsets for RGB
	vec3 color_phase = vec3(2.0, 1.0, 6.0) + vec3(warmth, brightness, warmth * 0.5) * 2.0;

	// March
	vec3 glow = vec3(0.0);
	float z = 0.0;

	for (int i = 1; i <= 40; i++) {
		float fi = float(i);

		// World position along ray
		vec3 p = z * rdir;

		// Focal-plane distance — controls depth-of-field blur
		float focal_d = abs(z - focal_dist + cos(t * focal_osc) / 0.7) / 20.0;

		// Repeated grid SDF
		// fract(p/v) wraps into unit cell, centered and scaled
		// length(...) gives distance to the shape at each cell
		vec3 cell = fract(p / v) - 0.5;
		vec3 scaled = abs(cell) * v - shape_size;
		float sdf = length(scaled);

		// Adaptive step: blend focal distance with SDF
		float d = 0.6 * max(focal_d, sdf - focal_d);

		// Accumulate volumetric glow — inverse-square falloff
		// cos cycling creates color variation per step
		vec3 step_color = (cos(fi * 0.25 + color_phase) + 1.0) / max(d * d, 0.0001);
		glow += step_color;

		// Advance along ray
		z += d;
	}

	// Tanh tonemapping — original: tanh(o / 3e4)
	float glow_scale = 30000.0 - energy * 8000.0;  // louder → brighter glow
	glow_scale = max(glow_scale, 5000.0);
	vec3 new_col = tanh(glow / glow_scale);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay = 0.93 + energy * 0.03;

	// Per-frame emission must be small — the feedback loop amplifies it.
	// tanh outputs up to ~1.0; raw additive at decay 0.93 gives equilibrium
	// of 1.0/0.07 = 14×.  Scale down to 0.15 so equilibrium ≈ 2.1,
	// then loop_reinhard(0.9) compresses it to ~1.0.
	float emission = 0.15 + energy * 0.04;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
