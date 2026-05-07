shader_type canvas_item;

// ── UI Material Overlay — GLM Neural ───────────────────────────────────────
// Electric amber neural field: flowing data streams, synaptic pulse patterns,
// and a warm golden luminosity that breathes with audio.  Inspired by the
// architecture of a neural network — layers of flowing information, nodes
// that light up with activation, and a deep void background from which
// meaning emerges.  The specular edge glow simulates energy flowing through
// a network, while caustic-like patterns evoke interconnected pathways.

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.025;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 3.0;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 0.8;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.08;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.82;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.015;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.35;

group_uniforms Neural;
uniform float specular_strength : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float specular_y_pos    : hint_range(0.1, 0.9, 0.05)  = 0.25;
uniform float specular_height   : hint_range(0.02, 0.3, 0.01) = 0.15;
uniform float corner_radius     : hint_range(0.0, 0.15, 0.005) = 0.04;
uniform float beat              : hint_range(0.0, 1.0)          = 0.0;
uniform float energy            : hint_range(0.0, 1.0)          = 0.0;
uniform float bass              : hint_range(0.0, 1.0)          = 0.0;
uniform float wave_seed         : hint_range(0.0, 100.0, 0.1)   = 0.0;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.05;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.025;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;
uniform float caustic_scale     : hint_range(1.0, 20.0, 0.5)  = 8.0;
uniform float iridescence       : hint_range(0.0, 1.0, 0.05)  = 0.55;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise for flowing data streams
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

