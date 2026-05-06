shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Processing
//  @author:        hisadan (magooney rmx)
//  @website:       x.com/hisadan
//  @description:   Flow-field particle trails with noise-driven color and organic drift
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.2
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.30
//  @grain_strength: 0.005
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Inspired by a Processing sketch by hisadan: thousands of particles
//  flow through a Perlin noise vector field, leaving colorful HSB trails.
//  Every ~255 frames the field resets with a new noise seed, creating
//  evolving organic patterns. The particles follow noise-derived angles,
//  and color shifts continuously based on position and time.
//
//  Adapted to the Iguana feedback pipeline: the fragment shader traces
//  each pixel backward through the flow field using the noise texture,
//  then reads from prev_frame to create persistent trails. Audio-reactive
//  parameters control flow speed, turbulence, color cycling, and decay.
//
//  Algorithm outline:
//    for each pixel:
//      angle = noise(position * scale + time) * TAU * 3.0
//      dir = vec2(cos(angle), sin(angle))
//      sample_prev = UV + dir * step_size
//      trail = prev_frame(sample_prev) * decay
//      new_color = HSB(noise(position + time), saturation, brightness)
//      output = trail + new_color * emission
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

// HSB → RGB conversion (hue 0–1, sat 0–1, bri 0–1)
vec3 hsb2rgb(vec3 c) {
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

// Noise-based flow field angle
// Uses the noise texture to approximate Perlin noise flow fields
float flow_angle(vec2 p, float t, float scale) {
	vec2 ns = p * scale + t;
	// Sample noise texture for flow direction — use R and G channels
	// to create a more complex angle field
	float n1 = texture(noise_tex, ns * 0.5).r;
	float n2 = texture(noise_tex, ns * 0.5 + 0.37).g;
	// Combine for angle: noise * TAU * 3 gives full rotation with variation
	return (n1 * 0.7 + n2 * 0.3) * TAU * 3.0;
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 p = uv - 0.5;
	p.x *= aspect;

	float dist = length(p);

	// ── 1. FEEDBACK ──────────────────────────────────────────────────

	// Evolving flow scale — cycles between tight and wide turbulence
	float flow_scale = 2.5 + sin(t * 0.07) * 1.0 + activity * 1.2;
	float flow_speed = t * 0.15 * (1.0 + energy * 0.4);

	// Step size pulses on kick — particles surge forward
	float step_size = 0.0022 + bass * 0.0015 + energy * 0.0008
		+ kick * 0.004 * smoothstep(0.4, 0.0, dist);

	// Trace backward through the flow field
	float angle = flow_angle(p, flow_speed, flow_scale);

	// Snare adds a rotational kick to the warp
	float snare_rot = snare * 0.012 * sin(t * 3.0);

	// Domain warping — bass drives amplitude, snare adds jitter
	vec2 warp_offset = vec2(
		sin(p.y * 3.5 + t * 0.4) * (0.004 + bass * 0.004),
		cos(p.x * 3.0 + t * 0.35 + snare_rot) * (0.004 + bass * 0.003)
	);

	// Hi-hat adds fine turbulence to the sampling
	warp_offset += vec2(
		sin(p.x * 12.0 + t * 2.0) * hihat * 0.002,
		cos(p.y * 12.0 + t * 2.3) * hihat * 0.002
	);

	vec2 flow_dir = vec2(cos(angle), sin(angle)) * step_size;
	vec2 sample_uv = p + flow_dir + warp_offset;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	// Edge fade
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Flow field particles ────────────────────────────

	// Decay — beats briefly preserve trails, quiet periods fade fast
	float decay = 0.88 + energy * 0.02 + beat * 0.02;

	// Particle noise — fewer, larger blobs (lower UV scale)
	float noise_time = t * 0.08 + sin(t * 0.02) * 5.0;
	float particle_noise = texture(noise_tex, uv * 3.5 + noise_time).r;

	// Thin particle band — narrow range = sparse coverage (~6% of pixels)
	float particle_mask = smoothstep(0.44, 0.47, particle_noise)
		* smoothstep(0.54, 0.51, particle_noise);

	// Onset gently spikes particle density on transients
	particle_mask *= (1.0 + onset * 0.5 + kick * 0.3);

	// HSB color — hue drifts with time + position, shifts per audio band
	float hue = fract(
		texture(noise_tex, uv * 1.2 + t * 0.025).r * 0.5
		+ t * 0.015
		+ dist * 0.4
		+ snare * 0.08   // snare shifts hue suddenly
	);

	// Warmth tilts toward warm, brightness tilts toward cool
	hue = fract(hue + warmth * 0.12 - brightness * 0.06);

	float sat = 0.45 + brightness * 0.1 + energy * 0.08;

	// Base emission — quiet ambient
	float bri = particle_mask * 0.03;

	// Energy adds a steady glow proportional to loudness
	bri += particle_mask * energy * 0.03;

	// Kick pulse — bright burst centered, fades with distance
	float kick_glow = kick * 0.1 * smoothstep(0.6, 0.0, dist);
	bri += particle_mask * kick_glow;

	// Snare flash — wide, brief, brighter at mid-distances
	float snare_ring = snare * 0.06 * smoothstep(0.15, 0.35, dist) * smoothstep(0.65, 0.35, dist);
	bri += particle_mask * snare_ring;

	vec3 new_col = hsb2rgb(vec3(hue, sat, bri));

	// Hi-hat sparkles — high-frequency detail dots
	float sparkle = smoothstep(0.93, 0.97, texture(noise_tex, uv * 20.0 + t * 0.5).r);
	sparkle *= hihat * 0.08;
	new_col += vec3(sparkle) * hsb2rgb(vec3(fract(hue + 0.3), 0.3, 1.0));

	// Compress emission — tanh keeps dynamic range but caps accumulation
	new_col = tanh(new_col * 1.8);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	vec3 col = trail * decay + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
