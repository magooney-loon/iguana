shader_type canvas_item;

// ── Audio uniforms ────────────────────────────────────────────────────
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

uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;

uniform vec2  mouse_pos  = vec2(0.5, 0.5);
uniform float mouse_down : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define PI  3.14159265359
#define TAU 6.28318530718

// ── Voronoi hash → [0,1]² ─────────────────────────────────────────────
vec2 h2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// ── Animated Voronoi ──────────────────────────────────────────────────
// Returns: x=d1 (nearest dist), y=membrane gap (d2-d1), z=cell hash [0,1]
// Each cell center breathes on its own phase — no global synchrony.
// Amplitude 0.32 keeps motion smooth; 0.40 was too twitchy.
vec3 voro(vec2 p, float t, float spd) {
	vec2 ip = floor(p), fp = fract(p);
	float d1 = 9.0, d2 = 9.0, ch = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 nb  = vec2(float(x), float(y));
			vec2 rh  = h2(ip + nb);
			vec2 ctr = nb + rh + 0.32 * sin(t * spd + rh * TAU);
			float d  = length(ctr - fp);
			if (d < d1) { d2 = d1; d1 = d; ch = rh.x; }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d1, d2 - d1, ch);
}

// ── 3-level cascaded domain warp ──────────────────────────────────────
// Strictly Cartesian — no atan anywhere, no seam.
// L1: slow viscous drift   L2: medium bulge/stretch   L3: fine boiling
// boil amplitude is driven ONLY by energy (smooth signal, not beat)
// so the warp never twitches.
vec2 fluid_warp(vec2 uv, float t, float bass_amp, float boil) {
	float spd = 0.022 + boil * 0.014;

	vec2 uv1  = uv * 0.54 + t * spd;
	float wx1 = texture(noise_tex, uv1).r                  * 2.0 - 1.0;
	float wy1 = texture(noise_tex, uv1 + vec2(0.5, 0.3)).r * 2.0 - 1.0;
	vec2  w1  = uv + vec2(wx1, wy1) * (0.25 + bass_amp * 0.16);

	vec2 uv2  = w1 * 1.14 - t * spd * 0.60 + vec2(0.4, 0.2);
	float wx2 = texture(noise_tex, uv2).r                  * 2.0 - 1.0;
	float wy2 = texture(noise_tex, uv2 + vec2(0.7, 0.1)).r * 2.0 - 1.0;
	vec2  w2  = w1 + vec2(wx2, wy2) * (0.13 + boil * 0.09);

	vec2 uv3  = w2 * 2.65 + t * spd * 1.8 + vec2(0.7, 0.5);
	float wx3 = texture(noise_tex, uv3).r                  * 2.0 - 1.0;
	float wy3 = texture(noise_tex, uv3 + vec2(0.3, 0.4)).r * 2.0 - 1.0;

	return w2 + vec2(wx3, wy3) * (0.04 + boil * 0.08);
}

// ── 4-octave FBM ──────────────────────────────────────────────────────
float fbm(vec2 p, float t, float spd) {
	float v = 0.0;
	v += texture(noise_tex, p * 1.00 + t * spd * 1.0               ).r * 0.5000;
	v += texture(noise_tex, p * 2.10 - t * spd * 0.7 + vec2(0.3, 0.1)).r * 0.2500;
	v += texture(noise_tex, p * 4.40 + t * spd * 1.3 + vec2(0.6, 0.7)).r * 0.1250;
	v += texture(noise_tex, p * 9.10 - t * spd * 0.5 + vec2(0.1, 0.4)).r * 0.0625;
	return v * (1.0 / 0.9375);
}

// ── Biological colour palette ─────────────────────────────────────────
// Arterial red → necrotic amber → bile yellow → slime green → bruised purple
// smoothstep between stops makes colours bleed into each other.
vec3 bio_palette(float t) {
	t = fract(t);
	float s = t * 5.0;
	float f = smoothstep(0.0, 1.0, fract(s));
	int   i = int(floor(s));
	if (i == 0) return mix(vec3(0.58, 0.04, 0.07), vec3(0.44, 0.17, 0.01), f);
	if (i == 1) return mix(vec3(0.44, 0.17, 0.01), vec3(0.50, 0.64, 0.04), f);
	if (i == 2) return mix(vec3(0.50, 0.64, 0.04), vec3(0.09, 0.43, 0.03), f);
	if (i == 3) return mix(vec3(0.09, 0.43, 0.03), vec3(0.24, 0.02, 0.37), f);
	             return mix(vec3(0.24, 0.02, 0.37), vec3(0.58, 0.04, 0.07), f);
}

