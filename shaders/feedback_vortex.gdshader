shader_type canvas_item;

// ── Audio uniforms ────────────────────────────────────────────────
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;  // 20-60 Hz — kick-drum channel
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float time_val    = 0.0;

// ── Feedback + interaction uniforms ──────────────────────────────
// hint_default_black: first frame samples black instead of white noise
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform vec2  mouse_pos  = vec2(0.5, 0.5);
uniform float mouse_down : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define TAU 6.28318530718

vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

void fragment() {
	vec2 uv = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// ══════════════════════════════════════════════════════════════
	//  PART 1: FEEDBACK — warp, zoom, rotate, and decay previous frame
	// ══════════════════════════════════════════════════════════════

	// Aspect-correct so zoom/rotation are circular, not elliptical
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// Zoom inward each frame: compounds into the classic infinite tunnel.
	// sub_bass (kick) adds a pulse that makes the tunnel breathe on the beat.
	float zoom = 0.98 - sub_bass * 0.02 - bass * 0.005;
	center *= zoom;

	// Per-frame rotation compounds into a spiral.
	// Energy widens the spiral; beat snaps it tighter on the downbeat.
	float rot = 0.007 + energy * 0.008 + beat * 0.006;
	float c = cos(rot), s = sin(rot);
	center = mat2(vec2(c, s), vec2(-s, c)) * center;

	// Back to UV space
	vec2 feedback_uv = center;
	feedback_uv.x /= aspect;
	feedback_uv += 0.5;

	// Per-pixel warp displacement: makes trails curve and flow instead of just
	// converging to a point. Uses aspect-corrected center so the field is
	// isotropic on 16:9 displays (raw uv.x/y would look stretched).
	vec2 warp = vec2(
		sin(center.y * 10.0 + t * 1.4) * 0.015,
		cos(center.x * 8.0  + t * 1.1) * 0.015
	);
	warp.x += sin(length(center) * 6.0 - t * 0.7) * 0.01;
	warp.y += cos(length(center) * 6.0 - t * 0.9) * 0.01;
	// Bass and energy widen the warp amplitude — more energy = wilder flow
	warp *= 1.0 + bass * 2.5 + energy * 1.5;

	// Mouse attraction: holding left-click pulls the warp field toward the cursor
	vec2 to_mouse = mouse_pos - uv;
	warp += normalize(to_mouse + 0.001) * exp(-length(to_mouse) * 8.0) * 0.04 * mouse_down;

	// Sample previous frame at the warped position and decay it
	vec3 trail = texture(prev_frame, clamp(feedback_uv + warp, 0.0, 1.0)).rgb;
	// Higher energy = longer trails (decay closer to 1.0)
	float decay = 0.92 + energy * 0.05;
	trail *= decay;

	// ══════════════════════════════════════════════════════════════
	//  PART 2: NEW GEOMETRY — fresh audio-reactive shapes each frame
	// ══════════════════════════════════════════════════════════════

	vec2 uv_c = uv - 0.5;
	uv_c.x *= aspect;
	float radius = length(uv_c);
	float angle  = atan(uv_c.y, uv_c.x);

	// Spiral arms that pulse with bass; beat_phase shifts their phase every beat
	float arms   = 4.0 + bass * 3.0;
	float spiral = sin(angle * arms + radius * 12.0 - t * 3.0 + beat_phase * TAU);
	spiral = pow(max(spiral, 0.0), 3.0);

	// Breathing ring: radius expands on energy, punches out on kick (sub_bass)
	float ring_r = 0.15 + energy * 0.08 + sub_bass * 0.06;
	float ring   = exp(-abs(radius - ring_r) * 50.0);

	// Center burst on kick
	float core = exp(-radius * 10.0) * kick * 2.0;

	// Snare flash: a thin cross pattern
	float cross_h = exp(-abs(uv_c.y) * 50.0) * snare;
	float cross_v = exp(-abs(uv_c.x) * 50.0) * snare;
	float cross   = max(cross_h, cross_v) * 0.4;

	// Hihat shimmer: high-freq radial ripple
	float shimmer = sin(radius * 40.0 - t * 8.0) * 0.5 + 0.5;
	shimmer *= exp(-radius * 4.0) * hihat * 0.3;

	float shape = spiral * 0.25 + ring * 0.6 + core + cross + shimmer;

	// Color cycling palette, warped by warmth/brightness from the audio mood
	vec3 shift = vec3(warmth * 0.15, 0.33 + warmth * 0.1, 0.67 + brightness * 0.15);
	vec3 new_col = palette(shape + t * 0.15 + beat_phase * 0.4, shift) * shape;

	// Onset flash: white/warm burst on any transient
	new_col += vec3(0.25, 0.18, 0.10) * onset;

	// ══════════════════════════════════════════════════════════════
	//  PART 3: COMPOSITE — feedback trail + new geometry
	// ══════════════════════════════════════════════════════════════

	vec3 col = trail + new_col;

	// Tonemap then gamma
	col = col / (1.0 + col);
	col = pow(max(col, vec3(0.0)), vec3(0.4545));

	// Film grain
	float grain = texture(noise_tex, uv * 300.0 + fract(t * 0.07)).r;
	col += (grain - 0.5) * 0.025;

	// Vignette
	float vig = 1.0 - smoothstep(0.3, 1.2, length(uv - 0.5) * 1.8);
	col *= mix(0.5, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
