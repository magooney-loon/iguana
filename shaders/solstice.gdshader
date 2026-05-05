shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Solstice
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   V-shaped ring glow with diagonal color modulation
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
//  Original tweet-shader by XorDev — a luminous ring at radius 0.5
//  built from a V-shaped distance function with a steep inner wall
//  (10× sharper than the outer). A vec4 color multiplier gives warm
//  reds on the ring, half-bright greens, and blue that shifts with
//  spatial position. The diagonal abs(p.x-p.y) term brightens pixels
//  along the 45° axis, splitting the ring into four luminous quadrants.
//  Adapted to the Iguana feedback pipeline with animated rotation,
//  bass-driven ring breathing, and energy-scaled glow intensity.
//
//  Decompressed algorithm:
//    p = (fragCoord*2 - resolution) / resolution.y       // centered UV
//    v = length(p) - 0.5                                  // radial offset
//    ring = max(v, -v/0.1)                                // V-shape: sharp inside
//    color = vec4(2, 1, 1+p.x, 1+p.y)                    // warm/cool split
//    glow = 0.03 * color / (0.05 + ring) / (0.1 + |p.x-p.y|)
//    output = tanh(glow)
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

	// ── 1. FEEDBACK — concentric ring stacking ───────────────────────
	// Moderate zoom stacks the ring into concentric echoes.
	// Rotation spirals the diagonal bright axis.
	// Warp pattern mirrors the abs(p.x-p.y) diagonal motif.

	float zoom = 0.988 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;
	warped = rot2(0.005 + beat_phase * 0.003) * warped;

	// Diagonal-crossing warp — mirrors the shader's abs(p.x-p.y) structure
	vec2 warp = vec2(
		sin(warped.y * 7.0 + t * 1.0) * 0.005,
		cos(warped.x * 7.0 - t * 0.8) * 0.005
	);
	warp += 0.003 * vec2(
		sin((warped.x + warped.y) * 4.0 + t * 1.3),
		cos((warped.x - warped.y) * 4.0 - t * 0.9)
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

	// ── 2. GEOMETRY — Solstice ───────────────────────────────────────

	// Centered UV: (FC.xy*2 - r) / r.y
	vec2 p = vec2((uv.x * 2.0 - 1.0) * aspect, uv.y * 2.0 - 1.0);

	// Animate: slow ambient rotation, energy accelerates
	p = rot2(t * 0.2 + energy * 0.3) * p;

	// Sine wobble — energy amplifies the displacement
	p += 0.015 * sin(p.yx * 3.5 + t * 0.7) * (1.0 + energy * 2.0);

	// Ring radius — sub_bass breathes it outward, kick punches inward
	float ring_base = 0.5
	                + 0.08 * sin(t * 0.6)
	                + sub_bass * 0.15
	                - kick * 0.08;

	// Inner wall sharpness — treble tightens the inner edge
	// Original: -v/0.1 = 10× steep inner wall
	float inner_sharp = max(0.1 - treble * 0.04, 0.03);

	// V-shaped ring function:
	//   outside (r > ring_base): gently rising v
	//   inside  (r < ring_base): steep inner wall at 1/inner_sharp × rate
	float r = length(p);
	float v = r - ring_base;
	float ring = max(v, -v / inner_sharp);

	// Diagonal bright axis — activity adds radial modulation
	float diag = abs(p.x - p.y);
	diag += 0.08 * sin(r * 5.0 - t * 1.5) * activity;

	// Glow — original 0.03 scale, energy-boosted
	// Denominator: (0.05 + ring) * (0.1 + diagonal)
	// Ring centers get the strongest glow; diagonal brightens quadrants
	float glow_denom = (0.05 + ring) * (0.1 + diag);
	glow_denom = max(glow_denom, 0.001);

	// Color multiplier — vec4(2, 1, 1+p.x, 1+p.y) → warm reds, half greens,
	// blue shifting with position. Audio warmth/brightness nudge the palette.
	vec3 color_mult = vec3(
		2.0 + warmth * 0.4,
		1.0 + (1.0 - warmth) * 0.3,
		1.0 + (p.x + p.y) * 0.4 + brightness * 0.4
	);

	float glow_scale = 0.03 * (1.0 + energy * 0.4);
	vec3 glow = glow_scale * color_mult / glow_denom;

	vec3 new_col = tanh(glow);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	// Decay / emission balance — ring is narrow so bright pixels
	// at the ring center don't blow out the full image.
	// Equilibrium at quiet: 0.08 * tanh(12) / (1 - 0.91) ≈ 0.08/0.09 ≈ 0.89
	float decay    = 0.91 + energy * 0.04;
	float emission = 0.08 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
