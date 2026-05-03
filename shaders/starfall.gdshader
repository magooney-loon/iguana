shader_type canvas_item;

// ── Audio engine uniforms ────────────────────────────────────────────
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;

uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;

uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;

uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;

uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm         = 120.0;
uniform float time_val    = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

// ── Helper functions ─────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float oct_box(vec3 pos, float scale) {
	pos *= scale;
	float base = sd_box(pos, vec3(0.4, 0.4, 0.1)) / 1.5;
	pos.xy *= 5.0;
	pos.y -= 3.5;
	pos.xy *= rot(0.75);
	float result = -base;
	return result;
}

float box_set(vec3 pos, float g_time) {
	vec3 pos_origin = pos;

	// Audio drives the oscillation amplitude: bass expands the spread,
	// kick adds punch, snare adds sudden jitter.
	float swing = 2.5 + bass * 2.0;
	float scale_mod = 1.5 + sub_bass * 1.2;
	float wobble = sin(g_time * 0.4) * swing;

	pos = pos_origin;
	pos.y += wobble;
	pos.xy *= rot(0.8 + snare * 0.3);
	float box1 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.y -= wobble;
	pos.xy *= rot(0.8 - snare * 0.2);
	float box2 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.x += wobble;
	pos.xy *= rot(0.8 + kick * 0.4);
	float box3 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.x -= wobble;
	pos.xy *= rot(0.8 - kick * 0.3);
	float box4 = oct_box(pos, 2.0 - abs(sin(g_time * 0.4)) * scale_mod);

	pos = pos_origin;
	pos.xy *= rot(0.8);
	float box5 = oct_box(pos, 0.5) * 6.0;

	pos = pos_origin;
	float box6 = oct_box(pos, 0.5) * 6.0;

	return max(max(max(max(max(box1, box2), box3), box4), box5), box6);
}

float map(vec3 pos, float g_time) {
	return box_set(pos, g_time);
}

void fragment() {
	// Normalized screen coordinates centered at origin
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);

	// Camera driven only by smooth time_val – no audio uniforms on the rig
	float t = time_val;

	vec3 ro = vec3(0.0, -0.2, t * 4.0);
	vec3 ray = normalize(vec3(p, 1.5));

	// Gentle sine-only sway – pure math, no frame-to-frame jitter
	float sway_xy = sin(t * 0.02) * 0.25 + sin(t * 0.007) * 0.1;
	float sway_yz = cos(t * 0.015) * 0.06 + sin(t * 0.005) * 0.04;
	ray.xy = ray.xy * rot(sway_xy);
	ray.yz = ray.yz * rot(sway_yz);

	float dist = 0.1;
	vec3 col = vec3(0.0);
	float ac = 0.0;

	// Raymarching loop – step count modulated by density for richer detail
	int steps = 60 + int(density * 39.0);
	for (int i = 0; i < 99; i++) {
		if (i >= steps) break;

		vec3 pos = ro + ray * dist;
		pos = mod(pos - 2.0, 4.0) - 2.0;
		float g_time = t - float(i) * 0.01;

		float d = map(pos, g_time);
		d = max(abs(d), 0.01);

		// Glow accumulation – beat pulses the glow radius, onset adds flashes
		float glow_strength = 23.0 + beat * 25.0 + onset * 15.0;
		ac += exp(-d * glow_strength);

		dist += d * (0.55 - beat * 0.03);
	}

	// Base glow color from accumulated light
	col = vec3(ac * 0.02);

	// Audio-reactive color palette:
	// Each frequency band drives its own color channel
	float hue_shift = beat_phase * 6.28318;
	vec3 band_color = vec3(
		0.5 + 0.5 * sin(hue_shift + 0.0),          // red channel cycles with beat
		0.5 + 0.5 * sin(hue_shift + 2.094),        // green channel offset by 120°
		0.5 + 0.5 * sin(hue_shift + 4.189)         // blue channel offset by 240°
	);

	// Bass warms the reds, treble cools the blues, mid boosts greens
	band_color.r += (bass + sub_bass) * 0.35;
	band_color.g += low_mid * 0.2 + mid * 0.15;
	band_color.b += (treble + presence) * 0.3;

	// Warmth/brightness bias the overall palette
	vec3 warm_tint = vec3(0.0, 0.2 * abs(sin(t)), 0.5 + sin(t) * 0.2);
	vec3 cool_tint = vec3(0.1 * abs(cos(t * 0.7)), 0.35, 0.65 + cos(t * 0.5) * 0.15);
	vec3 mood_tint = mix(cool_tint, warm_tint, warmth);

	col += mix(mood_tint, band_color, 0.5 + energy * 0.5);

	// Onset flash: white-hot burst on transients
	col += vec3(0.5, 0.45, 0.4) * onset * 0.35;

	// Beat-phase brightness pulse
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.2;

	// Alpha fades with depth, kick punches it brighter
	float alpha = 1.0 - dist * (0.02 + 0.02 * sin(t));
	alpha = clamp(alpha, 0.0, 1.0);
	alpha += beat * 0.15;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(clamp(col, 0.0, 1.0), alpha);
}
