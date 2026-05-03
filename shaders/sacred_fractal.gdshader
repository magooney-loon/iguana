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

vec2 rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec2 rotCenter(vec2 p, vec2 c, float a) {
	p -= c;
	float c2 = cos(a), s2 = sin(a);
	return vec2(p.x * c2 - p.y * s2, p.x * s2 + p.y * c2) + c;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, float t) {
	float f = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		f += amp * noise(p + t * 0.03 * float(i + 1));
		p *= 2.0;
		amp *= 0.5;
	}
	return f;
}

// Wider fbm with more octaves for richer flowing distortion
float fbmRich(vec2 p, float t) {
	float f = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 7; i++) {
		f += amp * noise(p * freq + t * 0.025 * float(i + 1));
		freq *= 2.0;
		amp *= 0.5;
	}
	return f;
}

float voronoi(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i + neighbor);
			point = 0.5 + 0.5 * sin(t * 0.5 + TAU * point);
			float dist = length(neighbor + point - f);
			d = min(d, dist);
		}
	}
	return d;
}

float sdCircle(vec2 p, float r) {
	return length(p) - r;
}

float sdHexagon(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

float sdStar(vec2 p, float r, int points, float ratio) {
	float an = PI / float(points);
	float en = an * ratio;
	vec2 acs = vec2(cos(an), sin(an));
	vec2 ecs = vec2(cos(en), sin(en));
	float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
	p = length(p) * vec2(cos(bn), abs(sin(bn)));
	p -= r * acs;
	p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
	return clamp(-dot(p, vec2(sign(p.x), 0.0)), -r, 0.0) - length(p);
}

// Soft blob with texture noise for smooth wobble
float sdBlob(vec2 p, float r, float t, float wobble) {
	float d = length(p);
	float angle = atan(p.y, p.x);
	float wobble_n = texture(noise_tex, vec2(angle * 1.5, d * 3.0) * 0.15 + t * 0.02).r * 0.1
	               + texture(noise_tex, vec2(angle * 3.5 - t * 0.015, d * 5.0) * 0.15).r * 0.06
	               + texture(noise_tex, vec2(angle * 6.0 + t * 0.01, d * 1.5 + 3.0) * 0.15).r * 0.03;
	wobble_n *= wobble;
	return d - r - wobble_n;
}

// Edge detail — slower time to avoid jitter, capped at 3 octaves
float edgeDetail(vec2 p, float t, float scale) {
	return texture(noise_tex, p * scale * 0.15 + t * 0.015).r * 0.5
	     + texture(noise_tex, p * scale * 0.3 + t * 0.01 + 5.0).r * 0.25
	     + texture(noise_tex, p * scale * 0.5 + t * 0.008 + 10.0).r * 0.125;
}

// Organic ring: texture noise for smooth, jitter-free variation
float organicRing(vec2 p, float r, float base_thickness, float t, float audio) {
	float angle = atan(p.y, p.x);
	float r_wobble = texture(noise_tex, vec2(angle * 2.0 + t * 0.02, r * 3.0) * 0.15).r * 0.025
	              + texture(noise_tex, vec2(angle * 5.0 - t * 0.015, r * 6.0 + 3.0) * 0.15).r * 0.012;
	float thick_mod = 1.0 + texture(noise_tex, vec2(angle * 3.5 + t * 0.012, r * 5.0) * 0.15).r * 0.6 - 0.3;
	return abs(length(p) - r - r_wobble) - base_thickness * max(thick_mod, 0.3);
}

vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	return a + b * cos(TAU * (c * t + d));
}