void fragment() {
	vec2  uv     = UV;
	float t      = time_val;
	float aspect = rect_size.x / rect_size.y;
	vec2  uv_c   = (uv - 0.5) * vec2(aspect, 1.0);

	// ── Fluid field warp ──────────────────────────────────────────
	// Only energy (slow-moving, continuous) drives boil — not beat/kick.
	// Percussion used to modulate boil here and caused all the twitching.
	float boil_amp = energy * 0.42;
	vec2 warped = fluid_warp(uv, t, bass, boil_amp);

	// Mouse: stir the petri dish toward the cursor
	if (mouse_down > 0.0) {
		vec2 to_cursor = mouse_pos - uv;
		warped += to_cursor * exp(-length(to_cursor) * 3.8) * mouse_down * 0.13;
	}

	// ── Four-scale Voronoi — biological hierarchy ─────────────────
	//
	//  XL  ~1.4 cells  tissue / organ background — gross colour regions
	//   L  ~2.8 cells  primary cell bodies       — main visual structure
	//   S  ~8.5 cells  organelles / cytoplasm     — interior texture
	//  XS  ~20  cells  protein granules           — fine surface grain
	//
	// All animation speeds driven ONLY by energy, never by beat/kick.

	// XL — tissue layer (quasi-static, moves like oil in a pan)
	float scl_XL = 1.35 + sub_bass * 0.25;
	vec3  vXL    = voro(warped * scl_XL + vec2(7.31, 4.17), t, 0.07 + energy * 0.035);

	// L — cell bodies
	float scl_L  = 2.7 + sub_bass * 0.45;
	vec3  vL     = voro(warped * scl_L, t, 0.12 + energy * 0.07);

	// S — organelles (offset so they don't align with L boundaries)
	float scl_S  = 8.4 + mid * 1.3;
	vec3  vS     = voro(warped * scl_S + vec2(3.71, 2.13), t * 1.20, 0.19 + energy * 0.11);

	// XS — protein granule layer
	vec3  vXS    = voro(warped * 20.5 + vec2(1.52, 6.83), t * 2.05, 0.32 + energy * 0.18);

	float mem_XL = vXL.y;
	float mem_L  = vL.y;
	float mem_S  = vS.y;
	float mem_XS = vXS.y;
	float cid_XL = vXL.z;
	float cid_L  = vL.z;
	float cid_S  = vS.z;
	float cid_XS = vXS.z;

	// ── Surface fluid textures ─────────────────────────────────────
	float surf  = fbm(warped * 3.2, t, 0.018);   // large wetness sheen
	float surf2 = fbm(warped * 7.0 + vec2(0.5, 0.3), t, 0.013);  // organelle detail
	float stain = fbm(warped * 0.82 + vec2(1.3, 0.7), t, 0.006); // quasi-static colour bleed

	// ── Biological colour composition ─────────────────────────────
	// Tissue type (XL) organises gross colour. Cell hash (L) + stain
	// makes neighbouring cells bleed the same hue. Three colour depths.
	float tissue_t  = fract(cid_XL * 0.73 + stain * 0.27);
	float palette_t = fract(cid_L * 0.54 + tissue_t * 0.30 + stain * 0.16);
	vec3  cell_col  = bio_palette(palette_t);

	vec3  org_col   = bio_palette(fract(cid_S  * 0.50 + surf  * 0.30) + 0.14);
	vec3  gran_col  = bio_palette(fract(cid_XS * 0.42 + surf2 * 0.22) + 0.29);

	// Build interior: cell → organelle → granule, blended by surface noise
	vec3 interior = cell_col;
	interior = mix(interior, org_col,  surf  * 0.40 + surf2 * 0.16);
	interior = mix(interior, gran_col, surf2 * 0.24);

	// Wet slime sheen: sickly green glow in high-noise peaks
	interior += vec3(0.10, 0.22, 0.01) * pow(surf, 3.0) * (0.85 + energy * 0.65);
	// Cytoplasmic depth: darken low-noise regions (dense packed cytoplasm)
	interior *= 0.36 + surf2 * 0.64;

	vec3 col = interior;

	// ── Tissue-scale shadow ───────────────────────────────────────
	// XL boundaries pool with stain — the organ border darkens organically.
	float tissue_edge = exp(-mem_XL * 2.2);
	col *= 1.0 - tissue_edge * 0.50;

	// ── Membrane glows — per-cell colour, multiple scales ─────────

	// L membrane: toxic yellow-green, hue shifts per cell identity.
	// NOT driven by kick/beat — those caused geometry-level twitching.
	float mem_sharp_L = 5.5 + energy * 5.0;
	float mglow_L     = exp(-mem_L * mem_sharp_L);
	// Per-cell iridescence: some membranes lean red-amber, others green
	vec3  mem_col_L   = mix(vec3(0.60, 0.92, 0.05), vec3(0.90, 0.48, 0.02),
	                        smoothstep(0.3, 0.8, cid_L));
	col += mem_col_L * mglow_L * (0.52 + energy * 0.48 + sub_bass * 0.22);

	// S membrane: bile-green, subdued, per-cell variation
	float mem_sharp_S = 14.0 + presence * 8.0;
	float mglow_S     = exp(-mem_S * mem_sharp_S);
	vec3  mem_col_S   = mix(vec3(0.42, 0.58, 0.03), vec3(0.22, 0.40, 0.02), cid_S);
	col += mem_col_S * mglow_S * (0.13 + density * 0.15);

	// XS membrane: barely-visible protein matrix criss-cross
	float mglow_XS = exp(-mem_XS * 28.0);
	col += vec3(0.26, 0.36, 0.02) * mglow_XS * (0.05 + density * 0.07);

	// ── Vacuoles — Voronoi-integrated, not screen-space circles ───
	// Cells whose hash falls in the top third are "vacuolar":
	// large hollow bubbles. They ARE the L-scale Voronoi cells, already
	// deformed by the domain warp, already breathing with the fluid.
	// No separate loop, no separate distance field.
	float is_vacuole = smoothstep(0.58, 0.78, cid_L);

	// Vacuole interior: translucent dark fluid, suppresses cytoplasm colour
	float vac_fill = is_vacuole * smoothstep(0.20, 0.0, mem_L);
	vec3  vac_fluid = mix(vec3(0.28, 0.40, 0.02), vec3(0.16, 0.28, 0.01), surf);
	col = mix(col, vac_fluid * (0.35 + surf * 0.25), vac_fill * 0.85);

	// Vacuole membrane: brighter than normal, slight purple contamination
	vec3  vac_mem = mix(vec3(0.74, 0.94, 0.07), vec3(0.60, 0.18, 0.52),
	                    smoothstep(0.58, 0.78, cid_L) * 0.35);
	col += vac_mem * mglow_L * is_vacuole * 0.60;

	// ── Tendrils — noise-gradient filaments between cells ─────────
	vec2  tn_uv = warped * 5.9 + t * 0.015;
	float tn0   = texture(noise_tex, tn_uv).r;
	float tn_dx = texture(noise_tex, tn_uv + vec2(0.008, 0.000)).r;
	float tn_dy = texture(noise_tex, tn_uv + vec2(0.000, 0.008)).r;
	float tendril = length(vec2(tn0 - tn_dx, tn0 - tn_dy)) * 118.0;
	tendril = pow(clamp(tendril - 0.34, 0.0, 1.0), 2.0);
	col += mix(vec3(0.08, 0.40, 0.02), vec3(0.58, 0.80, 0.04), tendril)
	     * tendril * (0.20 + low_mid * 0.16);

	// ── Percussion — colour layer only, no structure changes ──────

	// Kick: membrane flash at boundaries (not a warp spike)
	col += mem_col_L * mglow_L * kick * 0.70;
	col += mem_col_S * mglow_S * kick * 0.40;

	// Snare: membranes briefly blaze + mild static overlay
	col += vec3(0.70, 0.94, 0.05) * mglow_L * snare * 0.80;
	float static_n = texture(noise_tex, uv * 68.0 + fract(t * 5.8) * vec2(1.0, 0.4)).r;
	col += vec3(0.32, 0.44, 0.02) * pow(static_n, 5.5) * snare * 0.75;

	// Hihat: phosphorescent fine speckling
	float hat_n = texture(noise_tex, uv * 160.0 + fract(t * 11.5)).r;
	col += vec3(0.20, 0.50, 0.02) * pow(hat_n, 9.0) * hihat * 1.4;

	// Onset: expanding membrane-rupture ring
	float rupture_r = length(uv_c) - onset * 0.50;
	float rupture   = exp(-abs(rupture_r) * 16.0) * onset;
	col += mix(vec3(0.62, 0.88, 0.05), vec3(0.56, 0.04, 0.07), fract(t * 0.20))
	     * rupture * 1.15;

	// Beat-phase: slow biological respiration swell
	float phase_swell = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	col *= 1.0 + phase_swell * beat_confidence * 0.22;

	// ── VHS tracking error ────────────────────────────────────────
	float scan_y = floor(uv.y * 38.0) / 38.0;
	float vhs_n  = texture(noise_tex, vec2(uv.x * 3.5 + t * 0.16, scan_y + t * 0.04)).r;
	float vhs    = pow(max(vhs_n - 0.72, 0.0), 1.8) * 5.0;
	col += mix(vec3(0.30, 0.04, 0.04), vec3(0.46, 0.60, 0.03), stain) * vhs * (0.08 + energy * 0.07);

	// ── Film grain ────────────────────────────────────────────────
	float grain = texture(noise_tex, uv * 292.0 + fract(t * 0.113)).r;
	col += (grain - 0.5) * 0.034;

	// ── Vignette — petri dish rim ─────────────────────────────────
	float vd   = length(uv_c) * 1.42;
	float vign = 1.0 - smoothstep(0.38, 1.28, vd);
	col *= mix(0.28, 1.0, vign);

	// ── Bruised void background ───────────────────────────────────
	vec3 void_bg = mix(vec3(0.04, 0.01, 0.07), vec3(0.01, 0.04, 0.01), stain);
	col = max(col, void_bg * (1.0 - vign * 0.55));

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
