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

#define FAR 30.0
#define PI 3.14159265

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

mat3 lookAt(vec3 dir) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 rt = normalize(cross(dir, up));
	return mat3(rt, cross(rt, dir), dir);
}

float gyroid(vec3 p) {
	return dot(cos(p), sin(p.zxy)) + 1.0;
}

// HSV to RGB for color-reactive materials.
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float map(vec3 p) {
	float morph = bass;
	vec3 q = p + vec3(
		sin(p.y * 3.17 + morph * 2.0) * morph * 0.15,
		cos(p.z * 3.17 + morph * 2.0) * morph * 0.15,
		sin(p.x * 3.17 + morph * 2.0) * morph * 0.15
	);
	float freq = 1.0 + sub_bass * 0.3;
	q *= freq;
	return min(gyroid(q), gyroid(q - vec3(0.0, 0.0, PI * freq))) / freq;
}

float getMaterial(vec3 p) {
	float morph = bass;
	vec3 q = p + vec3(
		sin(p.y * 3.17 + morph * 2.0) * morph * 0.15,
		cos(p.z * 3.17 + morph * 2.0) * morph * 0.15,
		sin(p.x * 3.17 + morph * 2.0) * morph * 0.15
	);
	float freq = 1.0 + sub_bass * 0.3;
	q *= freq;
	float d1 = gyroid(q);
	float d2 = gyroid(q - vec3(0.0, 0.0, PI * freq));
	return (d1 < d2) ? 1.0 : 2.0;
}

float raymarch(vec3 ro, vec3 rd) {
	float t = 0.0;
	for (int i = 0; i < 100; i++) {
		float d = map(ro + rd * t);
		if (abs(d) < 0.001) break;
		t += d;
		if (t > FAR) break;
	}
	return t;
}

float getAO(vec3 p, vec3 sn) {
	float occ = 0.0;
	float spread = 0.08 + loudness * 0.06;
	for (float i = 0.0; i < 4.0; i++) {
		float t = i * spread;
		float d = map(p + sn * t);
		occ += t - d;
	}
	return clamp(1.0 - occ, 0.0, 1.0);
}

vec3 getNormal(vec3 p) {
	vec2 e = vec2(0.5773, -0.5773) * 0.001;
	return normalize(
		e.xyy * map(p + e.xyy) +
		e.yyx * map(p + e.yyx) +
		e.yxy * map(p + e.yxy) +
		e.xxx * map(p + e.xxx)
	);
}