vec3 sacredPalette(float t, float w, float br, float d_) {
	vec3 a = vec3(0.5, 0.5, 0.5);
	vec3 b = vec3(0.5, 0.5, 0.5);
	vec3 c = vec3(1.0, 1.0, 1.0);
	vec3 d = vec3(0.0, 0.33, 0.67);

	vec3 deep_moss = vec3(0.12, 0.18, 0.14);
	vec3 dustypurp = vec3(0.30, 0.20, 0.35);
	vec3 softteal = vec3(0.15, 0.30, 0.32);
	vec3 warmcream = vec3(0.42, 0.32, 0.25);
	vec3 mutedrose = vec3(0.38, 0.22, 0.32);
	vec3 acidgreen = vec3(0.25, 0.40, 0.20);
	vec3 deepblue = vec3(0.10, 0.18, 0.28);

	vec3 base1 = mix(deep_moss, dustypurp, w);
	vec3 base2 = mix(softteal, acidgreen, br);
	vec3 accent = mix(mutedrose, deepblue, d_);

	d.r += w * 0.2;
	d.g += br * 0.15;
	d.b += d_ * 0.25;

	return mix(palette(t, a, b, c, d), mix(base1, base2, 0.5), 0.35) + accent * 0.2;
}

// Smooth texture-based noise — bilinear filtering eliminates jitter
float texNoise(vec2 p) {
	return texture(noise_tex, p * 0.15).r;
}

float texFbm(vec2 p, float t) {
	float f = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		f += amp * texture(noise_tex, p * 0.15 + t * 0.01 * float(i + 1)).r;
		p *= 1.8;
		amp *= 0.5;
	}
	return f;
}

// Soft kaleidoscope: smooth noise, capped frequency to prevent jitter
vec2 softKaleido(vec2 uv, float segs, float t, float softness) {
	float a = atan(uv.y, uv.x);
	float r = length(uv);
	float slice = TAU / segs;

	// Smooth texture noise — no octave above a*8 to avoid jitter
	float angular_noise = texture(noise_tex, vec2(a * 1.5, r * 2.0) * 0.15 + t * 0.02).r * softness * 0.3
	                    + texture(noise_tex, vec2(a * 4.0 - t * 0.015, r * 4.0) * 0.15 + 3.0).r * softness * 0.15
	                    + texture(noise_tex, vec2(a * 8.0 + t * 0.01, r * 6.0 + 5.0) * 0.15).r * softness * 0.07;
	a += angular_noise;

	a = mod(a + slice * 0.5, slice) - slice * 0.5;
	return vec2(cos(a), sin(a)) * r;
}

// Domain warping using texture noise — smooth bilinear interpolation, no jitter
vec2 domainWarp(vec2 p, float t, float strength) {
	vec2 q = vec2(
		texFbm(p + vec2(0.0, 0.0) + t * 0.015, t),
		texFbm(p + vec2(5.2, 1.3) + t * 0.018, t)
	);
	vec2 r2 = vec2(
		texFbm(p + 3.0 * q + vec2(1.7, 9.2) + t * 0.01, t),
		texFbm(p + 3.0 * q + vec2(8.3, 2.8) + t * 0.012, t)
	);
	return p + strength * (q * 0.7 + 0.3 * r2);
}

float morphShape(vec2 p, float t, float morph) {
	float d1 = sdHexagon(p, 0.4 + morph * 0.1);
	float d2 = sdStar(p, 0.35 + morph * 0.15, 6, 0.4 + morph * 0.2);
	float d3 = sdCircle(p, 0.35 + morph * 0.1);

	float blend = sin(t * 0.5) * 0.5 + 0.5;
	float blend2 = sin(t * 0.3 + 1.0) * 0.5 + 0.5;

	float d = mix(d1, d2, blend);
	d = mix(d, d3, blend2 * morph);

	// Organic rings with noise-driven detail
	for (float i = 0.0; i < 3.0; i++) {
		vec2 rp = rot(p, t * 0.2 + i * 1.2);
		float ring_r = 0.15 + i * 0.12 + morph * 0.005;
		float rings = organicRing(rp, ring_r, 0.01 + morph * 0.004, t + i * 1.5, morph);
		// Add fine fractal edge detail
		float edge = edgeDetail(rp * 12.0, t + i, 1.0) * 0.008;
		rings += edge * smoothstep(0.06, 0.0, abs(rings));
		d = min(d, rings);
	}

	vec2 sp = p * 2.5;
	sp = rot(sp, -t * 0.3);
	for (float i = 0.0; i < 6.0; i++) {
		float angle = i * TAU / 6.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * (0.25 + morph * 0.1);
		float dot_shape = sdCircle(sp - offset, 0.04 + morph * 0.03);
		d = min(d, dot_shape);
	}

	return d;
}

