shader_type canvas_item;

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
uniform float bpm = 120.0;
uniform float time_val = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

// KIFS fold: abs(sin) trap + inverse-square scale.
// Bass shifts the phase, treble adds high-frequency detail.
void fold(inout vec3 p, inout float w, float phase, float freq) {
	p = abs(sin(p * freq + phase));
	float l = 4.0 / dot(p, p);
	p *= l;
	w *= l;
}

float map(vec3 p) {
	float t = time_val;
	float phase = bass * 0.2;
	float freq = 1.0 + treble * 0.3;

	// Sub-bass zooms into/out of the fractal structure.
	float scale = 20.0 + sub_bass * 5.0;

	float w = 0.5;
	p /= scale;
	p.z += t / 2.0;

	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);
	fold(p, w, phase, freq);

	return length(p * scale) / w;
}

// Soft shadow — 4 samples toward an orbiting sun.
float calc_light(vec3 p) {
	float t = time_val;
	float s = 0.0;

	// Sun orbits with time; warmth/brightness shift each axis differently.
	vec3 sun = cos(t + p.yzx / 2.0 + vec3(0.0, warmth, brightness)) * 20.0;
	p.x += t * 10.0;

	s += map(p + sun * 0.1);
	s += map(p + sun * 0.2);
	s += map(p + sun * 0.4);
	s += map(p + sun * 0.8);

	return exp(-s * 0.2);
}

void fragment() {
	vec2 r = rect_size;
	vec2 u = (UV * rect_size * 2.0 - r) / r.y;

	float a = 1.0;
	vec3 p;
	vec3 D = normalize(vec3(u, 1.0));

	// Single-step march at distance 30.
	p = D * a * 30.0;
	float d = map(p);

	// Fog absorption — density thickens it.
	a *= exp(-d * (0.1 + density * 0.05));

	float l = calc_light(p);

	// Color base shifts between warm orange and cool blue.
	vec3 base = mix(vec3(4.0, 2.0, 1.0), vec3(1.0, 3.0, 4.0), brightness * 0.5);
	base = mix(base, vec3(4.0, 1.5, 0.5), warmth * 0.3);

	vec3 col = base * a * d * l;

	// Tonemap.
	col = tanh(col * col);

	// Energy brightness.
	col *= 0.7 + energy * 0.5;

	// Beat pulse.
	col *= 1.0 + beat * 0.2;

	// Kick warm flash.
	col += vec3(0.1, 0.05, 0.02) * kick;

	// Snare cool flash.
	col += vec3(0.02, 0.05, 0.1) * snare;

	// Onset flash.
	col += vec3(0.05) * onset;

	// Beat phase pulse.
	float phase_pulse = pow(beat_phase, 3.0) * beat_confidence;
	col *= 1.0 + phase_pulse * 0.1;

	// Gamma.
	col = pow(max(col, vec3(0.0)), vec3(0.4545));

	COLOR = vec4(col, 1.0);
}
