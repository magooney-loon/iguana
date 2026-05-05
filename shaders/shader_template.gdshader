shader_type canvas_item;

//  @meta:          skip
// COPY WITHOUT THE @meta:          skip
// ═══════════════════════════════════════════════════════════════════════
//  @name:          My Shader
//  @author:        Your Name
//  @website:       N/A
//  @description:   One-line description shown in the settings UI
//
//  Post-processing defaults — tune these to taste, then leave them.
//  Any omitted value falls back to the global default.
//  @exposure:       1.42   // overall brightness (0.1 – 3.0)
//  @tonemap_knee:   0.0    // highlight compression (0.0 – 2.0)
//  @gamma:          2.0    // output gamma (0.5 – 3.0)
//  @vignette_dark:  0.30   // edge darkening (0.0 – 1.0)
//  @grain_strength: 0.01   // film grain (0.0 – 0.08)
//  @loop_reinhard:  0.9    // feedback Reinhard clamp (0.0 = off, 3.0 = heavy)
// ═══════════════════════════════════════════════════════════════════════
//
//  Pipeline — implement all three phases in fragment() below:
//    1. FEEDBACK  — warp / zoom / rotate prev_frame into trailing echoes
//    2. GEOMETRY  — draw fresh visuals (raymarching, SDFs, particles, etc.)
//    3. COMPOSITE — blend trail + new geometry, apply loop_reinhard tonemap
//
//  To ship a new shader: drop your .gdshader into res://shaders/ and
//  fill in the @meta tags above. The engine picks it up automatically.
// ═══════════════════════════════════════════════════════════════════════

// ── Audio · all values 0–1, pushed every frame by AudioAnalyzer ─────
//
// Frequency bands (smoothed)
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;  //   20–60 Hz   deep bass rumble
uniform float bass        : hint_range(0.0, 1.0) = 0.0;  //   60–250 Hz  kick body / bass guitar
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;  //  250–800 Hz  warmth / body
uniform float mid         : hint_range(0.0, 1.0) = 0.0;  //  800 Hz–4 kHz vocals / snare crack
uniform float presence    : hint_range(0.0, 1.0) = 0.0;  //   4–8 kHz    clarity / attack
uniform float treble      : hint_range(0.0, 1.0) = 0.0;  //   8–16 kHz   air / cymbals
//
// Percussion envelopes (attack/decay shaped)
uniform float beat        : hint_range(0.0, 1.0) = 0.0;  // general beat pulse
uniform float kick        : hint_range(0.0, 1.0) = 0.0;  // low-frequency kick drum
uniform float snare       : hint_range(0.0, 1.0) = 0.0;  // mid-frequency snare
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;  // high-frequency hi-hat
//
// Spectral flux / onset (rate of change per band)
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;  // bass transient energy
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;  // mid transient energy
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;  // treble transient energy
uniform float onset       : hint_range(0.0, 1.0) = 0.0;  // weighted onset strength
//
// Global descriptors
uniform float energy      : hint_range(0.0, 1.0) = 0.0;  // RMS loudness
uniform float activity    : hint_range(0.0, 1.0) = 0.0;  // spectral activity / busyness
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;  // perceptual loudness
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;  // bass ↔ treble ratio  (1 = bass-heavy)
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;  // treble energy ratio  (1 = bright)
uniform float density     : hint_range(0.0, 1.0) = 0.0;  // spectral flatness    (1 = noisy)
//
// Beat tracking
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;  // 0–1 ramp within current beat
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;  // tracker reliability
uniform float beat_threshold  : hint_range(0.0, 1.0) = 0.3;  // adaptive kick threshold
uniform float kick_threshold  : hint_range(0.0, 1.0) = 0.3;  // adaptive kick threshold
uniform float snare_threshold : hint_range(0.0, 1.0) = 0.3;  // adaptive snare threshold
uniform float hihat_threshold : hint_range(0.0, 1.0) = 0.3;  // adaptive hi-hat threshold
uniform float bpm             = 120.0;                         // estimated BPM
uniform float time_val        = 0.0;                           // elapsed seconds
uniform int   frame           = 0;                             // frame counter (parity / rhythm)

// ── Feedback loop ────────────────────────────────────────────────────
// Sample prev_frame warped/zoomed/rotated to build MilkDrop-style trails.
// repeat_disable = black border (use clamp or wrap manually if you need tiling).
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader Reinhard · tunable in Settings UI ─────────────────────
// Applied INSIDE the feedback loop to control trail brightness.
// 0.0 = bypass (full accumulation), higher = more compression.
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.9;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);  // viewport resolution in pixels

// ── Spectral rows (32 bands, 0–1 peak per row) ───────────────────────
// Use peak_00 (sub-bass) … peak_31 (ultra-treble) for equalizer-style FX.
uniform float peak_00 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_01 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_02 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_03 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_04 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_05 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_06 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_07 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_08 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_09 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_10 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_11 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_12 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_13 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_14 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_15 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_16 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_17 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_18 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_19 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_20 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_21 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_22 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_23 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_24 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_25 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_26 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_27 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_28 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_29 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_30 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_31 : hint_range(0.0, 1.0) = 0.0;

// ── Constants ────────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helpers (add your own below) ─────────────────────────────────────

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;                          // 0–1, top-left origin
	vec2 res = rect_size;
	vec2 p   = (uv - 0.5) * vec2(res.x / res.y, 1.0);  // aspect-corrected, centered

	// ── 1. FEEDBACK ──────────────────────────────────────────────────
	// Warp the UV before sampling to create trails / zoom / rotation.
	// Example: slow inward zoom + slight rotation
	vec2 warp_uv = uv;
	warp_uv = (warp_uv - 0.5) * (1.0 - 0.004 - energy * 0.003);  // zoom toward center
	warp_uv *= rot2(0.002 + bass * 0.004);                          // gentle rotation
	warp_uv += 0.5;

	vec3 trail = texture(prev_frame, warp_uv).rgb;

	// ── 2. GEOMETRY ──────────────────────────────────────────────────
	// Draw your visuals here. Use p (centered, aspect-corrected) or uv (0–1).
	vec3 new_col = vec3(0.0);

	// Example: simple pulsing circle driven by kick
	float r    = length(p);
	float ring = smoothstep(0.02, 0.0, abs(r - 0.3 - kick * 0.15));
	new_col   += vec3(0.2, 0.6, 1.0) * ring;

	// ── 3. COMPOSITE ─────────────────────────────────────────────────
	// Blend trail with new geometry, then apply loop_reinhard to keep
	// feedback from blowing out over many frames.
	vec3 col = trail * 0.92 + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
