shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Lightning Storm
//  @author:        afrhu (magooney rmx)
//  @website:       shadertoy.com/view/73f3zM
//  @description:   Cycle-based lightning bolts with FBM paths and corona
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.5
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.35
//  @grain_strength: 0.008
//  @loop_reinhard:  0.0
// ═══════════════════════════════════════════════════════════════════════
//
//  Original shader by afrhu — a cycle-based lightning system where time
//  is discretized into cycles.  Each cycle has a random probability of
//  producing a strike (governed by VOLTAGE / PRESSURE).  Active strikes
//  grow from top to bottom, following a path defined by 5-octave FBM
//  noise.  Three branches split off at random heights, each with their
//  own noise path.  Glow uses a dual inverse-distance model (sharp core
//  + soft bloom).  A faint corona flickers at the screen edges between
//  strikes.  Adapted to the Iguana feedback pipeline with audio-reactive
//  voltage, persistence, and time scale.
//
//  Decompressed algorithm:
//    t = time * TIME_SCALE
//    cycle = floor(t), prog = fract(t)
//    if hash(cycle) < strike_probability:
//      stroke = ramp_up * exp_decay(prog, PERSISTENCE)
//      grow = min(prog*5, 1) — bolt grows top→bottom in 20% of cycle
//      bolt_x(y) = (fbm(y*1.3, cycle) - 0.5) * 0.8
//      glow = sharp(0.003/d) + bloom(0.06/d)
//      for 3 branches:
//        split at random height, branch extends downward with own noise
//      glow *= stroke * growth_mask
//      color = contact_flash + bolt_color * glow + bloom³·⁵
//    corona = edge_glow * noise(flicker) * voltage
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

// ── Hash · pseudo-random from vec2 seed ──────────────────────────────

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// ── Value noise ──────────────────────────────────────────────────────

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);  // smoothstep hermite
	return mix(
		mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// ── Fractal Brownian motion · 5 octaves ──────────────────────────────

float fbm(vec2 p, float s) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p + s);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// ── Bolt path · x-offset at height y for a given cycle ──────────────

float bolt_path(float y, float cycle) {
	return (fbm(vec2(y * 1.3, cycle), 0.0) - 0.5) * 0.8;
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK — lingering charge ───────────────────────────────
	// Vertical bias — lightning trails drift like residual charge.
	// Moderate zoom converges the trails inward.

	float zoom = 0.993 - energy * 0.003 - onset * 0.005;
	vec2 warped = center * zoom;
	warped = rot2(0.002 + bass * 0.001) * warped;

	vec2 warp = vec2(
		sin(warped.y * 5.0 + t * 0.8) * 0.003,
		cos(warped.x * 3.0 - t * 0.5) * 0.005
	);
	warp.y -= 0.001 * (1.0 + energy);  // subtle upward drift
	warp *= 1.0 + bass * 1.5 + energy * 1.0;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Lightning Storm ────────────────────────────────

	// Flip y for Shadertoy-style y-up (bolt grows top→bottom)
	vec2 U = vec2(uv.x, 1.0 - uv.y);

	// Audio-reactive parameters
	float voltage     = 100.0 + energy * 200.0;           // more energy → more strikes
	float pressure    = 1.0;
	float persistence = 2.0 + bass * 2.0;                 // bass extends glow
	float time_scale  = 4.0 + energy * 4.0;               // energy speeds cycles

	float st    = t * time_scale;
	float cycle = floor(st);
	float prog  = fract(st);

	vec3 new_col = vec3(0.0);

	// ── Strike probability ───────────────────────────────────────────
	// Higher voltage → higher strike chance.
	// At quiet (voltage=100): 20% per cycle
	// At loud  (voltage=300): 100% per cycle
	float strike_chance = 0.3 + (voltage - 120.0 * pressure) / 200.0;

	if (hash21(vec2(cycle, 13.45)) < strike_chance) {

		// Stroke envelope: quick ramp up, exponential decay
		float stroke = smoothstep(0.0, 0.05, prog)
		             / exp(prog * 6.0 / persistence);

		// Growth: bolt extends top→bottom, full length at 20% of cycle
		float grow = min(prog * 5.0, 1.0);

		// Mask: only render above the growth front
		float mask = step(1.0 - grow, U.y);

		// Contact flash: when bolt reaches the bottom
		float contact = step(0.99, grow);

		// ── Main bolt ────────────────────────────────────────────────
		float tx = bolt_path(U.y, cycle);
		float d  = abs(U.x - 0.5 - tx);

		// Dual glow: sharp core + soft bloom
		float glow = 0.003 / (d + 0.0002)
		           + 0.06  / (d + 0.06);

		// ── Branches (3) ─────────────────────────────────────────────
		for (int i = 1; i <= 3; i++) {
			float fi   = float(i);
			float seed = cycle + fi * 7.8;
			float split = hash21(vec2(seed, 0.1)) * 0.6 + 0.2;

			// Branch visible if: pixel below split AND split above growth front
			if (U.y < split && split < grow) {
				// Branch x: starts at main bolt position, deviates with own noise
				float bx = bolt_path(split, cycle)
				         + (fbm(vec2(U.y * 3.0, seed), 1.0) - 0.5) * 0.4;
				float dbx = abs(U.x - 0.5 - bx);

				// Fade below the split point (over 0.3 units)
				float fade = 1.0 - smoothstep(-0.3, 0.0, U.y - split);
				glow += (0.001 / (dbx + 0.0003) + 0.02 / (dbx + 0.05)) * fade;
			}
		}

		glow *= stroke * mask;

		// Composite: contact flash + bolt color + bloom
		// Bolt goes purple (fading) → white (fresh), matching lightning temperature
		new_col += vec3(0.4, 0.6, 1.0) * 0.4 / exp(prog * 10.0) * contact      // flash
		        + mix(vec3(0.5, 0.2, 1.0), vec3(0.7, 0.9, 1.0), stroke) * glow  // bolt
		        + pow(glow * 0.5, 3.5);                                            // bloom
	}

	// ── Corona discharge at screen edges ─────────────────────────────
	float cor = (exp(-abs(U.y - 0.97) * 25.0)
	           + exp(-abs(U.y - 0.03) * 25.0))
	          * vnoise(vec2(t * 15.0));
	new_col += vec3(0.05, 0.1, 0.5) * cor
	         * voltage / 400.0
	         * smoothstep(0.0, 0.5, 0.5 - abs(U.x - 0.5));

	// Compress for feedback stability — bolt center can reach ~1448
	// before this clamp.  x/(1+x) maps [0,∞) → [0,1).
	new_col = new_col / (1.0 + new_col);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.92 + energy * 0.04;
	float emission = 0.07 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
