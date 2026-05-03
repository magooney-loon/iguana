shader_type canvas_item;

// Audio engine uniforms. These are the same inputs available to preset authors.
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
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;
uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float beat_threshold  : hint_range(0.0, 1.0) = 0.0;
uniform float kick_threshold  : hint_range(0.0, 1.0) = 0.0;
uniform float snare_threshold : hint_range(0.0, 1.0) = 0.0;
uniform float hihat_threshold : hint_range(0.0, 1.0) = 0.0;
uniform float peak_00 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_01 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_02 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_03 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_04 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_05 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_06 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_07 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_08 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_09 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_10 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_11 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_12 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_13 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_14 : hint_range(0.0, 1.0) = 0.0;
uniform float bpm         = 120.0;
uniform float time_val    = 0.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

float sd_box(vec2 p, vec2 c, vec2 hs, float r) {
	vec2 d = abs(p - c) - hs + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float fill_box(vec2 p, vec2 c, vec2 hs, float r) {
	return 1.0 - smoothstep(0.0, 1.25, sd_box(p, c, hs, r));
}

float stroke_box(vec2 p, vec2 c, vec2 hs, float r, float w) {
	float d = abs(sd_box(p, c, hs, r));
	return 1.0 - smoothstep(w, w + 1.25, d);
}

float line_segment(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w, w + 1.0, length(pa - ba * h));
}

float dash_line(vec2 p, vec2 a, vec2 b, float w, float cells) {
	vec2 ba = b - a;
	float h = clamp(dot(p - a, ba) / dot(ba, ba), 0.0, 1.0);
	float dash = step(0.50, fract(h * cells));
	return line_segment(p, a, b, w) * dash;
}

