shader_type canvas_item;

//  @meta:          skip
// ── Industrial Noise Overlay ─────────────────────────────────────────────────
// Adds subtle grain, scanlines, and scratch textures to UI panels.
// Designed to be layered on top of glass-style panels for a mechanical feel.

group_uniforms Noise;
uniform float grain_strength : hint_range(0.0, 0.15, 0.005) = 0.04;
uniform float grain_scale : hint_range(1.0, 8.0, 0.5) = 3.0;

group_uniforms Scanlines;
uniform float scanline_strength : hint_range(0.0, 0.12, 0.005) = 0.035;
uniform float scanline_count : hint_range(100.0, 800.0, 10.0) = 340.0;
uniform float scanline_softness : hint_range(0.1, 2.0, 0.1) = 0.6;

group_uniforms Scratches;
uniform float scratch_strength : hint_range(0.0, 0.08, 0.005) = 0.02;
uniform float scratch_density : hint_range(0.5, 5.0, 0.25) = 2.0;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01) = 0.08;
uniform float vignette_radius : hint_range(0.3, 1.5, 0.05) = 0.85;


// ── Hash functions ────────────────────────────────────────────────────────────

// Fast 2D hash for grain
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise for scratches
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
	vec4 base = COLOR;
	vec2 uv = UV;
	vec2 local_uv = uv * grain_scale;

	// ── Film grain ──────────────────────────────────────────────────────
	// Multi-octave grain for a more organic look
	float grain = hash12(local_uv * 100.0 + fract(TIME * 0.7) * 37.0);
	grain += hash12(local_uv * 200.0 + fract(TIME * 1.3) * 53.0) * 0.5;
	grain = (grain / 1.5) - 0.5; // center around 0
	float grain_amount = grain * grain_strength;

	// ── Scanlines ───────────────────────────────────────────────────────
	float scan_y = uv.y * scanline_count;
	float scanline = sin(scan_y * 3.14159) * 0.5 + 0.5;
	scanline = pow(scanline, scanline_softness);
	float scan_amount = (1.0 - scanline) * scanline_strength;

	// Subtle horizontal band variation (like old CRT)
	float band = vnoise(vec2(0.0, uv.y * 8.0 + TIME * 0.05));
	scan_amount += band * scanline_strength * 0.3;

	// ── Scratches ───────────────────────────────────────────────────────
	// Long thin horizontal scratches
	float scratch = 0.0;
	for (float i = 0.0; i < 3.0; i++) {
		vec2 scratch_uv = vec2(uv.x * scratch_density + i * 7.3, uv.y * (40.0 + i * 15.0));
		float s = vnoise(scratch_uv);
		s = smoothstep(0.82, 0.95, s);
		// Make scratches more horizontal
		float angle = vnoise(vec2(i * 3.7, 0.0)) * 0.02;
		s *= smoothstep(0.0, 0.1, abs(sin((uv.x + uv.y * angle) * 50.0 + i * 10.0)));
		scratch += s;
	}
	scratch *= scratch_strength / 3.0;

	// ── Vignette ────────────────────────────────────────────────────────
	vec2 vc = uv - 0.5;
	float vignette = length(vc) * 2.0;
	vignette = smoothstep(vignette_radius, vignette_radius - 0.4, vignette);
	float vig_amount = (1.0 - vignette) * vignette_strength;

	// ── Combine ─────────────────────────────────────────────────────────
	// Grain brightens randomly, scanlines darken, scratches brighten
	vec3 result = base.rgb;
	result += grain_amount;                    // grain (additive, signed)
	result -= scan_amount;                      // scanlines darken
	result += scratch;                          // scratches lighten
	result -= vig_amount;                       // vignette darkens edges

	// Subtle color shift in the grain for a metallic feel
	result.r += grain_amount * 0.15;
	result.b -= grain_amount * 0.10;

	COLOR = vec4(result, base.a);
}
