shader_type canvas_item;

// ── UI Material Overlay — Iguana Glass ──────────────────────────────────────
// Reptilian scale texture with pearlescent iridescence and organic
// movement.  Overlapping semicircular scales catch light differently
// at each angle — amber to teal-green color shift.  Scales breathe
// with the bass, ripple with the beat.  Very different from Aero's
// smooth Frutiger gloss.

group_uniforms Grain;
uniform float grain_strength  : hint_range(0.0, 0.15, 0.005) = 0.03;
uniform float grain_scale     : hint_range(1.0, 8.0, 0.5)   = 2.5;
uniform float grain_speed     : hint_range(0.1, 5.0, 0.1)   = 0.6;

group_uniforms Vignette;
uniform float vignette_strength : hint_range(0.0, 0.3, 0.01)  = 0.07;
uniform float vignette_radius   : hint_range(0.3, 1.5, 0.05)  = 0.80;
uniform float vignette_pulse    : hint_range(0.0, 0.1, 0.005) = 0.015;
uniform float vignette_pulse_spd : hint_range(0.1, 3.0, 0.1)  = 0.25;

group_uniforms Glass;
uniform float specular_strength : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float specular_y_pos    : hint_range(0.1, 0.9, 0.05)  = 0.25;
uniform float specular_height   : hint_range(0.02, 0.3, 0.01) = 0.15;
uniform float corner_radius     : hint_range(0.0, 0.15, 0.005) = 0.05;
uniform float beat              : hint_range(0.0, 1.0)          = 0.0;
uniform float energy            : hint_range(0.0, 1.0)          = 0.0;
uniform float bass              : hint_range(0.0, 1.0)          = 0.0;
uniform float wave_seed         : hint_range(0.0, 100.0, 0.1)   = 0.0;
uniform float gradient_strength : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float fresnel_strength  : hint_range(0.0, 0.5, 0.01)  = 0.0;
uniform float fresnel_width     : hint_range(0.01, 0.2, 0.01) = 0.06;
uniform float bevel_strength    : hint_range(0.0, 0.3, 0.01)  = 0.0;
uniform float bevel_width       : hint_range(0.005, 0.1, 0.005) = 0.0;
uniform float gloss_texture_str : hint_range(0.0, 0.1, 0.005) = 0.0;
uniform float caustic_scale     : hint_range(1.0, 20.0, 0.5)  = 6.0;
uniform float iridescence       : hint_range(0.0, 1.0, 0.05)  = 0.55;


// ── Hash / noise helpers ─────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// ── Scale pattern ────────────────────────────────────────────────────────────
// Overlapping semicircular scales arranged in staggered rows.
// Returns: vec2(distance_to_nearest_scale_edge, row_offset_for_iridescence)

vec2 scale_pattern(vec2 uv, float scale, float t, float ws, float beat_amt, float bass_amt) {
	// Scale grid — staggered rows like real reptile skin
	vec2 s_uv = uv * scale;

	// Subtle living movement — scales shift with audio
	s_uv.x += sin(uv.y * 12.0 + t * 0.15 + ws) * (0.03 + bass_amt * 0.02);
	s_uv.y += sin(uv.x * 10.0 + t * 0.12 + ws * 0.7) * (0.02 + beat_amt * 0.015);

	float row = floor(s_uv.y);
	float row_half = fract(row * 0.5);

	// Stagger every other row
	s_uv.x += step(0.5, row_half) * 0.5;

	// Cell ID and local UV
	vec2 cell_id = vec2(floor(s_uv.x), row);
	vec2 local = fract(s_uv);

	// Per-cell randomness from cell ID
	float cell_rand = hash12(cell_id + ws * 0.01);

	// Semicircular scale shape — rounded top, flat bottom
	// Each scale is a half-ellipse
	vec2 center = vec2(0.5, 0.0);
	float aspect = 0.7 + cell_rand * 0.15;
	vec2 d = local - center;
	d.x /= aspect;

	// Distance to the semicircle edge
	float semi_dist = length(d) - 0.5;

	// Add a slight ridge at the top of each scale
	float ridge = smoothstep(0.02, 0.0, abs(local.y - 0.85)) * 0.15;
	semi_dist -= ridge;

	// Feather the edge slightly for organic feel
	float edge = smoothstep(0.04, 0.0, semi_dist);

	// Overlap hint — darkening between scales
	float gap = smoothstep(0.0, 0.06, semi_dist);

	return vec2(edge, row_half + cell_rand * 0.3);
}


