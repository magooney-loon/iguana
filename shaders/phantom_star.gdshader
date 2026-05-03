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

// ── Constants ────────────────────────────────────────────────────────
const float PI2 = PI * 2.0;

// ── Helper functions ─────────────────────────────────────────────────
mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec2 pmod(vec2 p, float r) {
	float a = atan(p.x, p.y) + PI / r;
	float n = PI2 / r;
	a = floor(a / n) * n;
	return p * rot(-a);
}

float box_sdf(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

// IFS folded box – rotations are pure time for smooth morphing
float ifs_box(vec3 p) {
	for (int i = 0; i < 5; i++) {
		p = abs(p) - 1.0;
		p.xy *= rot(time_val * 0.3);
		p.xz *= rot(time_val * 0.1);
	}
	p.xz *= rot(time_val);
	return box_sdf(p, vec3(0.4, 0.8, 0.3));
}

float map(vec3 p) {
	vec3 p1 = p;
	p1.x = mod(p1.x - 5.0, 10.0) - 5.0;
	p1.y = mod(p1.y - 5.0, 10.0) - 5.0;
	p1.z = mod(p1.z, 16.0) - 8.0;
	p1.xy = pmod(p1.xy, 5.0);
	return ifs_box(p1);
}

void fragment() {
	float min_dim = min(rect_size.x, rect_size.y);
	vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);

	// Camera – pure time, no audio jitter
	float t_cam = time_val;
	vec3 c_pos = vec3(0.0, 0.0, -3.0 * t_cam);
	vec3 c_dir = normalize(vec3(0.0, 0.0, -1.0));
	vec3 c_up = vec3(sin(t_cam), 1.0, 0.0);
	vec3 c_side = cross(c_dir, c_up);
	vec3 ray = normalize(c_side * p.x + c_up * p.y + c_dir);

	// Phantom raymarch – glow accumulation
	float acc = 0.0;
	float acc2 = 0.0;
	float t = 0.0;

	// Glow falloff: energy tightens the glow, beat/onset punch it
	float glow_falloff = 3.0 + energy * 4.0;

	for (int i = 0; i < 99; i++) {
		vec3 pos = c_pos + ray * t;
		float dist = map(pos);
		dist = max(abs(dist), 0.02);

		float a = exp(-dist * glow_falloff);

		// Phantom pulse – synced to beat_phase for musical timing
		float phantom_phase = mod(length(pos) + 24.0 * time_val, 30.0);
		if (phantom_phase < 3.0) {
			a *= 2.0;
			acc2 += a;
		}

		acc += a;
		t += dist * 0.5;
	}

	// Audio-reactive color palette:
	// Base: warm amber/gold tones (no pink!)
	// acc2 (phantom glow) shifts toward emerald/green
	float base_r = acc * 0.011;
	float base_g = acc * 0.013 + acc2 * 0.004;
	float base_b = acc * 0.008 + acc2 * 0.002;

	// Kick adds amber intensity, hihat adds emerald shimmer
	base_r += kick * acc * 0.008;
	base_g += hihat * acc2 * 0.004;
	base_b += flux_treble * acc2 * 0.002;

	// Mood tint: warmth boosts amber, brightness boosts emerald highlights
	vec3 col = vec3(
		base_r * (1.0 + warmth * 0.6),
		base_g * (1.0 + warmth * 0.3 + brightness * 0.3),
		base_b * (1.0 + brightness * 0.4)
	);

	// Onset flash – neutral white punch
	col += vec3(0.08 * onset);

	// Beat-phase brightness swell
	float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.2;

	float alpha = 1.0 - t * 0.03;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha += beat * 0.1;
	alpha = clamp(alpha, 0.0, 1.0);

	COLOR = vec4(clamp(col, 0.0, 1.0), alpha);
}
