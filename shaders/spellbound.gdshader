shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Spellbound
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Spiraling tunnel with domain-warped cosine walls
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.4
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.25
//  @grain_strength: 0.006
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Original tweet-shader by XorDev — a 100-step raymarch through a
//  spiraling tunnel. Each step twists p.xy by a z-dependent matrix
//  (cos(z*0.2 + offsets)) that shears AND rotates, scrolls p.z by
//  -2*t for constant forward motion, then evaluates a domain-warped
//  cosine SDF: length(cos(p + cos(p.yzx*7+t)))/9. The yzx permutation
//  feeds each axis's cosine into the others, creating a complex
//  organic tunnel structure.
//
//  Decompressed algorithm:
//    for 100 steps:
//      p = z * normalize(ray)                     // position
//      p.xy *= mat2(cos(z*0.2 + vec4(0,33,11,0))) // z-dependent twist
//      p.z -= 2*t                                  // forward scroll
//      d = length(cos(p + cos(p.yzx*7+t))) / 9    // domain-warped SDF
//      glow += (sin(p.x + t + phase) + 1.3) / d
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

	// ── 1. FEEDBACK — hypnotic spiral ───────────────────────────────
	// The shader spirals inward — feedback should twist hard,
	// with a diamond-crossing warp that mirrors the yzx permutation.

	float zoom = 0.980 - sub_bass * 0.012 - onset * 0.008;
	vec2 warped = center * zoom;
	warped = rot2(0.008 + bass * 0.006 + beat_phase * 0.003) * warped;  // strong spiral

	// Crossing warp — both axes feed each other (like the yzx permutation)
	vec2 warp = vec2(
		sin(warped.x * 3.0 + warped.y * 5.0 + t * 1.2) * 0.007,
		cos(warped.x * 4.0 - warped.y * 3.0 + t * 0.8) * 0.007
	);
	warp *= 1.0 + kick * 2.0 + energy * 1.2;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Spellbound ────────────────────────────────────

	// Normalized ray direction
	vec2 centered_uv = uv * 2.0 - 1.0;
	vec3 rdir = normalize(vec3(centered_uv.x * aspect, centered_uv.y, -1.0));

	// Audio — just time speed, keep the original's character
	float t_speed = t * (1.0 + energy * 0.3);

	// Raymarch — 100 steps
	float z = 0.0;
	float d = 0.0;
	vec3 p = vec3(0.0);
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 100; i++) {
		// Position along ray
		p = z * rdir;

		// Z-dependent twist — NOT a pure rotation, shears too
		// Original: p.xy *= mat2(cos(z*0.2 + vec4(0,33,11,0)))
		// mat2 from vec4: col0=(v.x,v.y), col1=(v.z,v.w)
		vec4 m = cos(z * 0.2 + vec4(0.0, 33.0, 11.0, 0.0));
		mat2 twist = mat2(vec2(m.x, m.y), vec2(m.z, m.w));
		p.xy = p.xy * twist;

		// Forward scroll — the tunnel moves toward you
		p.z -= t_speed * 2.0;

		// Domain-warped cosine SDF
		// cos(p.yzx * 7 + t) permutes coordinates and warps
		// cos(p + warp) creates the organic tunnel structure
		d = length(cos(p + cos(p.yzx * 7.0 + t_speed))) / 9.0;

		// Accumulate glow — sin coloring with phase offsets
		// + 1.3 keeps always positive
		vec3 step_col = (sin(p.x + t_speed + vec3(0.0, 2.0, 4.0)) + 1.3) / max(d, 0.001);
		glow += step_col;

		// Advance
		z += d;
	}

	// Original: tanh(glow²/4e6). Squaring blows out in feedback,
	// but the 4e6 tells us glow hits 1000-3000. Without squaring
	// we need scale in the thousands, not tens.
	float glow_scale = max(4000.0 - energy * 1500.0, 1000.0);
	vec3 new_col = tanh(glow / glow_scale);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.91 + energy * 0.05;
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