void meter_row(
	inout vec3 col,
	vec2 px,
	vec2 origin,
	float row_h,
	float value,
	vec3 c,
	float peak,
	float threshold
) {
	float y = origin.y + row_h * 0.5;
	vec2 peak_a = vec2(origin.x + 315.0 * peak, y - 8.0);
	vec2 peak_b = vec2(origin.x + 315.0 * peak, y + 8.0);
	vec2 thresh_a = vec2(origin.x + 315.0 * threshold, y - 6.0);
	vec2 thresh_b = vec2(origin.x + 315.0 * threshold, y + 6.0);

	col = mix(col, vec3(0.052, 0.055, 0.062), fill_box(px, origin + vec2(157.5, row_h * 0.5), vec2(157.5, 2.5), 0.0));
	col = mix(col, c * 0.90, fill_box(px, origin + vec2(157.5 * value, row_h * 0.5), vec2(157.5 * value, 3.0), 0.0));
	col = mix(col, vec3(0.36, 0.36, 0.35), stroke_box(px, origin + vec2(157.5, row_h * 0.5), vec2(157.5, 4.5), 0.0, 0.85));
	if (threshold > 0.001) {
		col = mix(col, vec3(0.42, 0.78, 1.0), line_segment(px, thresh_a, thresh_b, 0.9));
	}
	col = mix(col, vec3(0.88, 0.84, 0.72), line_segment(px, peak_a, peak_b, 0.75));
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 uv = UV;
	float aspect = rect_size.x / rect_size.y;

	vec3 ink = vec3(0.78, 0.79, 0.78);
	vec3 paper = vec3(0.019, 0.020, 0.024);
	vec3 panel = vec3(0.032, 0.034, 0.040);
	vec3 panel_hi = vec3(0.050, 0.052, 0.060);
	vec3 col = paper;

	vec2 grid = fract(uv * vec2(18.0 * aspect, 12.0));
	float grid_l = step(0.985, grid.x) + step(0.985, grid.y);
	col += grid_l * 0.012;
	col += texture(noise_tex, uv * 1.5 + vec2(time_val * 0.012, 0.0)).r * 0.012;

	vec2 page_c = vec2(0.50, 0.50) * rect_size;
	vec2 page_h = vec2(0.47, 0.45) * rect_size;
	float page = fill_box(px, page_c, page_h, 3.0);
	col = mix(col, vec3(0.026, 0.027, 0.031), page);
	col = mix(col, vec3(0.16, 0.16, 0.15), stroke_box(px, page_c, page_h, 3.0, 1.2));

	float divider = dash_line(px, vec2(0.568, 0.075) * rect_size, vec2(0.568, 0.925) * rect_size, 0.9, 68.0);
	col = mix(col, vec3(0.52, 0.52, 0.48), divider);

	float bands[6] = float[](sub_bass, bass, low_mid, mid, presence, treble);
	float dets[4] = float[](beat, kick, snare, hihat);
	float flx[3] = float[](flux_bass, flux_mid, flux_treble);
	float globals[2] = float[](energy, activity);
	float peaks[15] = float[](
		peak_00, peak_01, peak_02, peak_03, peak_04, peak_05,
		peak_06, peak_07, peak_08, peak_09,
		peak_10, peak_11, peak_12,
		peak_13, peak_14
	);
	vec3 band_c[6] = vec3[](
		vec3(0.90, 0.22, 0.24),
		vec3(0.92, 0.43, 0.16),
		vec3(0.92, 0.58, 0.18),
		vec3(0.78, 0.65, 0.20),
		vec3(0.72, 0.66, 0.16),
		vec3(0.72, 0.60, 0.02)
	);
	vec3 det_c[4] = vec3[](
		vec3(0.45, 0.42, 0.95),
		vec3(0.28, 0.42, 0.95),
		vec3(0.07, 0.70, 0.92),
		vec3(0.16, 0.72, 0.48)
	);
	vec3 flux_c[3] = vec3[](
		vec3(0.22, 0.72, 0.40),
		vec3(0.18, 0.66, 0.38),
		vec3(0.20, 0.62, 0.44)
	);

	// Left uniform rows.
	vec2 row_origin = vec2(0.235, 0.13) * rect_size;
	float row_h = 0.041 * rect_size.y;
	for (int i = 0; i < 15; i++) {
		float value = 0.0;
		vec3 c = vec3(0.7);
		if (i < 6) {
			value = bands[i];
			c = band_c[i];
		} else if (i < 10) {
			value = dets[i - 6];
			c = det_c[i - 6];
		} else if (i < 13) {
			value = flx[i - 10];
			c = flux_c[i - 10];
		} else {
			value = globals[i - 13];
			c = mix(vec3(0.35, 0.65, 0.95), vec3(0.94, 0.52, 0.20), float(i - 13));
		}

		vec2 row_o = row_origin + vec2(0.0, float(i) * row_h);
		float sep = dash_line(px, vec2(0.045, 0.171 + float(i) * 0.041) * rect_size, vec2(0.535, 0.171 + float(i) * 0.041) * rect_size, 0.55, 56.0);
		col = mix(col, vec3(0.21, 0.21, 0.20), sep * 0.7);
		col = mix(col, c, fill_box(px, vec2(0.048, 0.153 + float(i) * 0.041) * rect_size, vec2(3.0, 9.0), 0.0));
		float threshold = 0.0;
		if (i == 6) {
			threshold = beat_threshold;
		} else if (i == 7) {
			threshold = kick_threshold;
		} else if (i == 8) {
			threshold = snare_threshold;
		} else if (i == 9) {
			threshold = hihat_threshold;
		}
		meter_row(col, px, row_o, row_h, value, c, peaks[i], threshold);
	}

	// Right top: beat clock gauge.
	vec2 gc = vec2(0.640, 0.172) * rect_size;
	float gr = min(rect_size.x, rect_size.y) * 0.069;
	float ring = abs(length(px - gc) - gr);
	col = mix(col, ink * 0.75, 1.0 - smoothstep(1.5, 3.0, ring));
	for (int i = 0; i < 4; i++) {
		float a = -1.5708 + float(i) * 1.5708;
		vec2 d = vec2(cos(a), sin(a));
		col = mix(col, ink * 0.65, line_segment(px, gc + d * (gr - 9.0), gc + d * (gr + 9.0), 1.0));
	}
	float phase_a = -1.5708 + beat_phase * 6.28318;
	vec2 hand = gc + vec2(cos(phase_a), sin(phase_a)) * gr * (0.72 + beat * 0.18);
	col = mix(col, vec3(0.48, 0.46, 1.0), line_segment(px, gc, hand, 2.0 + beat * 3.0));
	col += vec3(0.38, 0.36, 1.0) * beat * (1.0 - smoothstep(0.0, gr * 1.25, length(px - gc))) * 0.18;
	col = mix(col, vec3(0.36, 0.82, 1.0), line_segment(px, vec2(0.735, 0.252) * rect_size, vec2(0.735 + 0.090 * beat_confidence, 0.252) * rect_size, 1.8));

	// Spectrum snapshot panel.
	vec2 spec_c = vec2(0.768, 0.394) * rect_size;
	vec2 spec_h = vec2(0.178, 0.130) * rect_size;
	col = mix(col, panel, fill_box(px, spec_c, spec_h, 5.0));
	col = mix(col, ink * 0.82, stroke_box(px, spec_c, spec_h, 5.0, 1.6));
	col = mix(col, vec3(0.92, 0.39, 0.22), line_segment(px, vec2(0.668, 0.342) * rect_size, vec2(0.880, 0.342) * rect_size, 1.5));
	for (int i = 0; i < 6; i++) {
		float bw = 0.040;
		float bx = 0.600 + float(i) * 0.047;
		float bh = 0.092 * max(bands[i], 0.015);
		vec2 bc = vec2(bx + bw * 0.5, 0.496 - bh * 0.5) * rect_size;
		col = mix(col, panel_hi, fill_box(px, vec2(bx + bw * 0.5, 0.450) * rect_size, vec2(bw * 0.5, 0.048) * rect_size, 0.0));
		col = mix(col, band_c[i], fill_box(px, bc, vec2(bw * 0.5, bh * 0.5) * rect_size, 0.0));
		col = mix(col, ink * 0.85, line_segment(px, vec2(bx, 0.440 - 0.016 * fract(float(i) * 0.61)) * rect_size, vec2(bx + bw, 0.440 - 0.016 * fract(float(i) * 0.61)) * rect_size, 0.75));
	}

	// Noise texture inspection panel.
	vec2 noise_c = vec2(0.768, 0.595) * rect_size;
	vec2 noise_h = vec2(0.178, 0.070) * rect_size;
	col = mix(col, panel, fill_box(px, noise_c, noise_h, 5.0));
	col = mix(col, ink * 0.82, stroke_box(px, noise_c, noise_h, 5.0, 1.6));
	float noise_side = min(rect_size.x, rect_size.y) * 0.092;
	vec2 np0 = vec2(0.608, 0.549) * rect_size;
	vec2 ns = vec2(noise_side);
	vec2 nuv = (px - np0) / ns;
	if (nuv.x >= 0.0 && nuv.x <= 1.0 && nuv.y >= 0.0 && nuv.y <= 1.0) {
		float n = texture(noise_tex, nuv + vec2(time_val * 0.10, time_val * 0.04)).r;
		float check = (1.0 - abs(step(0.5, fract(nuv.x * 5.0)) - step(0.5, fract(nuv.y * 5.0)))) * 0.08;
		col = mix(col, vec3(n * 0.55 + check), 0.95);
	}
	col = mix(col, ink * 0.75, stroke_box(px, np0 + ns * 0.5, ns * 0.5, 0.0, 1.0));

	// Derived/mood uniform strip.
	float derived[5] = float[](onset, loudness, warmth, brightness, density);
	vec3 derived_c[5] = vec3[](
		vec3(0.90, 0.38, 0.25),
		vec3(0.80, 0.62, 0.25),
		vec3(0.86, 0.46, 0.25),
		vec3(0.42, 0.70, 1.00),
		vec3(0.72, 0.52, 0.95)
	);
	for (int i = 0; i < 5; i++) {
		float x = 0.585 + float(i) * 0.087;
		float v = derived[i];
		col = mix(col, vec3(0.055, 0.057, 0.065), fill_box(px, vec2(x + 0.018, 0.754) * rect_size, vec2(0.018, 0.004) * rect_size, 0.0));
		col = mix(col, derived_c[i], fill_box(px, vec2(x + 0.018 * v, 0.754) * rect_size, vec2(0.018 * v, 0.0045) * rect_size, 0.0));
	}

	// Bottom flux/onset strip.
	float base_y = 0.816 * rect_size.y;
	col = mix(col, ink * 0.55, dash_line(px, vec2(0.588, 0.774) * rect_size, vec2(0.948, 0.774) * rect_size, 0.75, 60.0));
	for (int i = 0; i < 3; i++) {
		float x = (0.650 + float(i) * 0.117) * rect_size.x;
		float v = flx[i];
		vec3 fc = flux_c[i];
		float stem = 8.0 + 55.0 * v;
		vec2 arrow_base = vec2(x, base_y + 12.0);
		vec2 arrow_tip = vec2(x, base_y + 12.0 - stem);
		float arrow_alpha = smoothstep(0.01, 0.12, v);
		col = mix(col, fc, line_segment(px, arrow_base, arrow_tip, 2.0) * arrow_alpha);
		col = mix(col, fc, line_segment(px, arrow_tip, arrow_tip + vec2(-8.0, 12.0), 2.0) * arrow_alpha);
		col = mix(col, fc, line_segment(px, arrow_tip, arrow_tip + vec2(8.0, 12.0), 2.0) * arrow_alpha);
		col = mix(col, fc * 0.55, fill_box(px, arrow_base, vec2(5.0, 2.0), 1.0) * (1.0 - arrow_alpha));
		col += fc * v * (1.0 - smoothstep(0.0, 42.0, length(px - arrow_tip))) * 0.18;
	}

	// Top status sweep.
	float tpos = fract(time_val * 0.07);
	col = mix(col, vec3(0.74, 0.50, 0.20), line_segment(px, vec2(0.480, 0.090) * rect_size, vec2(0.480 + 0.055 * tpos, 0.090) * rect_size, 1.0));
	float pulse = 1.0 - smoothstep(0.0, 20.0 + beat * 30.0, length(px - vec2((0.480 + 0.055 * tpos) * rect_size.x, 0.090 * rect_size.y)));
	col += vec3(0.95, 0.64, 0.25) * pulse * (0.08 + beat * 0.12);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
