shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          3D Fire
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Fractal flame raymarch with height-dependent twist
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
//  Original tweet-shader by XorDev — a 50-step volumetric raymarch
//  through a cone-shaped SDF with 4-octave fractal displacement.
//  The height-dependent xz twist uses a cos matrix with large phase
//  offsets (0, 33, 11) to create spiraling flames that narrow as they
//  rise (divided by max(p.y*.1+1, .1) perspective term).  The yzx-axis
//  permutation in the fractal loop produces 3D volumetric detail that
//  scrolls upward at 10× speed, creating flickering flame motion.
//  Fire colors come from sin(z/3 + phase_offsets(7,2,3,0)) with the
//  +1.1 shift keeping all channels positive — warm orange/yellow tones
//  that cycle with depth through the flame volume.
//
//  Decompressed algorithm:
//    dir = normalize(vec3(FC.xy*2-res, -res.y))
//    for 50 steps:
//      p = z * dir + vec3(0, 0, 5+cos(t))            // camera bob
//      p.xz *= twist_matrix / max(p.y*.1+1, .1)      // spiral + narrow
//      for j = 2, 3.33, 5.56, 9.26:                  // fractal detail
//        p += cos((p.yzx - vec3(10t,0,0))*j + t) / j
//      d = .01 + abs(length(p.xz) + p.y*.3 - .5)/7   // cone SDF
//      glow += (sin(z/3 + vec4(7,2,3,0)) + 1.1) / d  // fire color
//    output = tanh(glow / 1000)
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

	// ── 1. FEEDBACK — rising heat ────────────────────────────────────
	// Upward drift bias creates rising-heat trails.
	// Moderate zoom stacks flame layers.
	// Subtle rotation complements the flame twist.

	float zoom = 0.992 - energy * 0.003 - onset * 0.005;
	vec2 warped = center * zoom;
	warped = rot2(0.003 + bass * 0.002) * warped;

	vec2 warp = vec2(
		sin(warped.y * 5.0 + t * 1.0) * 0.004,
		cos(warped.x * 4.0 - t * 0.7) * 0.006
	);
	// Persistent upward drift — fire trails rise like heat
	warp.y += 0.002 * (1.0 + energy);
	warp *= 1.0 + bass * 1.5 + energy * 1.0;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — 3D Fire ────────────────────────────────────────

	// Perspective ray direction
	vec3 dir = normalize(vec3(
		(2.0 * uv.x - 1.0) * aspect,
		1.0 - 2.0 * uv.y,
		-1.0
	));

	// Audio-reactive parameters
	float t_speed     = t * (1.0 + energy * 0.3);          // energy speeds animation
	float cone_slope  = 0.3 + sub_bass * 0.1;               // bass widens fire base
	float cone_offset = 0.5 - kick * 0.1;                   // kick contracts flame

	// 50-step volumetric raymarch
	float z = 0.0;
	float d = 0.0;
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 50; i++) {
		// Position along ray
		vec3 p = z * dir;

		// Camera bob — gentle forward/backward oscillation
		p.z += 5.0 + cos(t_speed);

		// Height-dependent xz twist — flames spiral and narrow upward
		// mat2 from cos(t + p.y*.5 + vec4(0,33,11,0))
		// Large phase offsets (33, 11 ≈ 4.8π, 1.75π) decorrelate axes
		// Division by max(p.y*.1+1, .1) narrows flames at height
		vec4 m = cos(t_speed + p.y * 0.5 + vec4(0.0, 33.0, 11.0, 0.0));
		mat2 xform = mat2(vec2(m.x, m.y), vec2(m.z, m.w));
		vec2 pxz = xform * p.xz / max(p.y * 0.1 + 1.0, 0.1);
		p.x = pxz.x;
		p.z = pxz.y;

		// 4-octave fractal displacement
		// j = 2, 3.33, 5.56, 9.26  (j /= 0.6 each step)
		// yzx permutation rotates displacement axes for 3D detail
		// vec3(10*t, 0, 0) scrolls pattern upward at 10× speed
		float j = 2.0;
		for (int k = 0; k < 4; k++) {
			vec3 scroll = p.yzx - vec3(10.0 * t_speed, 0.0, 0.0);
			p += cos(scroll * j + t_speed) / j;
			j /= 0.6;
		}

		// Cone SDF — fire shape
		// length(p.xz) + p.y*slope ≈ offset → V-shaped double cone
		// Positive p.y widens → flames open upward
		d = 0.01 + abs(length(p.xz) + p.y * cone_slope - cone_offset) / 7.0;
		z += d;

		// Fire-colored glow accumulation
		// sin(z/3 + phases(7,2,3)) cycles warm tones with depth
		// +1.1 shifts sin from [-1,1] to [0.1,2.1] (always positive)
		// /d brightens near the flame surface
		glow += (sin(z / 3.0 + vec3(7.0, 2.0, 3.0)) + 1.1) / d;
	}

	// Tanh compression — original scale: 1e3 = 1000
	// Typical accumulated glow: ~200–10000 → tanh input: 0.2–10
	vec3 new_col = tanh(glow / 1000.0);

	// Warmth shift — bass-heavy music → hotter (more red, less blue)
	new_col.r *= 1.0 + warmth * 0.15;
	new_col.b *= 1.0 - warmth * 0.08;

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.92 + energy * 0.04;
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