float sacredFlower(vec2 p, float t, float petals, float audio) {
	float d = 1000.0;

	for (float i = 0.0; i < 8.0; i++) {
		if (i >= petals) break;
		float angle = i * TAU / petals + t * 0.3;
		float petal_count = 5.0 + floor(audio * 4.0);
		float inner_angle = angle;

		for (float j = 0.0; j < 3.0; j++) {
			float sub_angle = inner_angle + j * TAU / petal_count;
			vec2 offset = vec2(cos(sub_angle), sin(sub_angle)) * (0.25 + audio * 0.15);
			vec2 pp = p - offset;
			pp = rot(pp, t * 0.4 + j * 0.5);
			// Use blobs instead of hard hexagons for petals
			float petal = sdBlob(pp, 0.08 + audio * 0.04, t + j * 0.5, 0.6 + audio * 0.3);
			d = min(d, petal);
		}
	}

	// Soft center
	float center = sdCircle(p, 0.08 + audio * 0.05);
	center = max(center, -sdCircle(p, 0.05));
	d = min(d, center);

	// Organic rings with noise-driven variation
	for (float ring = 0.0; ring < 3.0; ring++) {
		float r = 0.2 + ring * 0.15 + audio * 0.08;
		float ring_d = organicRing(p, r, 0.008, t + ring * 1.5, audio);
		// Fine fractal edge detail on rings
		float edge = edgeDetail(p * (10.0 + ring * 4.0), t + ring, 1.0) * 0.006;
		ring_d += edge * smoothstep(0.05, 0.0, abs(ring_d));
		d = min(d, ring_d);

		// Noise-modulated angular pulses — each lobe is unique
		float angle = atan(p.y, p.x);
		float segments = 6.0 + ring * 2.0;
		float a = angle + t * (0.5 - ring * 0.1);
		float angular_pos = a * segments / TAU;
		float base_pulse = exp(-4.0 * pow(fract(angular_pos) - 0.5, 2.0));
		// Texture noise modulates pulse intensity per lobe — smooth and jitter-free
		float lobe_noise = texture(noise_tex, vec2(floor(angular_pos) * 2.5, ring * 1.5) * 0.15 + t * 0.015).r;
		float soft_pulse = base_pulse * (0.5 + lobe_noise * 0.5);
		float seg_dist = abs(length(p) - r) + (1.0 - soft_pulse) * 0.12;
		d = min(d, seg_dist);
	}

	for (float i = 0.0; i < 4.0; i++) {
		float fi = i / 4.0;
		vec2 sp = p * (1.5 + fi);
		sp = rot(sp, -t * 0.2 + i * 0.8);
		float sub = sdCircle(sp, 0.06 - fi * 0.015 + audio * 0.02);
		d = min(d, sub * 0.8);
	}

	return d;
}

