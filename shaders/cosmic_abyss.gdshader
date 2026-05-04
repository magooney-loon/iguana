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

float smootherstep(float x) {
	return x * x * (3.0 - 2.0 * x);
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
	float s_presence = presence;
	float s_flux = flux_bass + flux_mid + flux_treble;
	float s_onset = onset;
	float s_warmth = warmth;
	float s_brightness = brightness;
	
	vec3 col = vec3(0.0);
	
	float arms = 3.0 + s_bass * 2.5;
	
	vec2 feed_uv = uv;
	float amp = 1.0;
	
	for(int i = 0; i < 5; i++) {
		float fi = float(i);
		float phase = t * (0.3 + fi * 0.05);
		
		float r = length(feed_uv) * (0.4 + s_energy * 0.15);
		float a = atan(feed_uv.y, feed_uv.x);
		
		float swing = sin(phase);
		float swing2 = cos(phase * 0.6);
		
		float warp = sin(r * 5.0 - t * 0.4 + fi) * 0.08 * (0.3 + s_mid * 0.4);
		a += swing * 0.1 * (0.2 + s_mid * 0.3) + warp;
		r *= 1.0 + swing2 * 0.04 * s_bass;
		
		feed_uv = vec2(cos(a) * r, sin(a) * r);
		
		feed_uv = rot2d(feed_uv, swing * 0.25 * (0.15 + s_treble * 0.25) + s_beat * 0.15);
		
		float fold = 0.025 + fi * 0.004;
		feed_uv = abs(feed_uv) - fold * (1.0 + s_bass * 0.1);
		feed_uv = rot2d(feed_uv, PI / arms * (0.2 + fi * 0.05) + swing2 * 0.04);
		
		float d = length(feed_uv) - 0.08 - s_bass * 0.03;
		d = abs(d) - 0.002;
		
		float glow = 0.002 / (0.0008 + abs(d));
		glow *= 0.35 + s_energy * 0.25;
		glow = smootherstep(glow);
		
		vec3 shift = vec3(
			s_warmth * 0.05 + fi * 0.02 + swing * 0.01,
			0.33 + s_warmth * 0.05 + fi * 0.02 + swing2 * 0.01,
			0.67 + s_brightness * 0.05 + fi * 0.02
		);
		vec3 layer_col = palette(r * 0.6 - t * 0.05 + fi * 0.03, shift);
		layer_col *= 1.0 + s_beat * 0.35 + s_kick * 0.25;
		
		col += layer_col * glow * amp;
		amp *= 0.4;
		
		feed_uv *= 1.02 + s_energy * 0.003;
		feed_uv = rot2d(feed_uv, beat_phase * 0.004 * beat_confidence);
	}
	
	float ring = length(uv0);
	float angle = atan(uv0.y, uv0.x);
	
	vec3 morph = vec3(0.0);
	
	for(int i = 0; i < 6; i++) {
		float fi = float(i);
		float a = angle + t * (0.12 + fi * 0.04) + fi * PI / 3.0;
		float r = ring;
		
		float pulse = sin(t * (0.4 + fi * 0.1) + fi * 0.8);
		pulse = pulse * 0.5 + 0.5;
		
		float wave = sin(a * (3.0 + s_mid * 3.0 + fi) + t * 0.6 + r * 3.0);
		wave = wave * 0.5 + 0.5;
		
		float morph_r = r + pulse * 0.08 * s_energy + wave * 0.04 * s_mid;
		morph_r *= 1.0 + sin(t * 0.3 + fi) * 0.05 * s_beat;
		
		float ring_pos = 0.12 + fi * 0.04 + s_mid * 0.05;
		float ring_dist = abs(morph_r - ring_pos) - 0.003;
		
		float m = 0.0015 / (0.0006 + abs(ring_dist));
		m *= wave * pulse * (0.1 + s_beat * 0.25 + s_kick * 0.15);
		m = smootherstep(m);
		
		vec3 m_shift = vec3(
			s_warmth * 0.15 + fi * 0.05,
			0.33 + s_warmth * 0.15 + fi * 0.05,
			0.67 + s_brightness * 0.15 + fi * 0.05
		);
		vec3 m_col = palette(t * 0.25 + fi * 0.35, m_shift);
		morph += m_col * m;
	}
	col += morph * 0.55;
	
	vec3 rays = vec3(0.0);
	for(int i = 0; i < 4; i++) {
		float fi = float(i);
		float a = angle + t * (0.15 + fi * 0.06) + fi * PI / 2.0;
		float r = ring;
		
		float ray_wave = sin(a * (2.0 + s_treble * 3.0) + t * 0.5 - r * 6.0);
		ray_wave = max(ray_wave, 0.0);
		
		float ray_r = abs(r - (0.06 + fi * 0.035 + s_bass * 0.04)) - 0.001;
		
		float r_out = 0.001 / (0.0004 + abs(ray_r));
		r_out *= ray_wave * (0.08 + s_onset * 0.3 + s_flux * 0.2);
		r_out = smootherstep(r_out);
		
		vec3 r_col = palette(t * 0.2 + fi * 0.45, vec3(s_warmth * 0.25, 0.33 + s_warmth * 0.25, 0.67 + s_brightness * 0.25));
		rays += r_col * r_out;
	}
	col += rays * 0.35;
	
	float inner = smoothstep(0.5, 0.0, ring * 3.0 / (0.15 + s_energy * 0.2));
	vec3 inner_col = palette(t * 1.5, vec3(s_warmth * 0.3, 0.33 + s_warmth * 0.3, 0.67 + s_brightness * 0.3));
	col += inner_col * inner * (0.15 + s_kick * 0.35 + s_onset * 0.25);
	
	float core = smoothstep(0.8, 0.0, ring * 5.0 / (0.08 + s_beat * 0.15));
	col += vec3(1.0, 0.95, 0.98) * core * (0.1 + s_beat * 0.3 + onset * 0.2);
	
	vec2 tunnel = uv0;
	float tun = 0.0;
	for(int i = 0; i < 3; i++) {
		float fi = float(i);
		float phase = t * (0.1 + fi * 0.04);
		
		tunnel = abs(tunnel) - 0.04 * (1.0 + s_mid * 0.2);
		tunnel = rot2d(tunnel, phase + fi * PI / 3.0 + s_beat * 0.2);
		
		float d = length(tunnel) - 0.06 - fi * 0.03;
		d = abs(d) - 0.001;
		
		float t_glow = 0.0015 / (0.0005 + abs(d));
		t_glow *= (0.05 + s_presence * 0.1);
		tun += t_glow;
	}
	col += vec3(0.25, 0.5, 0.85) * tun * 0.25;
	
	float outer = abs(ring - 0.32 - s_treble * 0.08);
	outer = smoothstep(0.02, 0.0, outer);
	col += vec3(0.3, 0.25, 0.7) * outer * s_treble * 0.3;
	
	col *= 0.38 + s_brightness * 0.45;
	col.r *= 1.0 + s_warmth * 0.03;
	col.b *= 1.0 + s_brightness * 0.025;
	
	col = col / (1.0 + col);
	col = pow(col, vec3(0.75));
	col = pow(max(col, vec3(0.0)), vec3(0.4545));
	
	COLOR = vec4(col, 1.0);
}