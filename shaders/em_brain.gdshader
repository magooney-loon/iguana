shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          EM-Brain
//  @author:        YoheiNishitsuji (magooney rmx)
//  @website:       x.com/YoheiNishitsuji
//  @description:   Rotating fractal domain-warp brain with chromatic split feedback
//
//  Post-processing defaults
//  @exposure:       1.4
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.30
//  @grain_strength: 0.006
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
//
//  Original tweet-code by YoheiNishitsuji:
//    #define R rotate2D
//    vec2 p=FC.xy,q,l=(p+p-r)/r.x*.4+vec2(-1.95,-.8),n;
//    float s=6.,h,i,L=dot(l+1.7,l),e=99.;
//    for(;i++<e;)l*=R(5.),n*=R(4.8)+rotate2D(t)*.01,
//      h+=dot(r/r,sin(q=l*s*i+n)/s*6.),n-=cos(q),s*=1.05;
//    h=-h*.4-L;o-=h*.5*vec4(.65,vec3(.9,.9,1));
//
//  99-iteration fractal accumulation. Two coordinate vectors `l` and
//  `n` spiral through opposing rotations (5 rad and ~4.8 rad/step).
//  Each step accumulates sin(l*s*i+n)/s*6 into a volumetric glow h,
//  while n is warped by cos(q) feedback. Scale s*=1.05 adds fractal
//  detail at progressively finer levels. Result: a brain-like organic
//  structure with complex folding — the EM-Brain.
//
//  Decompressed algorithm:
//    l = (2*fragCoord - res) / res.x * 0.4 + vec2(-1.95, -0.8)
//    n = vec2(0), s = 6, h = 0, i = 0
//    L = dot(l + 1.7, l)              — distance weighting / vignette
//    for i = 1..99:
//      l *= rotate2D(5.0)             — spiral coordinate transform
//      n *= rotate2D(4.8) + rotate2D(t)*0.01  — warped counter-rotation
//      q = l * s * i + n              — domain warp target
//      h += dot(1,1, sin(q) * 6 / s) — accumulate volumetric glow
//      n -= cos(q)                    — domain warp feedback
//      s *= 1.05                      — fractal scale increase
//    h = -h*0.4 - L                   — invert + distance falloff
//    color -= h * 0.5 * (0.65, 0.9, 0.9, 1)  — teal/cyan output
//
//  Shader adaptation: 80–90 iterations with audio-reactive time speed,
//  bass-modulated fractal scale, and chromatic split feedback. Each
//  R/G/B channel samples the previous frame at a different rotation
//  angle and directional flow offset — over many frames the channels
//  diverge into prismatic rainbow-edged trails.
// ═══════════════════════════════════════════════════════════════════════

// ── Audio · all values 0–1, pushed every frame by AudioAnalyzer ─────
//
// Frequency bands (smoothed)
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;
//
// Percussion envelopes (attack/decay shaped)
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;
//
// Spectral flux / onset (rate of change per band)
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;
//
// Global descriptors
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;
//
// Beat tracking
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float beat_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float kick_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float snare_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float hihat_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;
uniform int   frame           = 0;

