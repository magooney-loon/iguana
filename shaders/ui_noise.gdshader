shader_type canvas_item;

//  @meta:          skip
// ── Industrial Noise Overlay — Animated ──────────────────────────────────────
// Procedural grain, scanlines, scratches, CRT flicker, rolling bars,
// interference sweeps, and pulsing vignette.  Everything is driven by TIME
// so the surface never feels static.

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.04;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 3.0;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 1.2;

group_uniforms Scanlines;
uniform float scanline_strength  : hint_range(0.0, 0.12, 0.005) = 0.035;
uniform float scanline_count     : hint_range(100.0, 800.0, 10.0) = 340.0;
uniform float scanline_softness  : hint_range(0.1, 2.0, 0.1)   = 0.6;
uniform float scanline_scroll_spd : hint_range(0.0, 2.0, 0.05) = 0.25;

group_uniforms Scratches;
uniform float scratch_strength : hint_range(0.0, 0.08, 0.005) = 0.02;
uniform float scratch_density  : hint_range(0.5, 5.0, 0.25)   = 2.0;
uniform float scratch_drift    : hint_range(0.0, 1.0, 0.05)   = 0.15;

group_uniforms CRT;
uniform float flicker_strength : hint_range(0.0, 0.06, 0.002) = 0.015;
uniform float roll_speed       : hint_range(0.0, 0.3, 0.005)  = 0.04;
uniform float roll_strength    : hint_range(0.0, 0.08, 0.002) = 0.025;
uniform float interference_str : hint_range(0.0, 0.06, 0.002) = 0.015;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.08;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.85;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.02;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.5;

group_uniforms Chromatic;
uniform float chromatic_str    : hint_range(0.0, 0.004, 0.0002) = 0.0008;
uniform float chromatic_flicker : hint_range(0.0, 1.0, 0.05)   = 0.4;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  FILM GRAIN  (multi-octave, animated)
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 100.0 + fract(t_a * 0.7) * 37.0);
	grain += hash12(g_uv * 200.0 + fract(t_a * 1.3) * 53.0) * 0.5;
	grain += hash12(g_uv * 400.0 + fract(t_a * 2.1) * 71.0) * 0.25;
	grain = (grain / 1.75) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  SCROLLING SCANLINES
	// ══════════════════════════════════════════════════════════════════════
	float scan_offset = t * scanline_scroll_spd;
	float scan_y = (uv.y + scan_offset) * scanline_count;
	float scanline = sin(scan_y * 3.14159) * 0.5 + 0.5;
	scanline = pow(scanline, scanline_softness);
	float scan_amt = (1.0 - scanline) * scanline_strength;

	// Organic band drift
	float band = vnoise(vec2(0.0, uv.y * 6.0 + t * 0.08));
	scan_amt += band * scanline_strength * 0.35;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  MOVING SCRATCHES
	// ══════════════════════════════════════════════════════════════════════
	float scratch = 0.0;
	for (float i = 0.0; i < 3.0; i++) {
		float drift = t * scratch_drift * (0.5 + i * 0.3);
		vec2 s_uv = vec2(
			uv.x * scratch_density + i * 7.3 + drift * 0.2,
			uv.y * (40.0 + i * 15.0) + drift
		);
		float s = vnoise(s_uv);
		s = smoothstep(0.82, 0.95, s);
		float angle = vnoise(vec2(i * 3.7 + t * 0.01, 0.0)) * 0.015;
		s *= smoothstep(0.0, 0.1, abs(sin(
			(uv.x + uv.y * angle) * 50.0 + i * 10.0 + drift * 3.0
		)));
		scratch += s;
	}
	scratch *= scratch_strength / 3.0;

	// ══════════════════════════════════════════════════════════════════════
	//  4.  CRT FLICKER  (global brightness wobble + occasional hard flick)
	// ══════════════════════════════════════════════════════════════════════
	// Slow sinusoidal breathing
	float flicker = sin(t * 3.7) * sin(t * 5.3 + 1.0) * 0.5;
	// Sporadic hard micro-flicker (hash-based, triggers briefly)
	float flick_trig = step(0.985, hash12(vec2(floor(t * 12.0), 0.0)));
	flicker += flick_trig * 0.6;
	float flick_amt = flicker * flicker_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  5.  ROLLING BAR  (bright horizontal band drifting vertically)
	// ══════════════════════════════════════════════════════════════════════
	float roll_pos = fract(t * roll_speed);
	float roll_dist = abs(uv.y - roll_pos);
	roll_dist = min(roll_dist, 1.0 - roll_dist); // wrap
	float roll_bar = smoothstep(0.08, 0.0, roll_dist);
	// Second, fainter bar offset by 0.5
	float roll_pos2 = fract(roll_pos + 0.5);
	float roll_dist2 = abs(uv.y - roll_pos2);
	roll_dist2 = min(roll_dist2, 1.0 - roll_pos2);
	float roll_bar2 = smoothstep(0.12, 0.0, roll_dist2) * 0.4;
	float roll_amt = (roll_bar + roll_bar2) * roll_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  6.  INTERFERENCE SWEEP  (horizontal glitch line that sweeps)
	// ══════════════════════════════════════════════════════════════════════
	float sweep_period = 4.0; // seconds between sweeps
	float sweep_phase = fract(t / sweep_period);
	// Only active for a brief window
	float sweep_active = smoothstep(0.0, 0.02, sweep_phase)
	                   * smoothstep(0.06, 0.04, sweep_phase);
	float sweep_y = sweep_phase * 1.4 - 0.2; // sweep from top to bottom
	float sweep_dist = abs(uv.y - sweep_y);
	float sweep_line = smoothstep(0.015, 0.0, sweep_dist) * sweep_active;
	// Random brightness spike on the line
	float sweep_bright = sweep_line * 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  7.  PULSING VIGNETTE
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	float vig_pulse = sin(t * vignette_pulse_spd) * vignette_pulse;
	float vig_r = vignette_radius + vig_pulse;
	float vignette = smoothstep(vig_r, vig_r - 0.4, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  8.  CHROMATIC ABERRATION  (subtle RGB offset, flickers in & out)
	// ══════════════════════════════════════════════════════════════════════
	float chroma_mod = sin(t * 2.3) * 0.5 + 0.5;          // slow pulse
	chroma_mod *= step(0.3, hash12(vec2(floor(t * 8.0), 1.0))); // sporadic
	chroma_mod = mix(1.0, chroma_mod, chromatic_flicker);
	float chroma_offset = chromatic_str * chroma_mod * vdist;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Chromatic: sample-shift (approximate by shifting the result channels)
	result.r = base.r + grain_amt * 0.15 + chroma_offset;
	result.g = base.g;
	result.b = base.b - grain_amt * 0.10 - chroma_offset;

	// Grain (signed additive)
	result += grain_amt;

	// Scanlines darken
	result -= scan_amt;

	// Scratches lighten
	result += scratch;

	// CRT flicker (signed)
	result += flick_amt;

	// Rolling bar brightens
	result += roll_amt;

	// Interference sweep
	result += sweep_bright * interference_str;

	// Vignette darkens edges
	result -= vig_amt;

	COLOR = vec4(result, base.a);
}
