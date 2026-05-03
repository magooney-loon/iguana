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

void fragment() {
	vec2 C = UV * rect_size;
	vec2 r = rect_size;
	float t = time_val;

	// Audio-reactive parameters — shape, color, and fold.
	float fold_base   = 2.0 + bass * 1.5;            // bass morphs fold angle
	float z_speed     = 0.6 + energy * 0.15;          // energy densifies the march
	float warm_shift  = warmth * 2.0;                  // warmth shifts second fold
	float col_shift   = brightness * 2.0;              // brightness rotates palette
	float det_radius  = 0.125 - treble * 0.02;         // treble sharpens detail shape

	float d;
	float z = fract(dot(C, sin(C))) - 0.5;
	vec4 accum = vec4(0.0);
	vec4 O = vec4(0.0);
	vec4 p = vec4(0.0);

	for (int i = 0; i < 76; i++) {
		// Ray position.
		p = vec4(z * normalize(vec3(C - 0.5 * r, r.y)), 0.1 * t);
		p.z += t;

		O = p;

		// First fold rotation — bass shifts the base angle.
		float a = fold_base + O.z;
		p.xy *= mat2(
			vec2(cos(a), cos(a + 11.0)),
			vec2(cos(a + 33.0), cos(a))
		);

		// Second fold rotation — warmth drifts the pattern.
		p.xy *= mat2(
			vec2(cos(O.x + warm_shift), cos(O.y + 11.0 + warm_shift)),
			vec2(cos(O.z + 33.0 + warm_shift), cos(O.w + warm_shift))
		);

		// Color: depth + distance + per-channel phase offsets.
		O = (1.0 + sin(0.5 * O.z + length(p - O) + vec4(col_shift, 4.0 + col_shift, 3.0 + col_shift * 0.5, 6.0)))
			/ (0.5 + 2.0 * dot(O.xy, O.xy));

		// Distance estimation — treble tightens the detail.
		p = abs(fract(p) - 0.5);
		d = abs(min(length(p.xy) - det_radius, min(p.x, p.y) + 1e-3)) + 1e-3;

		// Accumulate glow.
		accum += (O.w / d) * O;

		// Advance z — energy controls march density.
		z += z_speed * d;
	}

	// Tonemap.
	vec3 col = tanh(accum / 2e4).rgb;

	// Energy overall brightness.
	col *= 0.7 + energy * 0.5;

	// Beat brightness pulse.
	col *= 1.0 + beat * 0.2;

	// Kick flash — warm tint.
	col += vec3(0.12, 0.06, 0.02) * kick;

	// Snare flash — cool tint.
	col += vec3(0.02, 0.06, 0.12) * snare;

	// Onset flash.
	col += vec3(0.06) * onset;

	// Density adds subtle overall glow.
	col *= 1.0 + density * 0.15;

	// Beat-phase pulse.
	float phase_pulse = pow(beat_phase, 3.0) * beat_confidence;
	col *= 1.0 + phase_pulse * 0.1;

	// Gamma.
	col = pow(max(col, vec3(0.0)), vec3(0.4545));

	COLOR = vec4(col, 1.0);
}
