shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Quasar
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Quasicrystal diffraction pattern. Penrose-like.
//
//  Post-processing defaults
//  @exposure:       1.4
//  @tonemap_knee:   0.1
//  @gamma:          2.0
//  @vignette_dark:  0.28
//  @grain_strength: 0.005
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
//
//  Algorithm:
//    q5 = (1/5) Σ_{i=0}^{4} cos( dot(p, k_i) · freq + phase )
//    where k_i = (cos(i·π/5), sin(i·π/5))
//    → 10-fold symmetry, aperiodic (Penrose-like)
//
//    q7 = same with 7 waves at i·π/7, freq scaled by φ (golden ratio)
//    → 14-fold symmetry, incommensurate with q5
//
//    combined q = (q5 + 0.55·q7) / normalizer
//    interior = abs(q)              → tile bodies
//    ridges   = 1 - smooth(abs(q))  → boundary glow
//    peaks    = step(0.72, abs(q))  → tile-center highlights
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
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.5;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Constants ────────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359
#define PHI 1.61803398875  // golden ratio — used to make layers incommensurate

// ── Helpers ──────────────────────────────────────────────────────────

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) : col;
}

// N-fold quasicrystal: sum of N cosine plane waves at angles i·π/N
// k_i = (cos(i·π/N), sin(i·π/N)), returns [-1, 1]
// N=5 → 10-fold aperiodic (Penrose-like)
// N=7 → 14-fold aperiodic (exotic quasi-symmetry)
float qcrystal(vec2 p, int N, float freq, float phase) {
	float val = 0.0;
	for (int i = 0; i < N; i++) {
		float a = float(i) * PI / float(N);
		val += cos(dot(p, vec2(cos(a), sin(a))) * freq + phase);
	}
	return val / float(N);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK ──────────────────────────────────────────────────
	// No rotation — quasicrystal patterns are already visually rich,
	// rotating feedback would obscure the crystallographic structure.

	float zoom = 0.992 - energy * 0.004 - onset * 0.005;
	vec2 warped = center * zoom;

	vec2 warp = vec2(
		sin(warped.y * 5.0 + t * 0.8) * 0.004,
		cos(warped.x * 4.5 + t * 0.9) * 0.004
	);
	warp *= 1.0 + bass * 1.2 + energy * 0.8;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	// Slight chromatic aberration — gives glassy refraction feel
	float ca = 0.0008 + energy * 0.0006;
	vec3 trail;
	trail.r = texture(prev_frame, sample_uv + vec2(ca,  0.0)).r;
	trail.g = texture(prev_frame, sample_uv              ).g;
	trail.b = texture(prev_frame, sample_uv - vec2(ca,  0.0)).b;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Quasicrystal Diffraction ───────────────────────

	vec2 p = center;
	float dist_c = length(p);

	// Primary lattice scale: sub_bass + bass breathe the tile size
	float freq5 = 7.5 + sub_bass * 2.5 + bass * 1.5;
	// Second layer frequency offset by golden ratio → maximum incommensurability
	// (golden ratio produces the slowest-converging continued fraction, i.e.
	//  the "most irrational" ratio, so the moiré pattern never lock-steps)
	float freq7 = freq5 * PHI;

	// Phase: beat_phase continuously animates; kick fires a phase detonation
	float phase5 = t * 0.50  + beat_phase * TAU        + kick * 1.8;
	float phase7 = t * 0.382 + beat_phase * TAU * 0.618 + kick * 2.5;

	// Light domain warp driven by low_mid — keeps tiles slightly organic
	float warp_amt = low_mid * 0.045;
	vec2 p_w = p + vec2(
		sin(p.y * 3.2 + t * 0.30) * warp_amt,
		cos(p.x * 3.2 + t * 0.35) * warp_amt
	);

	// 5-fold layer: primary quasicrystal (10-fold symmetry)
	float q5 = qcrystal(p_w, 5, freq5, phase5);

	// 7-fold layer: treble + density unlock the exotic 14-fold layer
	float q7_w = treble * 0.55 + density * 0.25;
	float q7   = qcrystal(p_w, 7, freq7, phase7) * q7_w;

	// Combine; keep field nominally in [-1, 1]
	float q = (q5 + q7 * 0.55) / (1.0 + q7_w * 0.55);

	// ── Structure decomposition ───────────────────────────────────────

	// Interior: tile bodies — lit proportional to field magnitude
	float interior = abs(q) * (0.38 + mid * 0.32 + energy * 0.14);

	// Ridges: glow at zero-crossings (tile wall boundaries)
	float ridge_w = 0.18 + presence * 0.08;
	float ridges  = (1.0 - smoothstep(0.0, ridge_w, abs(q)))
	              * (0.55 + presence * 0.3 + hihat * 0.2);

	// Peaks: bright spots at tile-center maxima
	float peaks = smoothstep(0.72 + treble * 0.08, 1.0, abs(q))
	            * (0.45 + beat * 0.35 + kick * 0.22);

	// Radial vignette: center reads brighter, edges fade
	float radial = 1.0 - smoothstep(0.28, 0.72, dist_c);
	interior *= radial;
	ridges   *= radial;
	peaks    *= (0.4 + radial * 0.6);

	// ── Color ─────────────────────────────────────────────────────────
	// q5 value shifts hue continuously → adjacent tiles get distinct colors
	// without any manual ID hashing
	float hue = t * 0.09 + warmth * 1.3 + q5 * 1.4 + brightness * 0.6;
	vec3 col_interior = cos(vec3(0.0, 2.094, 4.189) + hue) * 0.5 + 0.5;
	vec3 col_ridge    = cos(vec3(0.6, 2.7,   4.8  ) + hue + 0.9) * 0.5 + 0.5;
	vec3 col_peak     = mix(col_interior, vec3(1.0), 0.22 + energy * 0.1);

	// Snare: ridge flash — edges briefly brighten toward cool white
	col_ridge = mix(col_ridge, vec3(0.72, 0.88, 1.0), snare * 0.32);

	vec3 new_col = col_interior * interior
	             + col_ridge    * ridges
	             + col_peak     * peaks;

	// Kick center burst — warm radial flash
	new_col += col_interior * kick * exp(-dist_c * 4.5) * 0.28;
	// Onset: brief blue-white pulse across the pattern
	new_col += vec3(0.35, 0.55, 1.0) * onset * 0.16 * radial;

	new_col = tanh(new_col * 1.5);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.92 + energy * 0.04;
	float emission = 0.12 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