void fragment() {
	float t = TIME;
	vec2 uv = UV;
	vec4 base = COLOR;

	// ══════════════════════════════════════════════════════════════════════
	//  1.  FILM GRAIN  — soft, slow, organic
	// ══════════════════════════════════════════════════════════════════════
	vec2 g_uv = uv * grain_scale;
	float t_a = t * grain_speed;
	float grain  = hash12(g_uv * 80.0 + fract(t_a * 0.5) * 31.0);
	grain += hash12(g_uv * 160.0 + fract(t_a * 0.9) * 47.0) * 0.5;
	grain += hash12(g_uv * 320.0 + fract(t_a * 1.5) * 67.0) * 0.25;
	grain = (grain / 1.75) - 0.5;
	float grain_amt = grain * grain_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  2.  PULSING VIGNETTE  — bass-breathing
	// ══════════════════════════════════════════════════════════════════════
	vec2 vc = uv - 0.5;
	float vdist = length(vc) * 2.0;
	float vig_breath = sin(t * vignette_pulse_spd + wave_seed * 0.1) * vignette_pulse;
	vig_breath += bass * 0.01;
	float vig_r = vignette_radius + vig_breath;
	float vignette = smoothstep(vig_r, vig_r - 0.5, vdist);
	float vig_amt = (1.0 - vignette) * vignette_strength;

	// ══════════════════════════════════════════════════════════════════════
	//  3.  REPTILIAN SCALE TEXTURE
	//      Staggered overlapping scales with pearlescent color shift.
	// ══════════════════════════════════════════════════════════════════════

	// Scale pattern driven by caustic_scale uniform (reused as scale density)
	float beat_amt = beat * 0.3;
	float bass_amt = bass * 0.2;
	vec2 sp = scale_pattern(uv, caustic_scale, t, wave_seed, beat_amt, bass_amt);
	float scale_edge = sp.x;
	float row_phase = sp.y;

	// ══════════════════════════════════════════════════════════════════════
	//  4.  PEARLESCENT IRIDESCENCE
	//      Color shifts across scale rows — amber ↔ teal ↔ gold
	// ══════════════════════════════════════════════════════════════════════

	// Phase varies by row position + angle + time for living color shift
	float irid_phase = row_phase
		+ (uv.x - 0.5) * 2.0
		+ sin(uv.y * 6.0 + t * 0.08 + wave_seed * 0.3) * 0.4;

	vec3 col_amber  = vec3(0.90, 0.78, 0.45);   // warm amber-gold
	vec3 col_teal   = vec3(0.35, 0.72, 0.55);   // deep iguana teal
	vec3 col_cream  = vec3(0.95, 0.92, 0.80);   // pale cream highlight

	float phase_t = sin(irid_phase * 3.14159) * 0.5 + 0.5;
	vec3 irid_color = mix(col_amber, col_teal, phase_t);
	// Add cream shimmer at scale edges
	irid_color = mix(irid_color, col_cream, scale_edge * 0.4);

	// Apply iridescence strength
	vec3 irid_tint = mix(vec3(1.0), irid_color, iridescence * 0.5);

	// ══════════════════════════════════════════════════════════════════════
	//  5.  SPECULAR  — curved edge glow + scale highlights
	// ══════════════════════════════════════════════════════════════════════

	// Rounded rectangle SDF for panel edge glow
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0);
	float fade = 2.8 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);
	edge_glow *= 1.0 + (0.5 - uv.y) * 0.4;

	// Audio-reactive wave
	float wave_amp = 0.04 + beat * 0.10 + bass * 0.06;
	float ws = wave_seed;
	float wave  = sin(uv.x * 18.0 + t * 1.0 + ws * 6.28) * wave_amp;
	wave += sin(uv.y * 12.0 - t * 0.7 + ws * 3.14) * wave_amp * 0.5;
	edge_glow *= (1.0 + wave);

	// Soft top highlight
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 250.0) * 0.35;

	float specular = edge_glow + top_glow;

	// Scale edge highlights — light catching the rim of each scale
	float scale_highlight = scale_edge * (0.5 + bass * 0.3);

	// ══════════════════════════════════════════════════════════════════════
	//  6.  FRESNEL, GRADIENT, BEVEL
	// ══════════════════════════════════════════════════════════════════════

	float lighting_grad = 1.0 - uv.y;

	float f_edge_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fresnel = smoothstep(fresnel_width * 1.3, 0.0, f_edge_d);

	float bv_top    = smoothstep(bevel_width, 0.0, uv.y);
	float bv_left   = smoothstep(bevel_width, 0.0, uv.x);
	float bv_bottom = smoothstep(bevel_width, 0.0, 1.0 - uv.y);
	float bv_right  = smoothstep(bevel_width, 0.0, 1.0 - uv.x);
	float bevel_hi  = bv_top * 0.5 + bv_left * 0.5;
	float bevel_sh  = bv_bottom * 0.5 + bv_right * 0.5;

	// Micro-texture grain
	float gloss_tex = hash12(uv * 400.0 + 11.7) - 0.5;

	// ══════════════════════════════════════════════════════════════════════
	//  COMBINE
	// ══════════════════════════════════════════════════════════════════════
	vec3 result = base.rgb;

	// Film grain
	result += grain_amt;

	// Vignette
	result -= vig_amt;

	// Scale pattern — subtle darkening between scales for depth
	result -= (1.0 - scale_edge) * gloss_texture_str * 2.0;

	// Pearlescent tint over everything
	result *= irid_tint;

	// Specular — edge glow + top highlight in iridescent color
	result += specular * specular_strength * irid_color;

	// Scale edge highlights — light catching scale rims
	result += scale_highlight * specular_strength * 0.5 * col_cream;

	// Gradient
	result += (lighting_grad - 0.4) * gradient_strength;

	// Fresnel — greenish edge bloom
	result += fresnel * fresnel_strength * vec3(0.45, 0.85, 0.60);

	// Bevel
	result += bevel_hi * bevel_strength * vec3(1.0, 0.95, 0.80);
	result -= bevel_sh * bevel_strength * 0.5 * vec3(0.50, 0.70, 0.55);

	// Micro-texture
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