// Fractal Brownian Motion — layered neural activity
float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += vnoise(p) * amp;
		p *= 2.15;
		amp *= 0.5;
	}
	return val;
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  FILM GRAIN  (soft, warm-tinted noise)
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 90.0 + fract(t_a * 0.6) * 33.0);
	grain += hash12(g_uv * 180.0 + fract(t_a * 1.1) * 51.0) * 0.5;
	grain += hash12(g_uv * 360.0 + fract(t_a * 1.8) * 73.0) * 0.25;
	grain = (grain / 1.75) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  PULSING VIGNETTE  (bass-breathing void)
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	float vig_pulse = sin(t * vignette_pulse_spd + wave_seed * 0.15) * vignette_pulse;
	vig_pulse += bass * 0.008;
	float vig_r = vignette_radius + vig_pulse;
	float vignette = smoothstep(vig_r, vig_r - 0.45, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  NEURAL ACTIVITY FIELD
	//      Flowing data streams and synaptic activation pulses.
	//      Horizontal layers of flowing noise simulate data flowing
	//      through network layers.  Audio drives activation intensity.
	// ══════════════════════════════════════════════════════════════════════

	// ── Flowing data streams ─────────────────────────────────────────
	// Multiple layers of noise create horizontal flow patterns
	// that look like data flowing through network layers
	float ws = wave_seed;

	vec2 stream_uv = uv;
	stream_uv.x += t * 0.06 + ws * 0.1;

	// Layer 1: slow broad flow — base data current
	float stream1 = fbm(stream_uv * 2.5 + vec2(0.0, ws * 0.3));

	// Layer 2: medium turbulence — signal processing
	float stream2 = vnoise(stream_uv * 5.0 + vec2(t * 0.12, ws * 0.7));

	// Layer 3: fine detail — individual activations
	float stream3 = vnoise(stream_uv * 12.0 + vec2(-t * 0.08, ws * 1.2));

	// Combine into neural activity field
	float neural_field = stream1 * 0.5 + stream2 * 0.35 + stream3 * 0.15;

	// Audio reactivity — field intensifies with music
	float audio_mod = 1.0 + beat * 0.25 + energy * 0.15 + bass * 0.10;
	neural_field *= audio_mod;

	// Create horizontal banding — "layers" of the network
	float layer_mask = sin(uv.y * 14.0 + neural_field * 3.5 + t * 0.2 + ws * 0.4);
	layer_mask = smoothstep(0.2, 0.8, layer_mask);

	// Activation pulse — bright nodes that light up
	float pulse_phase = fract(neural_field * 2.0 + t * 0.15 + ws * 0.2);
	float activation = smoothstep(0.85, 0.95, pulse_phase) * (0.5 + energy * 0.5);

	// ── Neural caustic pattern ────────────────────────────────────────
	// Interconnected pathways — like a network graph glowing
	float c_t = t * 0.10;
	float c1 = sin(uv.x * caustic_scale + sin(uv.y * caustic_scale * 1.2 + c_t) * 1.8);
	float c2 = cos(uv.y * caustic_scale * 0.85 + cos(uv.x * caustic_scale * 0.75 - c_t * 0.6) * 1.6);
	float caustic = abs(c1 + c2) * 0.3 + 0.5;
	caustic = caustic * caustic * caustic; // sharper falloff — more "digital"

	// ══════════════════════════════════════════════════════════════════════
	//  4.  SPECULAR  — energy conduit edge glow
	// ══════════════════════════════════════════════════════════════════════

	// Rounded rectangle SDF for panel edge glow
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0);

	// Exponential glow from the curved edge
	float fade = 3.2 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);

	// Directional bias — overhead light
	float dir_bias = 1.0 + (0.5 - uv.y) * 0.5;
	edge_glow *= dir_bias;

	// Flowing wave animation — energy pulsing through the network
	float wave_amp = 0.05 + beat * 0.12 + energy * 0.06;
	float wave  = sin(uv.x * 22.0 + t * 1.5 + ws * 6.28 + sin(uv.y * 9.0 + t * 0.65 + ws) * 1.8) * wave_amp;
	wave += sin(uv.y * 16.0 - t * 1.0 + ws * 3.50 + cos(uv.x * 7.0 + t * 0.45 + ws * 0.6) * 1.3) * wave_amp * 0.65;
	edge_glow *= (1.0 + wave);

	// Soft top highlight — light source
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 280.0) * 0.38;

	// Combine specular: edge glow + caustics + top highlight
	float specular = edge_glow * mix(1.0, caustic, 0.35) + top_glow;
	// Add neural activation glints
	specular += activation * 0.3;

	// Iridescent color — warm amber center, electric teal at edges
	float edge_f = abs(uv.x - 0.5) * 2.0;
	vec3 spec_color = mix(
		vec3(1.0, 0.88, 0.65),    // warm amber-gold center
		vec3(0.25, 0.70, 0.85),    // electric teal at edges
		edge_f * iridescence
	);

	// ══════════════════════════════════════════════════════════════════════
	//  5.  FRESNEL, GRADIENT, BEVEL
	// ══════════════════════════════════════════════════════════════════════

	// Top-to-bottom lighting gradient
	float lighting_grad = 1.0 - uv.y;

	// Fresnel edge bloom — edges glow like energy conduits
	float f_edge_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fresnel = smoothstep(fresnel_width, 0.0, f_edge_d);

	// Directional bevel — light from top-left
	float bv_top    = smoothstep(bevel_width, 0.0, uv.y);
	float bv_left   = smoothstep(bevel_width, 0.0, uv.x);
	float bv_bottom = smoothstep(bevel_width, 0.0, 1.0 - uv.y);
	float bv_right  = smoothstep(bevel_width, 0.0, 1.0 - uv.x);
	float bevel_hi  = bv_top * 0.6 + bv_left * 0.4;
	float bevel_sh  = bv_bottom * 0.4 + bv_right * 0.6;

	// Micro-texture — digital grain
	float gloss_tex = hash12(uv * 450.0 + 5.3) - 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Neural palette
	vec3 col_amber   = vec3(0.95, 0.72, 0.15);  // electric amber — primary
	vec3 col_gold    = vec3(1.00, 0.85, 0.30);   // bright gold — highlights
	vec3 col_teal    = vec3(0.20, 0.65, 0.80);    // cool teal — secondary
	vec3 col_cream   = vec3(1.00, 0.95, 0.85);    // warm cream — specular
	vec3 col_deep    = vec3(0.06, 0.04, 0.02);    // deep void — shadows

	// Grain (signed additive)
	result += grain_amt;

	// Vignette darkens edges
	result -= vig_amt;

	// Neural activity — flowing streams with warm amber glow
	float neural_brightness = neural_field * layer_mask;
	result += neural_brightness * col_amber * gloss_texture_str * 3.0;

	// Activation pulses — bright nodes lighting up
	result += activation * col_gold * gloss_texture_str * 2.0;

	// Specular — edge glow with neural caustics
	result += specular * spec_color * specular_strength;

	// Lighting gradient
	result += (lighting_grad - 0.4) * gradient_strength;

	// Fresnel edge bloom — amber-teal glow
	result += fresnel * fresnel_strength * mix(col_amber, col_teal, edge_f);

	// Bevel
	result += bevel_hi * bevel_strength * vec3(1.0, 0.90, 0.65);
	result -= bevel_sh * bevel_strength * 0.6 * vec3(0.25, 0.18, 0.08);

	// Micro-texture
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