// ── Feedback loop ────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.5;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Spectral rows (32 bands, 0–1 peak per row) ───────────────────────
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
	float aspect = rect_size.x / rect_size.y;
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — chromatic split
	//
	//  Each color channel (R, G, B) samples the previous frame at a
	//  different rotation angle and directional flow displacement.
	//  Over many frames the per-channel rotation diverges, splitting
	//  trails into prismatic rainbow-edged echoes. Combined with a
	//  shared zoom and per-channel directional flow for organic motion.
	//
	//  This is fundamentally different from standard zoom+rotate+warp:
	//  the three color channels evolve independently, creating spectral
	//  separation that compounds into iridescent spiraling trails.
	// ══════════════════════════════════════════════════════════════════

	vec2 center = uv - 0.5;
	center.x *= aspect;

	// Shared zoom — sub_bass breathes inward, onset pushes
	float zoom = 0.980 - sub_bass * 0.006 - onset * 0.004;
	vec2 zoomed = center * zoom;

	// Per-channel rotation — diverges over hundreds of frames
	float ang_r = 0.003 + energy * 0.003;
	float ang_g = 0.005 + energy * 0.004;
	float ang_b = 0.007 + energy * 0.005;

	vec2 ruv = rot2(ang_r) * zoomed;
	vec2 guv = rot2(ang_g) * zoomed;
	vec2 buv = rot2(ang_b) * zoomed;

	// Per-channel directional flow — bass amplifies the shimmer
	float flow = 0.003 * (1.0 + bass * 2.0);
	ruv += vec2(sin(center.y * 8.0 + t * 1.2), 0.0) * flow;
	guv += vec2(sin(center.x * 7.0 + t * 0.9), cos(center.y * 6.0 + t * 1.1)) * flow * 0.7;
	buv += vec2(0.0, cos(center.x * 6.0 + t * 1.5)) * flow;

	// Undo aspect correction, shift to 0–1 range
	ruv = vec2(ruv.x / aspect, ruv.y) + 0.5;
	guv = vec2(guv.x / aspect, guv.y) + 0.5;
	buv = vec2(buv.x / aspect, buv.y) + 0.5;

	// Edge fade — use average UV (channels are close enough)
	vec2 avg_uv = (ruv + guv + buv) / 3.0;
	vec2 edge_d = min(avg_uv, 1.0 - avg_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	// Decay — louder music clears old trails faster
	float decay = mix(0.92, 0.86, energy);

	// Sample each channel from its own rotated/drifted position
	vec3 trail;
	trail.r = texture(prev_frame, ruv).r * decay * edge_fade;
	trail.g = texture(prev_frame, guv).g * decay * edge_fade;
	trail.b = texture(prev_frame, buv).b * decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — EM-Brain fractal accumulation
	//
	//  Two coordinate vectors spiral through opposing rotations:
	//    l *= rotate2D(5.0)          — ~286° per step
	//    n *= rotate2D(4.8) + dR(t)  — ~275° + tiny time drift
	//
	//  Each step computes q = l*s*i + n, accumulates sin(q)*6/s
	//  into glow h, and warps n by cos(q) feedback. Scale s grows
	//  by 1.05× per step, adding fractal detail at finer levels.
	//
	//  The result is a brain-like organic structure — complex folding
	//  patterns emerging from the interplay of two counter-rotating
	//  spiral systems with domain warping.
	// ══════════════════════════════════════════════════════════════════

	// Fragment coordinates in pixel space (faithful to original)
	vec2 fc = uv * rect_size;
	vec2 res = rect_size;

	// Starting position — offset into fractal space
	vec2 l = (2.0 * fc - res) / res.x * 0.4 + vec2(-1.95, -0.8);
	vec2 n = vec2(0.0);

	// Initial scale — kick pulse expands fractal detail
	float s = 6.0 + kick * 0.5;
	float h = 0.0;

	// Distance weighting — vignette/spotlight around offset center
	// dot(l + vec2(1.7), l) = |l|² + 1.7*(l.x + l.y)
	float L = dot(l + vec2(1.7), l);

	// Audio-reactive time — energy makes the brain writhe
	float t_speed = t * (1.0 + energy * 0.2);

	// Precompute rotation matrices (constant across iterations)
	mat2 l_rot = rot2(5.0);
	mat2 n_rot = rot2(4.8) + rot2(t_speed) * 0.01;

	// Iteration count — energy reveals finer fractal detail
	int max_iter = 80 + int(energy * 10.0);  // 80–90

	for (int iter = 0; iter < 90; iter++) {
		if (iter >= max_iter) break;

		float fi = float(iter + 1);  // i starts at 1 in original

		// Spiral transforms — l and n counter-rotate
		l *= l_rot;
		n *= n_rot;

		// Domain warp target
		vec2 q = l * s * fi + n;

		// Accumulate volumetric glow — sin(q)*6/s weighted by iteration
		h += dot(vec2(1.0), sin(q) * 6.0 / s);

		// Domain warp feedback — bends n toward cos structure
		n -= cos(q);

		// Fractal scale increase — finer detail each step
		s *= 1.05;
	}

	// Invert + distance falloff — L darkens outer regions
	h = -h * 0.4 - L;

	// Base color — teal/cyan from original vec4(0.65, 0.9, 0.9, 1.0)
	// Audio shifts: warmth → gold, brightness → cooler blue
	vec3 base_col = vec3(0.65, 0.9, 0.9);
	base_col += vec3(warmth * 0.15, -warmth * 0.08, -warmth * 0.12);

	// Output — max clamps negatives, tanh compresses for safe feedback
	// emission ×0.10 keeps equilibrium ≤ 1.0 with decay ~0.89
	vec3 raw = max(-h * 0.5 * base_col, 0.0);
	vec3 new_col = tanh(raw) * 0.10;

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + new geometry, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════

	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
