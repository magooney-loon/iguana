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

#define PI 3.14159265359
#define TAU 6.28318530718

vec2 rot2d(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec3 palette(float t, vec3 shift) {
	vec3 a = vec3(0.5, 0.5, 0.5);
	vec3 b = vec3(0.5, 0.5, 0.5);
	vec3 c = vec3(1.0, 1.0, 1.0);
	return a + b * cos(TAU * (c * t + shift));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= rect_size.x / rect_size.y;
	vec2 uv0 = uv;
	
	float t = time_val;
	
	float s_bass = bass;
	float s_mid = mid;
	float s_treble = treble;
	float s_energy = energy;
	float s_beat = beat;
	float s_kick = kick;
	float s_beat_phase = beat_phase;
	
	float arms = 3.0 + s_bass * 2.5;
	
	vec3 col = vec3(0.0);
	float amp = 1.0;
	
	for(int i = 0; i < 7; i++) {
		float fi = float(i);
		float phase = t * (0.4 + fi * 0.08);
		
		float r = length(uv) * (0.5 + s_energy * 0.2);
		float a = atan(uv.y, uv.x);
		
		float swing = sin(phase);
		float swing2 = cos(phase * 0.7);
		float swing3 = sin(phase * 1.3 + fi * 0.5);
		
		a += swing * 0.1 * (0.3 + s_mid * 0.4);
		a += swing2 * 0.05 * fi;
		
		r *= 1.0 + swing3 * 0.06 * s_bass;
		
		uv = vec2(cos(a) * r, sin(a) * r);
		
		uv = rot2d(uv, swing * 0.3 * (0.2 + s_treble * 0.3) + s_beat_phase * PI * 0.2 * beat_confidence);
		
		float fold_amount = 0.04 + fi * 0.006;
		for(float f = 0.0; f < 2.0; f += 1.0) {
			uv = abs(uv) - fold_amount * (1.0 + s_bass * 0.2);
			uv = rot2d(uv, PI / arms * 0.3 + swing2 * 0.08);
		}
		
		uv = rot2d(uv, s_bass * 0.08 * swing);
		
		float d = length(uv) - 0.12 - s_bass * 0.05;
		d = abs(d) - 0.004;
		
		float glow = 0.004 / (0.0015 + abs(d));
		glow *= 0.45 + s_energy * 0.35;
		
		vec3 shift = vec3(
			warmth * 0.08 + fi * 0.03 + swing * 0.02,
			0.33 + warmth * 0.08 + fi * 0.03 + swing2 * 0.02,
			0.67 + brightness * 0.08 + fi * 0.03
		);
		vec3 layer_col = palette(r * 0.8 - t * 0.08 + fi * 0.04, shift);
		
		float beat_boost = 1.0 + s_beat * 0.6 + s_kick * 0.4;
		layer_col *= beat_boost;
		
		col += layer_col * glow * amp;
		amp *= 0.45;
		
		uv *= 1.02 + s_energy * 0.004;
		uv = rot2d(uv, s_beat_phase * 0.008 * beat_confidence);
	}
	
	float ring = length(uv0);
	float ring_glow = exp(-ring * 8.0 / (0.3 + s_energy * 0.3));
	col += vec3(0.3, 0.5, 0.9) * ring_glow * (0.15 + s_treble * 0.2);
	
	col *= 0.45 + brightness * 0.5;
	col.r *= 1.0 + warmth * 0.05;
	col.b *= 1.0 + brightness * 0.03;
	
	col = col / (1.0 + col);
	col = pow(col, vec3(0.8));
	col = pow(max(col, vec3(0.0)), vec3(0.4545));
	
	COLOR = vec4(col, 1.0);
}