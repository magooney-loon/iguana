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

// Tunnel spine path – wider, more dramatic curves than Squiggly
vec3 path(float z) {
	return vec3(
		cos(z * 0.015) * 16.0 + cos(z * 0.006) * 64.0,
		cos(z * 0.011) * 24.0 + cos(z * 0.009) * 32.0,
		z
	);
}

// Camera z-position – pure time, no audio
float cam_t() {
	return sin(time_val * 0.6) * 64.0 + time_val * 200.0;
}

// Rotation matrix from R() macro
mat2 rot2(float a) {
	vec4 v = cos(a + vec4(0.0, 33.0, 11.0, 0.0));
	return mat2(vec2(v.x, v.y), vec2(v.z, v.w));
}

// Repeating box SDF (larger grid than Squiggly: 40 vs 20)
float boxen(vec3 p) {
	p = abs(fract(p / 40.0) * 40.0 - 20.0) - 2.0;
	return min(p.x, min(p.y, p.z));
}

// Scene SDF with light accumulation
float scene_map(vec3 p, inout vec4 lights) {
	vec3 q = path(p.z);
	float g = q.y - p.y + 6.0;
	float m = boxen(p);
	p.xy -= q.xy;

	// Two squiggly neon tubes – different Y-based waves than Squiggly
	float red = length(p.xy - sin(p.y / 12.0 + vec2(5.0, 1.0)) * 12.0) - 1.0;
	float blue = length(p.xy - sin(p.y / 12.0 + vec2(0.0, 1.0)) * 12.0) - 1.0;
	float e = min(red, blue);

	// Event-driven light colors – amber + emerald, no pink
	float pulse = 1.0 + beat * 0.3 + onset * 0.15;

	// Amber tube: kick flares, flux_bass shifts hotter
	float amber_r = 10.0 + kick * 6.0 + flux_bass * 4.0;
	float amber_g = 4.0 + flux_bass * 2.0;
	lights += vec4(amber_r, amber_g, 0.15, 0.0) * pulse / (0.1 + abs(red) / 10.0);

	// Emerald tube: hihat flares, flux_treble shifts cooler
	float emerald_g = 6.0 + hihat * 4.0 + flux_treble * 2.0;
	float emerald_b = 4.0 + hihat * 3.0 + flux_treble * 3.0;
	lights += vec4(0.15, emerald_g, emerald_b, 0.0) * pulse / (0.1 + abs(blue) / 10.0);

	// Wall texture detail – density sharpens pattern
	p = abs(p);
	float detail = mix(30.0, 15.0, density);
	float tex = abs(length(sin(p * cos(p.yzx / detail) * 4.0) / (p * 4.0)));
	float tun = min(64.0 - p.x - p.y + m, 32.0 - p.y - m);
	float d = max(min(m, g), tun) - tex;
	return min(e, d);
}

void fragment() {
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 u = (UV * rect_size - rect_size * 0.5) / min_dim;
	u.y -= 0.2;

	vec4 o = vec4(0.0);
	float t = cam_t();
	vec3 p = path(t);
	vec3 ro = p;
	vec3 Z = normalize(path(t + 10.0) - p);
	vec3 X = normalize(vec3(Z.z, 0.0, -Z.x));

	// Camera rotation – pure sine drift
	float cam_rot = sin(t * 0.005) * 0.4;
	vec3 D = normalize(vec3(rot2(cam_rot) * u, 1.0) * mat3(-X, cross(X, Z), Z));

	vec4 lights = vec4(0.0);
	float d = 0.0;

	// Primary raymarch (128 steps)
	for (int i = 0; i < 128; i++) {
		p = ro + D * d;
		float s = scene_map(p, lights) * 0.8;
		d += s;
		o += lights + vec4(0.6, 0.45, 0.25, 1.0) / max(s, 0.01);
	}

	// Normal via tetrahedron offsets
	float h = 0.005;
	vec2 k = vec2(1.0, -1.0);
	vec3 n = normalize(
		k.xyy * scene_map(p + k.xyy * h, lights) +
		k.yyx * scene_map(p + k.yyx * h, lights) +
		k.yxy * scene_map(p + k.yxy * h, lights) +
		k.xxx * scene_map(p + k.xxx * h, lights)
	);

	// Diffuse lighting
	o *= (0.1 + max(dot(n, -D), 0.0));

	// Reflection pass (40 steps)
	vec4 ref = vec4(0.0);
	lights = vec4(0.0);
	D = reflect(D, n);
	p += n * 0.05;
	float s_ref = 0.0;
	for (int i = 0; i < 40; i++) {
		p += D * s_ref;
		s_ref = scene_map(p, lights) * 0.8;
		ref += lights + vec4(0.6, 0.45, 0.25, 1.0) / max(s_ref, 0.01);
	}

	o += o * ref;

	// Tone mapping – warm fog, no pink
	vec4 fog_tint = vec4(
		10.0 + warmth * 4.0,
		4.0 + flux_mid * 2.0,
		2.0 + brightness * 2.0,
		0.0
	);
	o = tanh(o / 6e6 / d * (1.0 + energy * 0.5));

	// Onset flash – neutral white punch
	o += vec4(0.1 * onset);

	// Beat-phase brightness swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	o *= 1.0 + phase_pulse * beat_confidence * 0.2;

	COLOR = vec4(clamp(o.rgb, 0.0, 1.0), 1.0);
}
