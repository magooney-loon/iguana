shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Nebula
//  @author:        Magooney
//  @website:       github.com/magooney-loon
//  @description:   Domain-warped plasma clouds with billowing feedback trails
//
//  @exposure:       1.50
//  @tonemap_knee:   0.0
//  @gamma:          2.10
//  @vignette_dark:  0.38
//  @grain_strength: 0.007
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════

// ── Frequency bands ──────────────────────────────────────────────────
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;

// ── Percussion envelopes ─────────────────────────────────────────────
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;

// ── Spectral flux / onset ────────────────────────────────────────────
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;

// ── Global descriptors ───────────────────────────────────────────────
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;

// ── Beat tracking ────────────────────────────────────────────────────
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;

// ── Feedback / utility ───────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform float     loop_reinhard : hint_range(0.0, 3.0) = 0.85;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2      rect_size = vec2(1600.0, 900.0);

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

// Cosine palette — shifts from cool blue-violet (warmth=0) to warm orange-pink (warmth=1)
vec3 nebula_pal(float t, float w) {
	vec3 a  = mix(vec3(0.50, 0.48, 0.62), vec3(0.62, 0.44, 0.30), w);
	vec3 b  = mix(vec3(0.38, 0.30, 0.52), vec3(0.52, 0.40, 0.30), w);
	vec3 cv = mix(vec3(0.70, 0.80, 1.00), vec3(1.00, 0.72, 0.52), w);
	vec3 d  = mix(vec3(0.30, 0.50, 0.02), vec3(0.00, 0.12, 0.42), w);
	return a + b * cos(TAU * (cv * t + d));
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2  uv  = UV;
	float t   = time_val;
	float asp = rect_size.x / rect_size.y;

	vec2 center = uv - 0.5;
	center.x *= asp;

	// ── 1. FEEDBACK ──────────────────────────────────────────────────
	// Slow inward zoom — sub_bass breathes the tunnel, onset = hard rush
	float zoom = 0.994 - energy * 0.003 - onset * 0.007;
	vec2 warped = center * zoom;

	// Rotation — bass tightens the spiral, sub_bass counter-nudges
	warped = rot2(0.005 + bass * 0.006 - sub_bass * 0.002) * warped;

	// Two-octave warp field — large billowing drift + fine turbulence
	vec2 wf = vec2(
		sin(warped.y * 4.8 + t * 0.55) * 0.011 + sin(warped.y * 10.6 + t * 1.05) * 0.004,
		cos(warped.x * 4.4 + t * 0.48) * 0.011 + cos(warped.x *  9.3 + t * 0.92) * 0.004
	);
	wf *= 1.0 + bass * 2.8 + energy * 1.6;
	warped += wf;

	// Back to UV space, edge fade, sample
	vec2 sample_uv = warped;
	sample_uv.x /= asp;
	sample_uv += 0.5;

	vec2 ed = min(sample_uv, 1.0 - sample_uv);
	float ef = smoothstep(0.0, 0.04, min(ed.x, ed.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb * ef;

	// ── 2. GEOMETRY — domain-warped nebula plasma ─────────────────────

	vec2 q = center;

	// First warp pass — large pillars / cloud masses
	// low_mid drives how much the clouds billow
	float w1 = 0.19 + bass * 0.11 + low_mid * 0.09;
	q += vec2(
		sin(center.y * 3.3 + t * 0.32 + low_mid * 1.4) * w1,
		cos(center.x * 3.7 + t * 0.27 + low_mid * 1.2) * w1
	);

	// Second warp pass — fine turbulence inside the clouds
	float w2 = 0.07 + mid * 0.06 + presence * 0.04;
	q += vec2(
		sin(q.y * 7.0 + t * 0.66 + flux_mid  * 1.8) * w2,
		cos(q.x * 6.7 + t * 0.60 + flux_bass * 1.6) * w2
	);

	// Two-source field — fewer terms = sparser zero crossings across the screen
	float f1 = sin(q.x * (3.8 + treble * 1.0) + q.y * (3.2 + presence * 0.8));
	float f2 = cos(length(q) * (5.5 + mid * 1.8) - t * 0.75 + beat_phase * TAU * 0.15);
	float field = (f1 + f2) * 0.5;  // range [-1, 1]

	// ── tanh glow around field iso-surfaces ──────────────────────────
	// sin(field*PI) = 0 at field = 0, ±1 → ~3 curving filaments in view.
	// tanh(k/dist) gives a soft halo: bright at the line, fading smoothly outward.
	// This is the same pattern scatter uses — bounded output, no fill blowout.
	float dist_main = abs(sin(field * PI));
	float filaments = tanh(0.10 / max(dist_main, 0.004));

	// Snare flashes a second set of tighter filaments at double frequency
	float dist_snap = abs(sin(field * PI * 2.0));
	filaments += tanh(0.05 / max(dist_snap, 0.004)) * snare * 0.55;

	float r = length(center);

	// Kick ring — tanh radial glow, pulses outward
	float ring_r = 0.30 + sub_bass * 0.10 + kick * 0.12;
	float ring   = tanh(0.08 / max(abs(r - ring_r), 0.003)) * (0.45 + kick * 0.55);

	// Onset shockwave
	float shock  = tanh(0.06 / max(abs(r - (0.08 + onset * 0.58)), 0.003)) * onset * 0.75;

	// Core flash on kick
	float core   = exp(-r * 12.0) * (kick * 0.40 + beat * 0.09);

	float raw    = clamp(filaments + ring + shock + core, 0.0, 1.0);

	// Hue rides the field value — each filament gets its own color band
	float hue    = field * 0.25 + t * 0.030 + beat_phase * 0.08 + brightness * 0.12;
	vec3 new_col = nebula_pal(hue, warmth) * raw;

	// ── 3. COMPOSITE ─────────────────────────────────────────────────
	// tanh filaments: bright at line center (glow→1), falloff into dark space.
	// equilibrium at line center:  0.130/0.075 = 1.73 → clips white (ok, bright line)
	// equilibrium at half-glow:    0.065/0.075 = 0.87 → vivid halo
	// equilibrium in dark gaps:    0.016/0.075 = 0.21 → subtle nebula haze
	float decay    = 0.925 + energy * 0.010;
	float emission = 0.130 + energy * 0.015;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
