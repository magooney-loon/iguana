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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for(int i = 0; i < 5; i++) {
		sum += noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

vec3 palette(float t, float shift) {
	vec3 a = vec3(0.5, 0.5, 0.5);
	vec3 b = vec3(0.5, 0.5, 0.5);
	vec3 c = vec3(1.0, 1.0, 1.0);
	vec3 d = vec3(0.0 + shift * 0.33, 0.33 + shift * 0.33, 0.67 + shift * 0.33);
	return a + b * cos(TAU * (c * t + d));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= rect_size.x / rect_size.y;
	vec2 uv0 = uv;
	
	float t = time_val;
	float tb = t * 0.5;
	
	// Bass defines main shape complexity - number of radial arms
	float arms = 3.0 + floor(bass * 5.0);
	
	// Mid controls spiral tightness
	float spiral = 0.3 + mid * 0.8;
	
	// Treble adds high-frequency detail ripples
	float detail = presence * 8.0 + treble * 16.0;
	
	// Beat triggers geometry morphs
	float beat_morph = kick * 2.0 + beat * 1.0;
	
	// Energy overall scale
	float scale = 0.8 + energy * 0.4;
	
	// Activity drives motion intensity
	float motion = activity * 2.0;
	
	vec3 col = vec3(0.0);
	float amp = 1.0;
	
	// Multiple iteration layers - Milkdrop-style feedback
	for(int i = 0; i < 6; i++) {
		float fi = float(i);
		
		// Polar coordinates
		float r = length(uv) * scale;
		float a = atan(uv.y, uv.x);
		
		// Radial modulation from bass
		r *= 1.0 + bass * 0.5 * sin(a * arms + fi * 0.7 + t);
		
		// Beat-synced pulse
		r *= 1.0 - beat_morph * 0.15 * sin(tb + fi);
		
		// Spiral fold
		a += r * spiral * (1.0 + sin(tb) * 0.2);
		
		// Wave distortion
		float wave = sin(r * 6.0 - t * 2.0 + a * 4.0) * 0.05 * (1.0 + mid);
		uv = vec2(cos(a + wave) * r, sin(a + wave) * r);
		
		// Fold and rotate - multiple symmetry
		for(int j = 0; j < 3; j++) {
			uv = abs(uv) - 0.15 * (1.0 + bass * 0.3);
			uv = rot2d(uv, PI / arms * (1.0 + energy * 0.5));
		}
		
		// Bass-reactive secondary rotation
		uv = rot2d(uv, bass * PI * 0.25 * sin(tb));
		
		// Distance to shape
		float d = length(uv) - 0.3 - bass * 0.2;
		
		// Shape modulation
		d = abs(d) - 0.02 * (1.0 + treble * 0.5);
		
		// Glow accumulation
		float glow = 0.02 / (0.01 + abs(d));
		glow *= smoothstep(0.0, 1.0, energy);
		
		// Color per iteration - shifts with warmth/brightness
		float shift = warmth + fi * 0.1 + brightness * 0.5;
		vec3 layer_col = palette(r * 2.0 - t * 0.3 + fi * 0.15, shift);
		
		// Audio-reactive color boost
		layer_col *= 1.0 + flux_bass * 0.3;
		layer_col *= 1.0 + flux_mid * 0.2;
		layer_col *= 1.0 + flux_treble * 0.1;
		
		// Beat pulse brightness
		layer_col *= 1.0 + beat * 0.4 * (1.0 - fi * 0.1);
		
		// Accumulate
		col += layer_col * glow * amp;
		amp *= 0.7;
		
		// Zoom into next iteration
		uv *= 1.07 + energy * 0.02;
		
		// Rotate per beat
		uv = rot2d(uv, beat_phase * TAU * 0.1 * beat_confidence);
	}
	
	// Outer ring - treble detail
	float ring_r = length(uv0);
	float ring = abs(ring_r - 0.35 - treble * 0.1) - 0.02;
	ring = abs(ring) - 0.005;
	col += vec3(0.3, 0.5, 1.0) * (0.01 / (0.001 + ring)) * treble * 0.5;
	
	// Inner glow - bass/kick
	float inner = length(uv0) - 0.15;
	col += vec3(1.0, 0.4, 0.1) * (kick * 0.5) * exp(-inner * 8.0);
	
	// Center flash - kick/snare
	float center = length(uv0);
	col += vec3(1.0, 0.8, 0.6) * onset * 0.3 * exp(-center * 4.0);
	
	// Mid-range ring modulation
	float mid_ring = abs(ring_r - 0.25 - mid * 0.15);
	col += palette(mid_ring * 10.0 + t, warmth) * (0.005 / (0.001 + mid_ring)) * mid * 0.3;
	
	// Noise texture overlay - density
	vec2 noise_uv = UV * 2.0 + vec2(t * 0.1, t * 0.15);
	float n = fbm(noise_uv * 4.0);
	col += vec3(n) * density * 0.15;
	
	// Beat phase scan line
	float scan = abs(UV.y - (0.5 + beat_phase * 0.5 - beat_confidence * 0.25));
	scan = smoothstep(0.01, 0.0, scan) * beat_confidence * 0.2;
	col += vec3(0.8, 0.9, 1.0) * scan;
	
	// Hihat sparkle points
	for(int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 spark_uv = vec2(
			sin(fi * 1.618 + t * 2.0),
			cos(fi * 2.317 + t * 1.5)
		) * 0.4;
		float spark = length(uv0 - spark_uv);
		spark = smoothstep(0.015, 0.0, spark);
		col += vec3(1.0, 0.95, 0.9) * spark * hihat * 0.4;
	}
	
	// Overall brightness adjustment
	col *= 0.6 + brightness * 0.4;
	
	// Warmth color shift
	col.r *= 1.0 + warmth * 0.2;
	col.b *= 1.0 + brightness * 0.1;
	
	// Tonemap
	col = col / (1.0 + col);
	
	// Contrast
	col = pow(col, vec3(0.9));
	
	// Gamma
	col = pow(max(col, vec3(0.0)), vec3(0.4545));
	
	COLOR = vec4(col, 1.0);
}