float spiralGalaxy(vec2 p, float t, float arms, float audio) {
	float d = 1000.0;
	float spiral_strength = 3.0 + audio * 2.0;

	// Soft spiral arms using smooth angular falloff
	for (float i = 0.0; i < 4.0; i++) {
		float fi = i / 4.0;
		float r = length(p) * (1.0 - fi * 0.3);
		float angle = atan(p.y, p.x) + r * spiral_strength - t * (1.0 + fi * 0.5);

		// Soft angular wrap instead of hard mod
		float slice = TAU / arms;
		float wrapped = mod(angle + slice * 0.5, slice) - slice * 0.5;
		// Gaussian-ish soft falloff from arm center
		float arm_soft = exp(-wrapped * wrapped * (2.0 + fi * 2.0));

		vec2 pp = vec2(cos(angle), sin(angle)) * r;
		float arm_dist = abs(pp.x) - 0.02 - audio * 0.02;
		float arm = length(pp) * (1.0 - arm_soft * 0.8);
		d = min(d, arm * (0.5 + fi * 0.5));
	}

	// Organic rings with noise-driven variation
	for (float r = 0.05; r < 0.5; r += 0.08) {
		float ring = organicRing(p, r, 0.005, t + r * 3.0, audio);
		// Fine edge detail
		float edge = edgeDetail(p * (14.0 + r * 8.0), t + r, 1.0) * 0.004;
		ring += edge * smoothstep(0.04, 0.0, abs(ring));
		d = min(d, ring);

		// Noise-modulated angular pulses
		float angle = atan(p.y, p.x);
		float segments = 8.0 + r * 6.0;
		float a = angle - t * 0.5;
		float angular_pos = (a + r * 2.0) * segments / TAU;
		float base_pulse = exp(-3.5 * pow(fract(angular_pos) - 0.5, 2.0));
		float lobe_noise = texture(noise_tex, vec2(floor(angular_pos) * 1.8, r * 3.0) * 0.15 + t * 0.012).r;
		float soft_pulse = base_pulse * (0.5 + lobe_noise * 0.5);
		float seg_d = abs(length(p) - r) + (1.0 - soft_pulse) * 0.1;
		d = min(d, seg_d);
	}

	float center_glow = sdCircle(p, 0.06 + audio * 0.04);
	center_glow = max(center_glow, -sdCircle(p, 0.03 + audio * 0.02));
	d = min(d, center_glow * 0.8);

	// Organic curved arms with noise-driven wobble and edge detail
	for (float arm = 0.0; arm < 5.0; arm++) {
		if (arm >= arms) break;
		float arm_angle = arm * TAU / arms;
		vec2 arm_p = p;
		float r = length(arm_p);
		float a = atan(arm_p.y, arm_p.x) - arm_angle;
		a = mod(a + PI, TAU) - PI;

		// Smooth texture noise for organic arm curves
		float arm_wobble = texture(noise_tex, vec2(a * 1.5 + t * 0.02, arm * 2.5) * 0.15).r * 0.03
		                 + texture(noise_tex, vec2(a * 3.5 - t * 0.015, arm * 4.0 + 3.0) * 0.15).r * 0.015;
		// Vary arm thickness along length
		float thick = 0.018 + audio * 0.012;
		thick *= 0.5 + texture(noise_tex, vec2(a * 2.5 + t * 0.012, r * 3.0 + arm * 2.0) * 0.15).r * 0.5;
		float arm_d = abs(r - 0.3 - a * 0.3 - arm_wobble) - thick;
		d = min(d, arm_d);
	}

	return d;
}

float sacredTunnel(vec2 p, float t, float depth, float audio) {
	float d = 0.0;

	for (float i = 0.0; i < 8.0; i++) {
		float fi = i / 8.0;
		float z = 1.0 + fi * 2.0 + audio;
		vec2 pp = p * z;
		pp = rot(pp, t * (0.2 - fi * 0.05) + i * 0.3);

		float layer = morphShape(pp, t + fi, audio);
		layer = max(layer, -sdCircle(pp, 0.05));

		// Wider smoothstep for softer layer compositing
		d += smoothstep(0.15, 0.0, layer) * (0.35 - fi * 0.035);

		// Organic rings in the tunnel with noise variation
		float ring_r = 0.3 + fi * 0.15;
		float ring = organicRing(pp, ring_r, 0.005, t + fi * 2.0, audio);
		ring = max(ring, -sdCircle(pp, 0.25 + fi * 0.2));
		d += smoothstep(0.08, 0.0, ring) * (0.15 - fi * 0.015);
	}

	// Floating orbs with slight wobble
	for (float i = 0.0; i < 4.0; i++) {
		float fi = i / 4.0;
		float r = 0.1 + fi * 0.12;
		float angle = fi * TAU + t * (0.3 + fi * 0.2);
		vec2 center = vec2(cos(angle), sin(angle)) * r;
		center += vec2(sin(t * 1.5 + fi), cos(t * 1.2 + fi)) * 0.03;
		// Slightly larger, softer orbs
		float orb = sdCircle(p - center, 0.022 + audio * 0.015);
		d = min(d, orb * 0.5);
	}

	return d;
}