vec3 trace(vec3 ro, vec3 rd) {
	vec3 C = vec3(0.0);
	vec3 throughput = vec3(1.0);

	float fog_density = 0.004 + density * 0.016;

	// Color hue driven by warmth — shifts the whole palette over time.
	float hue_shift = warmth * 0.3 + time_val * 0.02;

	for (int bounce = 0; bounce < 2; bounce++) {
		float d = raymarch(ro, rd);
		if (d > FAR) break;

		float fog = 1.0 - exp(-fog_density * d * d);
		// Fog color shifts with warmth and time.
		vec3 fog_col = hsv2rgb(vec3(hue_shift + 0.6, 0.4, 0.03 + energy * 0.05));
		C += throughput * fog * fog_col;
		throughput *= 1.0 - fog;

		vec3 p = ro + rd * d;
		float detail = 0.05 + treble * 0.25 + presence * 0.15;
		vec3 sn = normalize(getNormal(p) + pow(abs(cos(p * 64.0)), vec3(16.0)) * detail);

		// Light orbits smoothly with time, mid shifts its angle.
		float light_angle = time_val * 0.3 + mid * PI * 0.5;
		vec3 lp = vec3(
			10.0 * cos(light_angle),
			-10.0 + snare * 4.0,
			-10.0 + ro.z + 10.0 * sin(light_angle)
		);
		vec3 ld = normalize(lp - p);

		float diff_str = 2.0 + energy * 3.0;
		float diff = max(0.0, 0.5 + diff_str * dot(sn, ld));
		float diff2 = pow(length(sin(sn * 2.0) * 0.5 + 0.5), 2.0);
		float diff3 = max(0.0, 0.5 + 0.5 * dot(sn, vec3(0.0, 1.0, 0.0)));

		float spec_pow = 4.0 + hihat * 4.0 + presence * 2.0;
		float spec_int = 8.0 + energy * 16.0;
		float spec = max(0.0, dot(reflect(-ld, sn), -rd));
		float fres = 1.0 - max(0.0, dot(-rd, sn));

		vec3 col = vec3(0.0);
		vec3 alb = vec3(0.0);

		// Lighting colors rotate through hue based on warmth + brightness.
		vec3 diff_a = hsv2rgb(vec3(hue_shift + 0.55, 0.5 + brightness * 0.3, 0.5 + energy * 0.4));
		vec3 diff_b = hsv2rgb(vec3(hue_shift + 0.0, 0.7 - warmth * 0.2, 0.4 + energy * 0.3));
		vec3 diff_c = hsv2rgb(vec3(hue_shift + 0.85, 0.6 + brightness * 0.3, 0.5 + energy * 0.3));
		vec3 spec_col = hsv2rgb(vec3(hue_shift + 0.15, 0.3, 0.4 + brightness * 0.4));

		col += diff_a * diff;
		col += diff_b * diff2;
		col += diff_c * diff3;
		col += spec_col * pow(spec, spec_pow) * spec_int;

		// Mid shifts the freckle pattern scale.
		float freckle_scale = 23.0 + mid * 12.0;
		float freck = dot(cos(p * freckle_scale), vec3(1.0));
		float mat_id = getMaterial(p);

		if (mat_id < 1.5) {
			// Material 1: hue shifts with warmth, saturation with energy.
			alb = hsv2rgb(vec3(hue_shift + 0.6, 0.7 + energy * 0.3, 0.4 + energy * 0.4));
			alb *= max(0.6, step(2.5, freck));
		} else {
			// Material 2: hue shifts with brightness, saturation with energy.
			alb = hsv2rgb(vec3(hue_shift + 0.1, 0.6 + energy * 0.3, 0.35 + energy * 0.4));
			alb *= max(0.8, step(-2.5, freck));
		}

		// Onset brightens the albedo momentarily.
		alb *= 1.0 + onset * 0.5;

		// Beat phase pulses the albedo saturation.
		alb *= 1.0 + pow(beat_phase, 4.0) * beat_confidence * 0.2;

		col *= alb;
		col *= getAO(p, sn);

		// Snare warm highlight flash.
		col += hsv2rgb(vec3(hue_shift + 0.08, 0.8, 0.4)) * snare * diff * 0.5;

		// Kick cool rim flash.
		col += hsv2rgb(vec3(hue_shift + 0.55, 0.6, 0.3)) * kick * fres * 0.6;

		C += throughput * col;

		rd = reflect(rd, sn);
		ro = p + sn * 0.01;
		throughput *= (0.85 + energy * 0.1) * pow(fres, 1.0);
	}

	return C;
}

void fragment() {
	vec2 fragCoord = UV * rect_size;
	vec2 uv = (fragCoord - rect_size * 0.5) / rect_size.y;

	float t = time_val;

	// Smooth camera — only time, warmth, and loudness. No transient jitter.
	// time_val already speeds up with energy so the orbit naturally quickens.
	vec3 ro = vec3(PI * 0.5, 0.0, -t * 0.5);
	vec3 ta = vec3(
		cos(t * 0.25) * (0.4 + warmth * 0.2),
		sin(t * 0.25) * (0.3 + loudness * 0.1),
		4.0
	);
	vec3 rd = lookAt(normalize(ta)) * normalize(vec3(uv, -0.5));

	vec3 col = trace(ro, rd);

	// Audio-reactive vignette.
	float vig_strength = 1.2 + treble * 0.3;
	col *= smoothstep(0.0, 1.0, vig_strength - length(uv * 0.9));

	// Beat brightness pulse.
	col *= 1.0 + beat * 0.15;

	// Energy overall brightness.
	col *= 0.7 + energy * 0.5;

	// Beat-phase subtle pulse.
	float phase_pulse = pow(beat_phase, 3.0) * beat_confidence;
	col *= 1.0 + phase_pulse * 0.08;

	// Gamma.
	col = pow(max(col, vec3(0.0)), vec3(0.4545));

	COLOR = vec4(col, 1.0);
}
