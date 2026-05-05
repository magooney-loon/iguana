shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Mars
//  @author:        XorDev (magooney rmx)
//  @website:       xordev.com
//  @description:   Noise-terrain flyover with adaptive LOD and depth fog
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
//  Original tweet-shader by XorDev — a 200-step terrain raymarch using
//  2D simplex noise as a heightfield.  The adaptive LOD scheme cycles
//  the step divisor through exp(mod(i,5)), alternating coarse and fine
//  noise detail.  The terrain scrolls forward with time, creating a
//  flyover effect.  Output uses a grb channel swizzle for warm Mars-
//  like coloring with an off-center sun flare, depth fog, and terrain
//  shadow.  Adapted to the Iguana feedback pipeline with audio-reactive
//  terrain height, scroll speed, and atmospheric density.
//
//  Decompressed algorithm:
//    d = vec3(FC.xy*2-res, res.y) / res.x     // unnormalized ray dir
//    for 200 steps:
//      s = exp(mod(i, 5))                      // LOD: 1, e, e², e³, e⁴
//      h = p.y + 0.2 - 0.2*snoise((p.xz*.6+t*.2)*s)
//      p += d * h / s                          // adaptive step
//    raw = 0.5*d + 0.03*(d+1)/|d.xy-0.3| - 0.7/(p.z+1) - min(0.2+2p.y, 0)
//    color = raw.yxz                           // grb → rgb swizzle
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

// ── Simplex 2D noise (Ashima / Ian McEwan) ───────────────────────────

vec3 _mod289_v3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 _mod289_v2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 _permute(vec3 x)   { return _mod289_v3(((x * 34.0) + 10.0) * x); }

float snoise(vec2 v) {
	const vec4 C = vec4(
		0.211324865405187,   // (3 - sqrt(3)) / 6
		0.366025403784439,   // (sqrt(3) - 1) / 2
		-0.577350269189626,  // -1 + 2 * C.x
		0.024390243902439    // 1 / 41
	);

	// First corner
	vec2 i  = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);

	// Other corners
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;

	// Permutations
	i = _mod289_v2(i);
	vec3 p = _permute(_permute(i.y + vec3(0.0, i1.y, 1.0))
	                + i.x + vec3(0.0, i1.x, 1.0));

	// Gradients: 41 x 41 psrdnoise
	vec3 m = max(0.5 - vec3(dot(x0, x0),
	                         dot(x12.xy, x12.xy),
	                         dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;

	vec3 xp = 2.0 * fract(p * C.www) - 1.0;
	vec3 h  = abs(xp) - 0.5;
	vec3 ox = floor(xp + 0.5);
	vec3 a0 = xp - ox;

	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

	vec3 g;
	g.x  = a0.x * x0.x   + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;

	return 130.0 * dot(m, g);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK — terrain depth stacking ─────────────────────────
	// Subtle zoom stacks the terrain into layered depth echoes.
	// Minimal rotation — terrain perspective is directional.
	// Horizontal warp matches the terrain scroll direction.

	float zoom = 0.992 - energy * 0.003 - onset * 0.005;
	vec2 warped = center * zoom;
	warped = rot2(0.001 + bass * 0.002) * warped;

	vec2 warp = vec2(
		sin(warped.y * 5.0 + t * 0.8) * 0.005,
		cos(warped.x * 4.0 + t * 0.6) * 0.007
	);
	warp *= 1.0 + bass * 1.5 + energy * 1.0;
	warped += warp;

	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — Mars terrain ───────────────────────────────────

	// Unnormalized ray direction
	// Original: vec3(FC.xy*2 - res, res.y) / res.x
	// Flip y for Shadertoy-style upward-y
	vec3 d = vec3(
		uv.x * 2.0 - 1.0,
		(1.0 - 2.0 * uv.y) / aspect,
		1.0 / aspect
	);

	// Audio-reactive parameters
	float height_amp   = 0.2 * (1.0 + sub_bass * 1.5);       // bass swells mountains
	float scroll_speed = t * (0.2 + energy * 0.1);            // energy accelerates flyover
	float noise_freq   = 0.6 + treble * 0.1;                  // treble sharpens terrain detail
	float fog_density  = 0.7 + energy * 0.3;                  // energy thickens atmosphere

	// 200-step raymarch with adaptive LOD
	// s cycles through exp(0..4) = 1, 2.718, 7.389, 20.086, 54.598
	// Higher s = higher noise freq + smaller steps = more detail
	vec3 p = vec3(0.0);

	for (int i = 0; i < 200; i++) {
		float fi = float(i + 1);                              // 1..200
		float s = exp(mod(fi, 5.0));

		// Heightfield: surface at y = -0.2 + height_amp * noise
		vec2 noise_coord = (p.xz * noise_freq + vec2(scroll_speed)) * s;
		float h = p.y + 0.2 - height_amp * snoise(noise_coord);

		p += d * (h / s);
	}

	// Output color (with side-effect expansions from original)
	//
	// Original: o.grb = .5*d + .03*++d/length(d.xy-1.3)
	//                    - .7/++p.z - min(.2+p+p, 0.).y
	//
	// After expanding ++d and ++p.z:
	//   .03*(d+1)/length(d.xy-0.3)   — sun flare at d.xy = 0.3
	//   .7/(p.z+1)                   — depth fog
	//   min(0.2+2*p.y, 0)            — terrain shadow (below surface)

	float fog    = fog_density / (p.z + 1.0);
	float shadow = min(0.2 + 2.0 * p.y, 0.0);

	vec3 raw = 0.5 * d
	         + 0.03 * (d + 1.0) / length(d.xy - 0.3)
	         - fog
	         - shadow;

	// grb → rgb swizzle gives warm Mars coloring:
	//   red   ← raw.y (vertical view → warm below, cool above)
	//   green ← raw.x (horizontal view angle)
	//   blue  ← raw.z (forward component)
	vec3 new_col = max(raw.yxz, 0.0);

	// Compress to [0,1) for stable feedback — the sun flare can reach
	// very high values at its center.
	new_col = new_col / (1.0 + new_col);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay    = 0.92 + energy * 0.04;
	float emission = 0.08 + energy * 0.02;

	vec3 col = trail * decay + new_col * emission;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
