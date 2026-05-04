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
	float tb = t * 0.35;
	
	float arms = 3.0 + floor(bass * 4.0);
	float scale = 0.75 + energy * 0.3;
	
	vec3 col = vec3(0.0);
	float amp = 1.0;
	
	for(int i = 0; i < 5; i++) {
		float fi = float(i);
		
		float r = length(uv) * scale;
		float a = atan(uv.y, uv.x);
		
		r *= 1.0 + bass * 0.25 * sin(a * arms + fi * 0.5 + tb);
		a += r * (0.2 + mid * 0.4);
		
		float wave = sin(r * 4.5 - t * 1.2 + a * 2.5) * 0.03 * (1.0 + mid * 0.5);
		uv = vec2(cos(a + wave) * r, sin(a + wave) * r);
		
		for(int j = 0; j < 2; j++) {
			uv = abs(uv) - 0.1 * (1.0 + bass * 0.15);
			uv = rot2d(uv, PI / arms * 0.7);
		}
		
		uv = rot2d(uv, bass * PI * 0.1 * sin(tb * 0.5));
		
		float d = length(uv) - 0.22 - bass * 0.12;
		d = abs(d) - 0.012 * (1.0 + treble * 0.3);
		
		float glow = 0.012 / (0.006 + abs(d));
		glow *= 0.7 + energy * 0.3;
		
		vec3 shift = vec3(warmth * 0.2 + fi * 0.07, 0.33 + warmth * 0.2 + fi * 0.07, 0.67 + brightness * 0.2 + fi * 0.07);
		vec3 layer_col = palette(r * 1.6 - t * 0.2 + fi * 0.1, shift);
		
		layer_col *= 1.0 + (beat * 0.3 + kick * 0.2) * (1.0 - fi * 0.1);
		
		col += layer_col * glow * amp;
		amp *= 0.6;
		
		uv *= 1.05 + energy * 0.01;
		uv = rot2d(uv, beat_phase * TAU * 0.04 * beat_confidence);
	}
	
	col *= 0.55 + brightness * 0.4;
	col.r *= 1.0 + warmth * 0.12;
	col.b *= 1.0 + brightness * 0.08;
	
	col = col / (1.0 + col);
	col = pow(col, vec3(0.88));
	col = pow(max(col, vec3(0.0)), vec3(0.4545));
	
	COLOR = vec4(col, 1.0);
}