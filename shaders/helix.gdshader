shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Helix
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Volumetric helix raymarch with logarithmic spiral SDF
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
//  Original tweet-shader by XorDev — a 70-step volumetric raymarch
//  through a helical distance field.  The SDF combines log(radius)
//  with height/radius + azimuth*0.5 + time, producing a logarithmic
//  spiral that rotates around the y-axis.  Glow accumulates along
//  the ray, colored by cosine phase offsets (0, 2, 5, 3) that cycle
//  through warm and cool tones as the view traverses the helix.
//  Adapted to the Iguana feedback pipeline with audio-reactive
//  twist rate, SDF detail, and rotation speed.
//
//  Decompressed algorithm:
//    dir = normalize(vec3(FC.xy*2-res.xy, -res.y))   // perspective ray
//    for 70 steps:
//      p = z * dir + vec3(0, 0, 2)                   // position along ray
//      dist = length(p.xz)                           // radial distance from y-axis
//      sdf_uv = vec2(log(dist), p.y/dist + atan(p.x,p.z)*0.5 + t) * 4
//      step = dist * 0.1 * length(cos(sdf_uv))       // adaptive step
//      glow += (cos(p.y+z+phases) + 1.2) / step      // volumetric color
//      z += step
//    output = tanh(glow / 2000)
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

	// ── 1. FEEDBACK — spiral trail stacking ──────────────────────────
	// Rotation mirrors the helix spiral.
	// Spiral-biased warp complements the helical geometry.
	// Moderate zoom layers the volumetric glow.

	float zoom = 0.990 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;
	warped = rot2(0.005 + beat_phase * 0.003) * warped;

	// Standard + spiral warp
	vec2 warp = vec2(
		sin(warped.y * 6.0 + t * 1.2) * 0.005,
		cos(warped.x * 6.0 - t * 0.9) * 0.005
	);
	float wr = length(warped);
	warp += 0.003 * vec2(sin(wr * 4.0 + t), cos(wr * 4.0 + t));
	warp *= 1.0 + bass * 2.0 + energy * 1.5;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Helix ──────────────────────────────────────────

	// Perspective ray direction
	// Original: normalize(vec3(FC.xy*2 - res.xy, -res.y))
	// Simplified: normalize removes common scale (res.y)
	vec3 dir = normalize(vec3(
		(2.0 * uv.x - 1.0) * aspect,
		1.0 - 2.0 * uv.y,
		-1.0
	));

	// Audio-reactive parameters
	float twist    = 0.5 + bass * 0.2;                       // bass tightens helix
	float sdf_freq = 4.0 + treble * 1.0;                     // treble adds detail
	float t_speed  = t * (1.0 + energy * 0.3);               // energy speeds rotation

	// 70-step volumetric raymarch
	float z = 0.0;
	float d = 0.0;
	vec3 p  = vec3(0.0);
	vec3 glow = vec3(0.0);

	for (int i = 0; i < 70; i++) {
		// Position along ray, offset forward by 2 units
		p = z * dir;
		p.z += 2.0;

		// Radial distance from y-axis (cylindrical coordinates)
		float dist = max(length(p.xz), 0.001);

		// Helix SDF:
		//   u = log(dist)    — logarithmic spiral (detail scales with distance)
		//   v = height/dist + azimuth*twist + time — helical twist
		// Both tiled by sdf_freq, then cosined → near-zero = near surface
		vec2 sdf_uv = vec2(
			log(dist),
			p.y / dist + atan(p.x, p.z) * twist + t_speed
		) * sdf_freq;

		float sdf = 0.1 * length(cos(sdf_uv));
		d = dist * sdf;
		d = max(d, 0.0001);
		z += d;

		// Volumetric glow — colored by cosine phase offsets
		// Original phases: vec4(0,2,5,3) → RGB uses 0, 2, 5
		// +1.2 shifts cos from [-1,1] to [0.2,2.2] (always positive)
		// /d brightens near the helix surface (small step = near geometry)
		glow += (cos(p.y + z + vec3(0.0, 2.0, 5.0)) + 1.2) / d;
	}

	// Tanh compression — original scale: 2e3 = 2000
	// Typical accumulated glow: ~300–3000 → tanh input: 0.15–1.5
	float glow_scale = 2000.0;
	vec3 new_col = tanh(glow / glow_scale);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.91 + energy * 0.04;
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