float flowField(vec2 p, float t, float audio) {
	vec2 flow = p;
	float n1 = fbm(flow + vec2(t * 0.03, 0.0), t);
	float n2 = fbm(flow + vec2(0.0, t * 0.04) + 10.0, t);

	float distort = (n1 - n2) * 0.3 * (1.0 + audio);
	p += distort;

	return fbm(p * 3.0 + t * 0.06, t);
}

// ── Starfield layer (from Shadertoy "Sacred Fractal" by Art of Code) ────

float star_shape(vec2 uv, float flare) {
	float col = 0.0;
	float d = length(uv);
	float m = 0.02 / d;

	float rays = max(0.0, 1.0 - abs(uv.x * uv.y * 1000.0));
	m += rays * flare;
	uv = rot(uv, PI * 0.25);
	rays = max(0.0, 1.0 - abs(uv.x * uv.y * 1000.0));
	m += rays * 0.3 * flare;

	m *= smoothstep(1.0, 0.2, d);
	return m;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 star_layer(vec2 uv, float t_stars, float flare_mult, vec3 tint) {
	vec3 col = vec3(0.0);
	vec2 gv = fract(uv) - 0.5;
	vec2 id = floor(uv);

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offs = vec2(float(x), float(y));
			float n = hash21(id + offs);
			float size = fract(n * 345.32);

			vec2 p = vec2(n, fract(n * 34.0));
			float star = star_shape(gv - offs - p + 0.5, smoothstep(0.8, 1.0, size) * 0.6 * flare_mult);

			// Color from hash, tinted by audio – amber/gold/emerald, no pink
			float hue = fract(n * 2345.2);
			vec3 color = sin(vec3(hue, hue + 0.33, hue + 0.67) * 3.5) * 0.5 + 0.5;
			color *= vec3(1.0, 0.6, 0.3); // warm bias
			color = mix(color, tint, 0.3); // blend in audio tint

			// Twinkle – audio-reactive speed
			float twinkle_speed = 3.0 + energy * 4.0 + beat * 6.0;
			star *= sin(t_stars * twinkle_speed + n * TAU) * 0.4 + 1.0;

			col += star * size * color;
		}
	}
	return col;
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= rect_size.x / rect_size.y;

	float t = time_val * 0.35;

	float audio = (energy + activity + onset) * 0.5;
	float bass_val = sub_bass + bass * 0.8;
	float mid_val = low_mid + mid;
	float treble_val = presence + treble;

	float sub_pulse = sub_bass + sin(beat_phase * TAU) * kick * 0.3;

	// Domain warp the base UV for organic flow
	float warp_strength = 0.12 + audio * 0.08;
	vec2 uv_warped = domainWarp(uv * 1.5, t, warp_strength);

	// Smooth segment counts — avoid discrete floor() jumps
	float seg1 = 6.0 + floor(bass_val * 4.0 + 0.5);
	float seg2 = 8.0 + floor(mid_val * 3.0 + 0.5);
	float seg3 = 12.0 + floor(treble_val * 6.0 + 0.5);

	// Soft kaleidoscope with smooth noise
	vec2 uv_k1 = softKaleido(uv_warped, seg1, t, 0.35 + audio * 0.2);
	vec2 uv_k2 = softKaleido(uv_warped * 1.2, seg2, t, 0.4 + audio * 0.15);
	vec2 uv_k3 = softKaleido(uv_warped * 0.8, seg3, t, 0.5 + audio * 0.1);

	// Smooth rotation — blend transient kick so it doesn't snap
	float rot_speed = beat * 0.3 + kick * 0.15;
	uv_k1 = rot(uv_k1, t * 0.08 + rot_speed);
	uv_k2 = rot(uv_k2, -t * 0.06);
	uv_k3 = rot(uv_k3, t * 0.04 + beat_phase * TAU * 0.5);

	float n = fbm(uv_warped * 1.5 + t * 0.03, t);
	float flow = flowField(uv, t, audio);

	float p1 = sacredFlower(uv_k1, t, seg1, bass_val);
	float p2 = spiralGalaxy(uv_k2 * 0.6, t, 4.0 + floor(mid_val * 3.0 + 0.5), mid_val);
	float p3 = sacredTunnel(uv_k3 * 0.4, t, 4.0, treble_val);

	float p4 = morphShape(uv_warped * 2.0 + vec2(sin(t * 0.5) * 0.08, cos(t * 0.5) * 0.08), t, sub_pulse);

	// Softer masks but not too wide — keep shapes contained
	float mask1 = 1.0 - smoothstep(0.0, 0.14, p1);
	float mask2 = 1.0 - smoothstep(0.0, 0.11, p2);
	float mask3 = 1.0 - smoothstep(0.0, 0.08, p3);
	float mask4 = 1.0 - smoothstep(0.0, 0.12, p4);

	// Gentle glow halos — tapered near center to avoid white-out
	float radial = length(uv);
	float center_damp = smoothstep(0.0, 0.15, radial);
	float glow1 = exp(-p1 * 8.0) * 0.2 * center_damp;
	float glow2 = exp(-p2 * 9.0) * 0.18 * center_damp;
	float glow3 = exp(-p3 * 10.0) * 0.14 * center_damp;
	float glow4 = exp(-p4 * 7.0) * 0.16 * center_damp;

	float p1_val = p1 * 0.4 + t * 0.4 + n * 0.2;
	float p2_val = p2 * 0.3 + t * 0.5 + bass_val * 0.3;
	float p3_val = p3 + t * 0.3 + flow * 0.2;
	float p4_val = p4 * 0.5 + t * 0.25 + sub_pulse;

	// Darken palette outputs so layering doesn't blow out to white
	vec3 col1 = sacredPalette(p1_val, warmth, brightness, density) * 0.7;
	vec3 col2 = sacredPalette(p2_val, 1.0 - warmth * 0.5, brightness * 0.8, density * 0.8) * 0.65;
	vec3 col3 = sacredPalette(p3_val, warmth * 0.7 + 0.3, brightness, density * 0.6) * 0.6;
	vec3 col4 = sacredPalette(p4_val, (warmth + brightness) * 0.5, 1.0 - brightness * 0.3, 1.0 - density * 0.4) * 0.65;

	vec3 col = vec3(0.0);

	// Audio gate: patterns breathe with the music, fade when quiet
	float audio_gate = 0.15 + energy * 0.85;

	// Compositing — gated by audio so quiet = dim
	col = mix(col, col1, mask1 * 0.95 * audio_gate);
	col = mix(col, col2, mask2 * 0.85 * audio_gate);
	col = mix(col, col3, mask3 * 0.75 * audio_gate);
	col = mix(col, col4, mask4 * 0.8 * audio_gate);

	// Glows also gated by audio
	col += col1 * glow1 * audio_gate;
	col += col2 * glow2 * audio_gate;
	col += col3 * glow3 * audio_gate;
	col += col4 * glow4 * audio_gate;

	// Subtle dark ambient background — always present but muted
	float ambient_flow = fbmRich(uv * 2.0 + t * 0.04, t);
	vec3 ambient_col = mix(
		vec3(0.02, 0.015, 0.03),
		vec3(0.04, 0.03, 0.05),
		ambient_flow
	);
	col += ambient_col * (1.0 - length(uv) * 0.3);

	col += vec3(0.03, 0.025, 0.04) * (1.0 - length(uv) * 0.4);
	col += flow * vec3(0.03, 0.02, 0.04) * audio_gate;

	// All transient/glow effects gated by audio — quiet = no flashes
	float beat_pulse = (beat + kick * 0.9 + snare * 0.5) * 0.5 * audio_gate;

	vec3 glow_col = mix(col1, col2, 0.5);
	col += glow_col * beat_pulse * exp(-radial * 2.5) * 0.2;

	float flash = onset * beat_pulse * 0.5;
	col += glow_col * flash * exp(-radial * 3.5) * 0.12;

	col += col3 * hihat * audio_gate * exp(-radial * 3.5) * 0.08;

	float phase_pulse = sin(beat_phase * TAU + t) * 0.5 + 0.5;
	col += mix(col1, col4, 0.5) * phase_pulse * activity * exp(-radial * 3.0) * 0.1;

	float flux_glow = (flux_bass + flux_mid + flux_treble) * 0.3 * audio_gate;
	col += mix(vec3(0.15, 0.3, 0.35), vec3(0.3, 0.15, 0.35), flux_treble) * flux_glow * exp(-radial * 3.5) * 0.08;

	float dense_fold = smoothstep(0.3, 0.8, density);
	vec3 dense_col = mix(vec3(0.06, 0.04, 0.08), vec3(0.15, 0.1, 0.2), dense_fold);
	col += dense_col * (1.0 - smoothstep(0.2, 0.8, radial)) * density * audio_gate * 0.15;

	// Gentle brightness lift near center — only when audio is present
	float bright_fold = brightness * 0.08 * audio_gate;
	vec3 bright_tint = mix(vec3(0.45, 0.4, 0.5), col, 0.7);
	col = mix(col, bright_tint, bright_fold * smoothstep(0.18, 0.06, radial));

	float warm_tint = warmth * 0.1 * audio_gate;
	col.r += warm_tint * (1.0 - radial);
	col.g += warm_tint * 0.4;

	float conf = beat_confidence;
	col = mix(col, col * 1.05, conf * 0.2 * activity);

	float vignette = 1.0 - smoothstep(0.5, 1.3, radial);
	col *= vignette * 0.35 + 0.65;

	col *= 0.8 + loudness * 0.3;

	// ── Starfield layer ────────────────────────────────────────────────
	// Kaleidoscope fold the UV for sacred symmetry, then layer parallax stars
	vec2 uv_star = uv;
	uv_star.x = abs(uv_star.x);
	uv_star.y += tan((5.0 / 6.0) * PI) * 0.5;
	vec2 n_star = vec2(sin((5.0 / 6.0) * PI), cos((5.0 / 6.0) * PI));
	float d_star = dot(uv_star - vec2(0.5, 0.0), n_star);
	uv_star -= n_star * max(0.0, d_star) * 2.0;
	n_star = vec2(sin((2.0 / 3.0) * PI), cos((2.0 / 3.0) * PI));
	float star_scale = 1.0;
	uv_star.x += 1.5 / 1.25;
	for (int i = 0; i < 5; i++) {
		star_scale *= 1.25;
		uv_star *= 1.25;
		uv_star.x -= 1.5;
		uv_star.x = abs(uv_star.x);
		uv_star.x -= 0.5;
		uv_star -= n_star * min(0.0, dot(uv_star, n_star)) * 2.0;
	}
	// Slow rotation – pure time, smooth
	float star_rot = time_val * 0.01;
	float sr_c = cos(star_rot), sr_s = sin(star_rot);
	uv_star = vec2(uv_star.x * sr_c - uv_star.y * sr_s, uv_star.x * sr_s + uv_star.y * sr_c);

	// Parallax depth layers – 10 layers, audio-gated
	float star_flare = 0.4 + onset * 2.0 + kick * 1.0;
	vec3 star_tint = mix(vec3(1.0, 0.7, 0.3), vec3(0.3, 0.8, 0.5), brightness);
	vec3 stars = vec3(0.0);
	float num_layers = 10.0;
	for (float i = 0.0; i < 1.0; i += 1.0 / num_layers) {
		float depth = fract(i + time_val * 0.01);
		float s = mix(20.0, 0.5, depth);
		float fade = depth * smoothstep(1.0, 0.9, depth);
		stars += star_layer(uv_star * s + i * 453.2, time_val, star_flare, star_tint) * fade;
	}
	// Composite stars behind the sacred geometry, audio-gated
	col += stars * audio_gate * 0.25;

	// Soft tonal compression instead of hard clamp — prevents white clipping
	col = col / (1.0 + col * 0.6);
	col = clamp(col, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
