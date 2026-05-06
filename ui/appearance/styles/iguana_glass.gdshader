shader_type canvas_item;

// ── UI Material Overlay — Iguana Glass ──────────────────────────────────────
// Living reptilian skin: Voronoi-based overlapping scales with 3D curvature,
// pearlescent iridescence, and deep organic flow.  Scales breathe with bass,
// ripple with beats, and shimmer with a liquid pearlescent sheen that drifts
// across the surface.  Inspired by the Aero shader's flowing caustics but
// fully reptilian in character.

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

// Smooth value noise for organic flow distortion
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion — layered noise for rich organic flow
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}


// ── Voronoi scale pattern ────────────────────────────────────────────────────
// Authentic reptilian scales via staggered hex-grid Voronoi cells.
// Each scale is a convex cell with curved surface (3D dome), ridge at the
// seam between cells, and per-cell random variation.  Audio drives the
// distortion field so scales ripple and breathe.
//
// Returns: vec4(
//   x = cell_edge   — smooth edge/ridge between scales (0-1)
//   y = cell_center — how close to scale center (0-1), used for curvature
//   z = cell_id     — per-cell random value for iridescence
//   w = row_phase   — row offset for color banding
// )

vec4 scale_field(vec2 uv, float density, float t, float ws, float beat_amt, float bass_amt) {
	// Scale UV to density
	vec2 s_uv = uv * density;

	// ── Organic flow distortion ──
	// Layered noise displacement makes the whole scale field undulate
	// slowly, like skin breathing.  Bass makes it deeper, beat adds snap.
	float flow_t = t * 0.08;
	vec2 flow_off = vec2(
		fbm(s_uv * 0.15 + vec2(flow_t, flow_t * 0.7) + ws * 0.3),
		fbm(s_uv * 0.15 + vec2(-flow_t * 0.6, flow_t * 1.1) + ws * 0.5)
	);
	float flow_str = 0.25 + bass_amt * 0.35;
	s_uv += (flow_off - 0.5) * flow_str;

	// Beat ripple — radially expanding distortion from a wandering point
	vec2 beat_origin = vec2(
		sin(ws * 2.17) * 3.0,
		cos(ws * 1.53) * 3.0
	);
	float beat_rdist = length(s_uv - beat_origin);
	float ripple = sin(beat_rdist * 3.0 - t * 4.0) * beat_amt * 0.12;
	ripple *= exp(-beat_rdist * 0.3); // attenuate with distance
	s_uv += normalize(s_uv - beat_origin + 0.001) * ripple;

	// ── Staggered hex grid ──
	// Rows are offset every other line for the classic scale overlap pattern
	float row = floor(s_uv.y);
	float row_half = fract(row * 0.5);
	float stagger = step(0.5, row_half) * 0.5;
	s_uv.x += stagger;

	// Voronoi: find nearest and second-nearest cell centers
	vec2 cell_uv = s_uv;
	vec2 nearest_cell = floor(cell_uv);
	vec2 nearest_local = fract(cell_uv);

	float min_dist = 10.0;
	float second_dist = 10.0;
	vec2 cell_a = nearest_cell; // closest cell id

	// 3x3 neighbor search
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 neighbor = vec2(float(i), float(j));
			vec2 cell_id = nearest_cell + neighbor;

			// Per-cell jitter for organic irregularity
			vec2 jitter = (hash22(cell_id + ws * 0.01) - 0.5) * 0.25;

			// Animate cell centers gently — each scale sways
			jitter += vec2(
				sin(t * 0.2 + hash12(cell_id) * 6.28 + ws) * 0.04,
				cos(t * 0.18 + hash12(cell_id + 7.0) * 6.28 + ws) * 0.03
			) * (1.0 + bass_amt);

			vec2 diff = neighbor + jitter - nearest_local;
			float d = length(diff);

			if (d < min_dist) {
				second_dist = min_dist;
				min_dist = d;
				cell_a = cell_id;
			} else if (d < second_dist) {
				second_dist = d;
			}
		}
	}

	// ── Scale geometry ──
	// Edge detection: the seam between two Voronoi cells
	// sharpness controls how crisp the scale ridges are
	float edge_raw = second_dist - min_dist;
	float cell_edge = smoothstep(0.0, 0.12, edge_raw);  // 0 at seam, 1 inside

	// Curvature: distance from cell center → dome shape
	// This gives each scale a 3D curved surface feel
	float curvature = 1.0 - smoothstep(0.0, 0.65, min_dist);

	// Ridge highlight: thin bright line at the seam (like raised scale edges)
	float ridge = smoothstep(0.08, 0.0, edge_raw) * 0.6;

	// Per-cell random value for iridescence
	float cell_rand = hash12(cell_a + ws * 0.01);

	return vec4(cell_edge, curvature, cell_rand, row_half + cell_rand * 0.2);
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
	//  3.  VORONOI SCALE FIELD
	//      Living scales with 3D curvature, ridged seams, organic flow.
	// ══════════════════════════════════════════════════════════════════════
	float beat_amt = beat * 0.4;
	float bass_amt = bass * 0.3;
	vec4 sf = scale_field(uv, caustic_scale, t, wave_seed, beat_amt, bass_amt);
	float cell_edge   = sf.x;   // 1 inside scale, 0 at seam
	float curvature   = sf.y;   // dome height (0 at edge, 1 at center)
	float cell_rand   = sf.z;   // per-cell random for iridescence
	float row_phase   = sf.w;   // row offset for color banding

	// ══════════════════════════════════════════════════════════════════════
	//  4.  PEARLESCENT IRIDESCENCE
	//      Color flows across the scale field — amber ↔ teal ↔ emerald.
	//      Each scale has a unique phase offset.  The whole field drifts.
	// ══════════════════════════════════════════════════════════════════════

	// Flowing iridescent phase: combines cell random, position, and slow drift
	float irid_phase = cell_rand * 6.28
		+ (uv.x - 0.5) * 1.8
		+ sin(uv.y * 4.0 + t * 0.06 + wave_seed * 0.3) * 0.5
		+ t * 0.03; // slow global drift

	vec3 col_amber   = vec3(0.92, 0.78, 0.38);   // warm golden amber
	vec3 col_teal    = vec3(0.25, 0.72, 0.58);    // deep jungle teal
	vec3 col_emerald = vec3(0.18, 0.65, 0.40);    // dark emerald
	vec3 col_cream   = vec3(0.96, 0.93, 0.82);    // pale cream highlight
	vec3 col_silver  = vec3(0.80, 0.88, 0.85);    // cool silver for ridges

	// Three-way color blend cycling through the palette
	float phase_sin = sin(irid_phase);
	float phase_cos = cos(irid_phase * 1.3 + 0.5);
	vec3 irid_color = mix(col_amber, col_teal, phase_sin * 0.5 + 0.5);
	irid_color = mix(irid_color, col_emerald, phase_cos * 0.3 + 0.3);

	// Scale center gets the warm color, edges shift cooler
	irid_color = mix(irid_color * 0.85, col_cream, curvature * 0.2);

	// Global iridescence tint
	vec3 irid_tint = mix(vec3(1.0), irid_color, iridescence * 0.55);

	// ══════════════════════════════════════════════════════════════════════
	//  5.  3D SCALE LIGHTING
	//      Each scale dome catches light.  Seam ridges are highlighted.
	//      Directional light from upper-left.
	// ══════════════════════════════════════════════════════════════════════

	// Fake directional light — scales facing upper-left are brighter
	// Use curvature as a proxy for surface normal
	float light_dir = curvature * (1.0 - uv.y * 0.3 + (1.0 - uv.x) * 0.2);

	// Seam ridge highlight — light catches the raised edges between scales
	float ridge_glow = (1.0 - cell_edge) * (0.3 + bass * 0.15);

	// Scale body shadow — subtle darkening in the lower-right of each scale
	// (opposite the light direction) — gives real 3D depth
	float scale_shadow = (1.0 - curvature) * cell_edge * 0.3;

	// ══════════════════════════════════════════════════════════════════════
	//  6.  SPECULAR  — curved edge glow + scale dome highlights
	// ══════════════════════════════════════════════════════════════════════

	// Rounded rectangle SDF for panel edge glow
	vec2 rp = abs(uv - 0.5);
	vec2 rb = vec2(0.5) - corner_radius;
	float sdf = length(max(rp - rb, 0.0)) - corner_radius;
	float edge_dist = max(-sdf, 0.0);
	float fade = 2.8 / max(specular_height, 0.001);
	float edge_glow = exp(-edge_dist * fade);
	edge_glow *= 1.0 + (0.5 - uv.y) * 0.4;

	// Audio-reactive flowing wave — like aero's liquid glass but scalier
	float wave_amp = 0.05 + beat * 0.12 + bass * 0.08;
	float ws = wave_seed;
	float wave  = sin(uv.x * 20.0 + t * 1.2 + ws * 6.28 + sin(uv.y * 8.0 + t * 0.6 + ws) * 1.8) * wave_amp;
	wave += sin(uv.y * 14.0 - t * 0.8 + ws * 3.14 + cos(uv.x * 6.0 + t * 0.4 + ws * 0.5) * 1.2) * wave_amp * 0.6;
	edge_glow *= (1.0 + wave);

	// Soft top highlight
	float d_top = max(uv.y - specular_y_pos, 0.0);
	float top_glow = exp(-d_top * d_top * 250.0) * 0.35;

	float specular = edge_glow + top_glow;

	// Scale dome specular — light glinting off curved scale surfaces
	float dome_spec = curvature * curvature * (0.4 + energy * 0.3);

	// ══════════════════════════════════════════════════════════════════════
	//  7.  FRESNEL, GRADIENT, BEVEL
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

	// Scale depth — darken between scales (the seams/grooves)
	float groove_dark = (1.0 - cell_edge) * 0.5 + scale_shadow;
	result -= groove_dark * gloss_texture_str * 2.5;

	// Scale lighting — directional light on curved surfaces
	result += light_dir * gloss_texture_str * 1.5 * irid_color;

	// Seam ridge highlights — light catching the raised edges
	result += ridge_glow * gloss_texture_str * col_silver;

	// Pearlescent tint over everything
	result *= irid_tint;

	// Specular — edge glow + top highlight in iridescent color
	result += specular * specular_strength * mix(irid_color, col_cream, 0.3);

	// Dome specular — bright glint on scale centers
	result += dome_spec * specular_strength * 0.6 * col_cream;

	// Gradient
	result += (lighting_grad - 0.4) * gradient_strength;

	// Fresnel — teal-green edge bloom
	result += fresnel * fresnel_strength * vec3(0.35, 0.80, 0.55);

	// Bevel
	result += bevel_hi * bevel_strength * vec3(1.0, 0.95, 0.80);
	result -= bevel_sh * bevel_strength * 0.5 * vec3(0.40, 0.65, 0.50);

	// Micro-texture
	result += gloss_tex * gloss_texture_str;

	COLOR = vec4(result, base.a);
}
