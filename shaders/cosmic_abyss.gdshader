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
	float s_activity = activity;
	float s_hihat = hihat;
	float s_snare = snare;
	float s_flux_bass = flux_bass;
	float s_flux_mid = flux_mid;
	
	vec3 col = vec3(0.0);
	
	float arms = 3.0 + s_bass * 2.5;
	
	// ── Layer 1: Large-scale fractal backbone (fills screen) ──
	vec2 feed_uv = uv * 1.6;
	float amp = 1.0;
	
	for(int i = 0; i < 8; i++) {
		float fi = float(i);
		float phase = t * (0.3 + fi * 0.05);
		
		float r = length(feed_uv) * (0.5 + s_energy * 0.2);
		float a = atan(feed_uv.y, feed_uv.x);
		
		float swing = sin(phase);
		float swing2 = cos(phase * 0.6);
		
		float warp = sin(r * 4.0 - t * 0.35 + fi) * 0.1 * (0.3 + s_mid * 0.4);
		a += swing * 0.12 * (0.2 + s_mid * 0.3) + warp;
		r *= 1.0 + swing2 * 0.05 * s_bass;
		
		feed_uv = vec2(cos(a) * r, sin(a) * r);
		
		feed_uv = rot2d(feed_uv, swing * 0.25 * (0.15 + s_treble * 0.25) + s_beat * 0.12);
		
		float fold = 0.03 + fi * 0.005;
		feed_uv = abs(feed_uv) - fold * (1.0 + s_bass * 0.12);
		feed_uv = rot2d(feed_uv, PI / arms * (0.2 + fi * 0.05) + swing2 * 0.04);
		
		float d = length(feed_uv) - 0.1 - s_bass * 0.04;
		d = abs(d) - 0.0025;
		
		float glow = 0.003 / (0.001 + abs(d));
		glow *= 0.4 + s_energy * 0.3;
		glow = smootherstep(glow);
		
		vec3 shift = vec3(
			s_warmth * 0.05 + fi * 0.02 + swing * 0.01,
			0.33 + s_warmth * 0.05 + fi * 0.02 + swing2 * 0.01,
			0.67 + s_brightness * 0.05 + fi * 0.02
		);
		vec3 layer_col = palette(r * 0.5 - t * 0.04 + fi * 0.03, shift);
		layer_col *= 1.0 + s_beat * 0.3 + s_kick * 0.2;
		
		col += layer_col * glow * amp;
		amp *= 0.42;
		
		feed_uv *= 1.015 + s_energy * 0.003;
		feed_uv = rot2d(feed_uv, beat_phase * 0.004 * beat_confidence);
	}
	
	// ── Layer 2: Deep detail pass (nested inside, higher frequency) ──
	vec2 deep_uv = uv * 1.8;
	float deep_amp = 0.7;
	float deep_arms = 5.0 + s_mid * 3.0;
	
	for(int i = 0; i < 6; i++) {
		float fi = float(i);
		float phase = t * (0.25 + fi * 0.04) + 1.0;
		
		float r = length(deep_uv) * (0.55 + s_energy * 0.15);
		float a = atan(deep_uv.y, deep_uv.x);
		
		float swing = sin(phase);
		float swing2 = cos(phase * 0.7);
		
		float warp = sin(r * 6.0 - t * 0.5 + fi * 0.5) * 0.06 * (0.4 + s_presence * 0.3);
		a += swing * 0.08 * (0.3 + s_mid * 0.3) + warp;
		r *= 1.0 + swing2 * 0.03 * s_mid;
		
		deep_uv = vec2(cos(a) * r, sin(a) * r);
		
		deep_uv = rot2d(deep_uv, swing * 0.2 * (0.2 + s_presence * 0.2) + s_beat * 0.08);
		
		float fold = 0.02 + fi * 0.003;
		deep_uv = abs(deep_uv) - fold * (1.0 + s_mid * 0.08);
		deep_uv = rot2d(deep_uv, PI / deep_arms * (0.15 + fi * 0.04) + swing2 * 0.03);
		
		float d = length(deep_uv) - 0.06 - s_mid * 0.02;
		d = abs(d) - 0.0015;
		
		float glow = 0.002 / (0.0006 + abs(d));
		glow *= 0.3 + s_energy * 0.2;
		glow = smootherstep(glow);
		
		vec3 shift = vec3(
			s_warmth * 0.1 + fi * 0.03 + swing * 0.015,
			0.4 + s_warmth * 0.08 + fi * 0.025 + swing2 * 0.01,
			0.75 + s_brightness * 0.08 + fi * 0.03
		);
		vec3 layer_col = palette(r * 0.7 - t * 0.06 + fi * 0.04 + 0.2, shift);
		layer_col *= 1.0 + s_snare * 0.25 + s_flux_mid * 0.2;
		
		col += layer_col * glow * deep_amp;
		deep_amp *= 0.38;
		
		deep_uv *= 1.02 + s_mid * 0.004;
		deep_uv = rot2d(deep_uv, -beat_phase * 0.003 * beat_confidence);
	}
	
	// ── Layer 3: Outer halo (wide, soft, bass-reactive) ──
	vec2 halo_uv = uv * 1.2;
	float halo_amp = 0.5;
	
	for(int i = 0; i < 4; i++) {
		float fi = float(i);
		float phase = t * (0.15 + fi * 0.03) + 2.0;
		
		float r = length(halo_uv) * (0.6 + s_bass * 0.15);
		float a = atan(halo_uv.y, halo_uv.x);
		
		float swing = sin(phase);
		float swing2 = cos(phase * 0.5);
		
		a += swing * 0.06;
		r *= 1.0 + swing2 * 0.04 * s_bass;
		
		halo_uv = vec2(cos(a) * r, sin(a) * r);
		
		halo_uv = rot2d(halo_uv, swing * 0.15 + s_beat * 0.06);
		
		float fold = 0.05 + fi * 0.008;
		halo_uv = abs(halo_uv) - fold * (1.0 + s_bass * 0.15);
		halo_uv = rot2d(halo_uv, PI / (2.0 + s_bass) * (0.3 + fi * 0.06) + swing2 * 0.02);
		
		float d = length(halo_uv) - 0.15 - s_bass * 0.06;
		d = abs(d) - 0.004;
		
		float glow = 0.005 / (0.002 + abs(d));
		glow *= 0.35 + s_energy * 0.25;
		glow = smootherstep(glow) * 0.5;
		
		vec3 shift = vec3(
			s_warmth * 0.15 + fi * 0.04,
			0.25 + s_warmth * 0.1 + fi * 0.03,
			0.5 + s_brightness * 0.1 + fi * 0.04
		);
		vec3 layer_col = palette(r * 0.4 - t * 0.03 + fi * 0.05 + 0.4, shift);
		layer_col *= 1.0 + s_kick * 0.3;
		
		col += layer_col * glow * halo_amp;
		halo_amp *= 0.45;
		
		halo_uv *= 1.03;
		halo_uv = rot2d(halo_uv, beat_phase * 0.002);
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
	
	// ── Floating particles (noise-driven, asymmetrical) ──
	float noise_val = texture(noise_tex, UV * 3.0 + vec2(t * 0.02, t * 0.015)).r;
	float noise_val2 = texture(noise_tex, UV * 5.0 - vec2(t * 0.03, t * 0.025)).r;
	
	vec3 particles = vec3(0.0);
	for(int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 offset = vec2(
			sin(fi * 2.39 + t * 0.1),
			cos(fi * 3.17 + t * 0.08)
		) * (0.2 + s_energy * 0.15);
		
		vec2 p_pos = uv0 + offset;
		float p_noise = texture(noise_tex, p_pos * 4.0 + t * 0.02).r;
		
		float p_size = 0.003 + p_noise * 0.006 * (1.0 + s_treble * 0.5);
		float p_dist = length(p_pos - vec2(
			sin(fi * 1.7 + t * (0.05 + fi * 0.01)),
			cos(fi * 2.3 + t * (0.04 + fi * 0.012))
		) * (0.15 + s_mid * 0.1));
		
		float p = smoothstep(p_size, 0.0, p_dist);
		p *= p_noise * (0.3 + s_activity * 0.5);
		
		vec3 p_col = palette(fi * 0.15 + t * 0.1, vec3(s_warmth * 0.2, 0.33, 0.67 + s_brightness * 0.2));
		particles += p_col * p;
	}
	col += particles * (0.12 + s_hihat * 0.08);
	
	// ── Organic blobs (noise-thresholded, irregular shapes) ──
	vec3 blobs = vec3(0.0);
	float blob_noise = texture(noise_tex, uv0 * 2.0 + vec2(sin(t * 0.07) * 0.1, cos(t * 0.05) * 0.08)).r;
	float blob_noise2 = texture(noise_tex, uv0 * 3.0 - vec2(cos(t * 0.06) * 0.12, sin(t * 0.09) * 0.06)).r;
	
	float blob = smoothstep(0.55 - s_bass * 0.15, 0.65 + s_bass * 0.1, blob_noise);
	blob *= smoothstep(0.5, 0.7, blob_noise2);
	blob = blob * 0.5 + blob * blob * 0.5;
	
	vec3 blob_col = palette(t * 0.08 + s_warmth * 0.3, vec3(0.1 + s_warmth * 0.15, 0.4, 0.7));
	blobs += blob_col * blob * (0.06 + s_energy * 0.08);
	
	float blob2 = smoothstep(0.45, 0.65, blob_noise * blob_noise2);
	blob2 *= smoothstep(0.3, 0.5, texture(noise_tex, uv0 * 1.5 + t * 0.01).r);
	vec3 blob2_col = palette(t * 0.12 + s_brightness * 0.2, vec3(0.5, 0.6 + s_brightness * 0.1, 0.3 + s_warmth * 0.2));
	blobs += blob2_col * blob2 * (0.04 + s_mid * 0.06);
	
	col += blobs;
	
	// ── Light streaks (horizontal/vertical, beat-reactive) ──
	vec3 streaks = vec3(0.0);
	
	float h_stripe = abs(sin(uv.y * 50.0 + t * 0.5 + sin(uv.x * 3.0) * 2.0));
	h_stripe = pow(h_stripe, 8.0 + s_bass * 12.0);
	h_stripe *= smoothstep(0.5, 0.0, abs(uv.y - 0.3 - sin(t * 0.2) * 0.1));
	
	vec3 h_col = palette(t * 0.15, vec3(s_warmth * 0.2, 0.25, 0.55 + s_brightness * 0.15));
	streaks += h_col * h_stripe * (0.05 + s_beat * 0.12);
	
	float v_stripe = abs(cos(uv.x * 40.0 - t * 0.3 + cos(uv.y * 2.5) * 1.5));
	v_stripe = pow(v_stripe, 10.0 + s_mid * 8.0);
	v_stripe *= smoothstep(0.4, 0.0, abs(uv.x + 0.2 + cos(t * 0.15) * 0.08));
	
	vec3 v_col = palette(t * 0.2 + 0.33, vec3(0.2 + s_warmth * 0.1, 0.35, 0.6 + s_brightness * 0.1));
	streaks += v_col * v_stripe * (0.04 + s_snare * 0.1);
	
	col += streaks;
	
	// ── Light leak (asymmetrical corner glow) ──
	vec3 leak = vec3(0.0);
	float leak_mask = smoothstep(0.6, 0.0, length(UV - vec2(0.85, 0.15)));
	leak_mask *= smoothstep(0.3, 0.0, texture(noise_tex, vec2(t * 0.03, 0.5)).r - 0.4);
	vec3 leak_col = palette(t * 0.2, vec3(s_warmth * 0.3, 0.15, 0.45 + s_brightness * 0.2));
	leak += leak_col * leak_mask * (0.2 + s_energy * 0.3);
	
	float leak_mask2 = smoothstep(0.5, 0.0, length(UV - vec2(0.1, 0.8)));
	leak_mask2 *= smoothstep(0.35, 0.0, texture(noise_tex, vec2(0.5, t * 0.025)).r - 0.35);
	vec3 leak_col2 = palette(t * 0.15 + 0.5, vec3(0.5 + s_warmth * 0.2, 0.25, 0.15 + s_brightness * 0.1));
	leak += leak_col2 * leak_mask2 * (0.15 + s_flux_bass * 0.3);
	
	col += leak * 0.1;
	
	// ── Film grain ──
	float grain = texture(noise_tex, UV * 200.0 + fract(t * 0.1)).r;
	grain = (grain - 0.5) * 0.04 * (1.0 + s_energy * 0.5);
	col += grain;
	
	// ── Subtle vignette ──
	float vignette = 1.0 - smoothstep(0.3, 1.2, length(UV - 0.5) * 1.8);
	vignette = mix(0.6, 1.0, vignette);
	col *= vignette;
	
	col *= 0.38 + s_brightness * 0.45;
	col.r *= 1.0 + s_warmth * 0.03;
	col.b *= 1.0 + s_brightness * 0.025;
	
	col = col / (1.0 + col);
	col = pow(col, vec3(0.75));
	col = pow(max(col, vec3(0.0)), vec3(0.4545));
	
	COLOR = vec4(col, 1.0);
}