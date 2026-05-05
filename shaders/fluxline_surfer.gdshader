shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Fluxline Surfer
//  @author:        mrange (magooney rmx)
//  @website:       shadertoy.com/view/sfSXRt
//  @description:   4D-rotated kaleidoscopic raymarch with domain folding
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
//  Original tweet-shader by mrange — a 76-step raymarch through a
//  4D-rotated, domain-folded space.  A double-cosine rotation matrix
//  R = mat2(cos(cos(.4*z) + vec4(0,11,33,0))) is applied to three
//  different coordinate planes (yw, wx, xy), creating a complex 4D
//  spatial transformation.  The abs(p.xy)-0.5 fold creates a
//  kaleidoscopic repeating pattern.  The SDF uses a cross-correlation
//  term dot(p.yzwx, p) to add harmonic variation to a ring-like
//  distance field.  The glow is self-weighted: the w component of
//  the color vector acts as the brightness weight, creating a
//  volumetric accumulation that concentrates near the geometry.
//
//  Decompressed algorithm:
//    dir = normalize(vec3(fragCoord-res/2, res_y))
//    for 76 steps:
//      p = vec4(z * dir, 0.3)           // 4D position (w=0.3)
//      p.z += time                       // scroll forward
//      R = mat2(cos(cos(.4*z) + vec4(0,11,33,0)))
//      p.yw *= R, p.wx *= R, p.xy *= R  // three 4D rotations
//      color = 1 + sin(.3*z + 4*p.x + vec4(6,3,1,z))
//      p.xy = abs(p.xy) - 0.5           // kaleidoscope fold
//      d = .6*abs(length(p.xy) + mod) + .002
//      glow += color.w/d * color.rgb
//    output = tanh(glow / 10000)
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
	vec2 uv = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK — kaleidoscopic stacking ──────────────────────────
	// Rotation enhances the 4D spiral pattern.
	// Moderate zoom layers the kaleidoscope echoes.

	float zoom = 0.990 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;
	warped = rot2(0.005 + beat_phase * 0.003) * warped;

	vec2 warp = vec2(
		sin(warped.y * 6.0 + t * 1.0) * 0.005,
		cos(warped.x * 5.0 - t * 0.8) * 0.005
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

	// ── 2. GEOMETRY — Fluxline Surfer ────────────────────────────────

	// Perspective ray direction
	// Original: normalize(vec3(fragCoord - res/2, res_y))
	vec3 dir = normalize(vec3(
		(2.0 * uv.x - 1.0) * aspect,
		1.0 - 2.0 * uv.y,
		1.0
	));

	// Audio-reactive parameters
	float t_speed  = t * (1.0 + energy * 0.3);        // energy speeds scroll
	float rot_rate = 0.4 + bass * 0.1;                 // bass tightens twist
	float fold_off = 0.5 - kick * 0.08;                // kick shifts fold

	// 76-step raymarch through 4D space
	float z = 0.0;
	float d = 0.0;
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 76; i++) {
		// 4D position — w=0.3 adds an extra dimension
		vec4 p = vec4(z * dir, 0.3);

		// Scroll forward through the flux field
		p.z += t_speed;

		// Double-cosine rotation matrix — depth-dependent twist
		// cos(cos(rot_rate*z)) creates a smooth oscillation
		// Phase offsets (0, 11, 33, 0) decorrelate matrix elements
		// In Godot: mat2(vec2,vec2) — not mat2(vec4)
		vec4 m = cos(cos(rot_rate * p.z) + vec4(0.0, 11.0, 33.0, 0.0));
		mat2 R = mat2(vec2(m.x, m.y), vec2(m.z, m.w));

		// Three 4D plane rotations — creates complex spatial folding
		// Each rotates a different pair of coordinates with the same matrix
		// Original: p.yw*=R, p.wx*=R, p.xy*=R
		vec2 yw = R * vec2(p.y, p.w);  p.y = yw.x;  p.w = yw.y;
		vec2 wx = R * vec2(p.w, p.x);  p.w = wx.x;  p.x = wx.y;
		vec2 xy = R * vec2(p.x, p.y);  p.x = xy.x;  p.y = xy.y;

		// Color — sine waves with per-channel phase offsets
		// Phases (6, 3, 1, z) create color cycling with depth
		// +1 shifts from [-1,1] to [0,2] (always positive)
		vec4 color = 1.0 + sin(0.3 * p.z + 4.0 * p.x + vec4(6.0, 3.0, 1.0, p.z));

		// Domain folding — kaleidoscopic repeating pattern
		// abs(p.xy) reflects into positive quadrant, -offset tiles it
		p.x = abs(p.x) - fold_off;
		p.y = abs(p.y) - fold_off;

		// SDF — ring-like structure in folded space
		// dot(p.yzwx, p) = cross-correlation of adjacent components
		// The 17*sqrt(...) term adds harmonic variation
		// -89 bias means sin ≈ -1 → the modulation is ~-0.45
		// abs(length(p.xy) - ~0.45) creates the ring at radius ~0.45
		float cross_dot = dot(vec4(p.y, p.z, p.w, p.x), p);
		float modulation = 5e-3 * (sin(z + 17.0 * sqrt(abs(cross_dot))) - 89.0);

		d = 0.6 * abs(length(vec2(p.x, p.y)) + modulation) + 2e-3;
		z += d;

		// Self-weighted glow — the w component acts as brightness weight
		// color.w/d concentrates glow near the geometry surface
		glow += (color.w / d) * color.rgb;
	}

	// Tanh compression — original scale: 1e4 = 10000
	vec3 new_col = tanh(glow / 10000.0);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.92 + energy * 0.04;
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
