shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  SUBMERSION — Deep-sea bioluminescent tunnel with organic wall
//  oscillation, neon spiral bands, Inigo Quilez cosine palettes,
//  and iridescent noise-driven morphing
// ═══════════════════════════════════════════════════════════════════════
//
//  Pipeline:
//    1. FEEDBACK  — warp / zoom / rotate prev_frame into trailing echoes
//    2. GEOMETRY  — draw fresh visuals (raymarching, overlays, effects)
//    3. COMPOSITE — trail + new_col, tonemapped with loop_reinhard
//
//  All uniforms below are pushed automatically by visualizer.gd.
//  Per-shader post-processing (exposure, gamma, vignette, grain) runs
//  in a SEPARATE post_process pass — it never feeds back into the loop.
//
//  Writing a new shader?
//    · Copy this file, add your entry to the SHADERS array in visualizer.gd
//    · Implement the three pipeline phases in fragment()
//    · Tweak loop_reinhard to control how bright trails feed back
// ═══════════════════════════════════════════════════════════════════════

// ── Audio engine · auto-driven by AudioAnalyzer ─────────────────────
//
// Frequency bands (0–1, smoothed each frame)
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;  //   20–60 Hz
uniform float bass        : hint_range(0.0, 1.0) = 0.0;  //   60–250 Hz
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;  //  250–800 Hz
uniform float mid         : hint_range(0.0, 1.0) = 0.0;  //  800 Hz–4 kHz
uniform float presence    : hint_range(0.0, 1.0) = 0.0;  //   4–8 kHz
uniform float treble      : hint_range(0.0, 1.0) = 0.0;  //   8–16 kHz
//
// Percussion envelopes (0–1, attack/decay shaped)
uniform float beat        : hint_range(0.0, 1.0) = 0.0;  // general beat pulse
uniform float kick        : hint_range(0.0, 1.0) = 0.0;  // low-frequency kick
uniform float snare       : hint_range(0.0, 1.0) = 0.0;  // mid-frequency snare
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;  // high-frequency hat
//
// Spectral flux / onset (0–1, rate of change per band)
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;  // bass band flux
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;  // mid band flux
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;  // treble band flux
uniform float onset       : hint_range(0.0, 1.0) = 0.0;  // weighted onset strength
//
// Global descriptors (0–1 unless noted)
uniform float energy      : hint_range(0.0, 1.0) = 0.0;  // RMS loudness
uniform float activity    : hint_range(0.0, 1.0) = 0.0;  // spectral activity
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;  // perceptual loudness
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;  // bass ↔ treble ratio
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;  // treble energy ratio
uniform float density     : hint_range(0.0, 1.0) = 0.0;  // spectral flatness
//
// Timing
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;  // 0–1 position in beat
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;  // tracker confidence
uniform float bpm             = 120.0;                          // estimated BPM
uniform float time_val        = 0.0;                             // elapsed seconds

// ── Feedback loop ───────────────────────────────────────────────────
// Previous frame's output — sample this (warped/zoomed/rotated) to
// create MilkDrop-style trails, tunnels, and infinite zoom effects.
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader tuning · configurable in Settings UI ─────────────────
// Reinhard tonemapping applied INSIDE the feedback loop.
// Higher = more compression (dimmer highlights, more detail retained).
// 0 = bypass.  Default is set per-shader in visualizer.gd.
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.69;

// ── Utility · auto-provided by visualizer.gd ────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);  // viewport resolution in pixels

// ── Constants ───────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Shader-specific helpers ─────────────────────────────────────────
mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Cosine palette — Inigo Quilez
vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	return a + b * cos(TAU * (c * t + d));
}

// Smooth minimum — organic shape merging
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Iridescent plasma field ───────────────────────────────────────────
// Six overlapping sine planes in 2D — fills the tunnel interior
float plasma_field(vec2 c, float t) {
	float r = length(c);
	float a = atan(c.y, c.x);
	float p = 0.0;
	p += sin(c.x * 8.0  + t * 1.15 + sin(c.y * 4.0  + t * 0.7)  * 2.1);
	p += sin(c.y * 7.0  - t * 0.85 + cos(c.x * 5.0  + t * 0.75) * 1.8);
	p += sin(r * 12.0   - t * 2.4  + a * 3.0);
	p += cos(r * 7.5    + t * 1.9  - a * 2.0);
	p += sin((c.x + c.y) * 6.0 + t * 0.55 + sin(r * 4.2) * 1.9);
	p += cos((c.x - c.y) * 5.0 - t * 0.65 + cos(a * 2.0 + t * 0.3) * 1.5);
	return p * (1.0 / 6.0);
}

// ── Volumetric ray fan ────────────────────────────────────────────────
// Rotating light beams radiating from the tunnel center
float vol_rays(vec2 c, float t) {
	float a = atan(c.y, c.x);
	float r = length(c);

	// Three superimposed fans at different rotational frequencies
	float f1 = pow(max(sin(a * 8.0  + t * 0.75 + beat_phase * TAU) * 0.5 + 0.5, 0.0), 4.0);
	float f2 = pow(max(sin(a * 5.0  - t * 0.55 + beat_phase * TAU * 0.6) * 0.5 + 0.5, 0.0), 3.0);
	float f3 = pow(max(cos(a * 12.0 + t * 1.1 ) * 0.5 + 0.5, 0.0), 7.0);

	float combined = f1 * 0.5 + f2 * 0.35 + f3 * 0.15;
	float falloff = exp(-r * (2.8 - energy * 1.4 - sub_bass * 0.6));
	return combined * falloff * (0.6 + energy * 0.9 + sub_bass * 0.5);
}

// ── Propagating mercury rings ─────────────────────────────────────────
// Beat-driven concentric pulse rings with specular highlight
float mercury_rings(vec2 c, float t) {
	float r = length(c);
	float a = atan(c.y, c.x);
	float rings = 0.0;

	// Primary beat-sync pulse — wraps around with fract
	float p1 = fract(t * 0.38 + beat_phase * 0.45);
	rings += exp(-abs(r - p1 * 0.52) * 42.0) * (0.35 + beat * 0.65);

	// Slower secondary ring
	float p2 = fract(t * 0.22 + 0.5);
	rings += exp(-abs(r - p2 * 0.52) * 28.0) * (0.2 + energy * 0.55);

	// Kick shockwave — sharp, fast, bright
	float kp = fract(t * 1.15 + kick * 0.25);
	rings += exp(-abs(r - kp * 0.42) * 65.0) * kick * 0.8;

	// Surface ripple — makes rings look liquid
	float ripple = sin(r * 85.0 - t * 13.0 + a * 2.0) * 0.5 + 0.5;
	rings *= 0.65 + ripple * 0.35;

	// Mercury specular highlight — facing-angle bloom
	float spec = pow(max(cos(a + t * 0.38) * 0.5 + 0.5, 0.0), 9.0);
	rings += spec * exp(-r * 6.5) * (0.12 + energy * 0.18);

	return rings;
}

void fragment() {
	vec2 uv  = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center — all warp math uses this
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ══════════════════════════════════════════════════════════════
	// PART 1 — FEEDBACK WARP & ACCUMULATION
	// ══════════════════════════════════════════════════════════════

	// ── Zoom (compounds each frame into infinite tunnel) ──────────
	// onset = hard inward rush; sub_bass = kick-breath
	float zoom = 0.976 - sub_bass * 0.018 - onset * 0.014;
	vec2 warped = center * zoom;

	// ── Rotation (compounds into spiral) ─────────────────────────
	float rot_speed = 0.0062 + energy * 0.009 + beat * 0.004;
	warped = rot2(rot_speed) * warped;

	// ── Multi-layer per-pixel warp field ─────────────────────────
	// All terms use Cartesian warped.xy or scalar rc — never atan().
	// atan() has a branch cut at the negative x-axis that compounds
	// into a hard seam every frame through the feedback loop.
	float rc = length(warped);

	// Slow large-scale gravitational wave
	vec2 w1 = vec2(
		sin(warped.y *  6.0 + t * 0.88 + warped.x * 5.0) * 0.019,
		cos(warped.x *  5.0 + t * 0.72 + rc * 3.2)       * 0.019
	);
	// Medium ripple
	vec2 w2 = vec2(
		sin(warped.y * 11.0 - t * 1.55 + rc * 8.5)       * 0.009,
		cos(warped.x *  9.0 + t * 1.25 + warped.y * 7.0) * 0.009
	);
	// Fast turbulence
	vec2 w3 = vec2(
		sin(warped.x * 4.0 + rc * 19.0 - t * 3.1) * 0.005,
		cos(warped.y * 6.0 - rc * 14.0 + t * 2.7) * 0.005
	);
	// Noise-based soft-body bulge
	vec2 nuv = warped * 0.38 + t * 0.038;
	float nx = texture(noise_tex, nuv).r          * 2.0 - 1.0;
	float ny = texture(noise_tex, nuv + vec2(0.5)).r * 2.0 - 1.0;
	vec2 wn = vec2(nx, ny) * 0.015;

	// Audio amplitude on warp — more bass/energy → wilder displacement
	float wamp = 1.0 + bass * 2.8 + energy * 2.1 + beat * 1.6;

	vec2 total_warp = (w1 + w2 + w3 + wn) * wamp;

	// Reconstruct feedback sample UV
	vec2 fb_center = warped + total_warp;
	fb_center.x /= aspect;
	vec2 fb_uv = fb_center + 0.5;

	// Soft edge fade — smoothstep prevents the border clamp artifact
	vec2 ed = min(fb_uv, 1.0 - fb_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(ed.x, ed.y));

	// Chromatic aberration on the feedback sample (CRT lens fringing)
	float ca = 0.0038 + brightness * 0.003 + onset * 0.009;
	vec2 ca_off = (fb_uv - 0.5) * ca;
	float fb_r = texture(prev_frame, fb_uv + ca_off * 1.6).r;
	float fb_g = texture(prev_frame, fb_uv              ).g;
	float fb_b = texture(prev_frame, fb_uv - ca_off * 1.6).b;
	vec3 trail = vec3(fb_r, fb_g, fb_b);

	// Decay — louder music = slower fade = longer echo trails
	trail *= (0.905 + energy * 0.038) * edge_fade;

	// ══════════════════════════════════════════════════════════════
	// PART 2 — NEW GEOMETRY (drawn fresh each frame)
	// ══════════════════════════════════════════════════════════════

	float r = length(center);
	float a = atan(center.y, center.x);

	vec3 new_col = vec3(0.0);

	// ── Neon color palette ────────────────────────────────────────
	// Cycles through deep midnight blues, radioactive greens, hot pinks
	float hue = beat_phase * TAU + t * 0.11;

	// Warmth < 0.5 → radioactive green / cyan; warmth > 0.5 → hot pink / magenta
	vec3 cold_neon = vec3(0.05 + mid * 0.1, 0.88 + treble * 0.12, 0.25 + mid * 0.2);
	vec3 hot_neon  = vec3(1.0,  0.04 + mid * 0.08, 0.38 + presence * 0.22);
	vec3 deep_blue = vec3(0.02, 0.06, 0.55 + brightness * 0.2);

	// Three-way blend: cool ↔ hot driven by warmth, with beat-phase rotation
	float blend_t = warmth + sin(hue) * 0.3;
	vec3 base_neon = mix(cold_neon, hot_neon, clamp(blend_t, 0.0, 1.0));
	base_neon = mix(deep_blue, base_neon, 0.65 + energy * 0.2);

	// Inigo Quilez cosine palette layered over base for subtle shimmer
	vec3 pal_col = palette(hue / TAU,
		vec3(0.5), vec3(0.5), vec3(1.0),
		vec3(warmth * 0.15, 0.33 + brightness * 0.1, 0.67)
	);
	vec3 neon_col = mix(base_neon, pal_col, 0.35);

	// Frequency tinting
	neon_col.r += (bass + sub_bass) * 0.38;
	neon_col.g += low_mid * 0.18 + mid * 0.14;
	neon_col.b += (treble + presence) * 0.32;

	// ── Soft-body tunnel wall ─────────────────────────────────────
	// The wall radius oscillates with overlapping sines — living organism
	float wall_r = 0.315
	             + 0.065 * sin(a * 4.0  + t * 2.05)
	             + 0.038 * sin(a * 7.0  - t * 1.45 + bass * 2.2)
	             + 0.022 * cos(a * 11.0 + t * 3.3)
	             + 0.016 * sin(a * 18.0 - t * 5.1)
	             + sub_bass * 0.058
	             + kick    * 0.038 * sin(t * 9.5);

	// Multiple wall layers — nested glow shells (sum ≈ 1.2 max, not 2.0)
	float wall_g0 = exp(-pow(r - wall_r,         2.0) * 200.0);
	float wall_g1 = exp(-pow(r - wall_r * 1.28,  2.0) * 120.0) * 0.35;
	float wall_g2 = exp(-pow(r - wall_r * 1.65,  2.0) *  70.0) * 0.18;
	float wall_g3 = exp(-pow(r - wall_r * 2.10,  2.0) *  40.0) * 0.09;
	float outer_glow = wall_g0 + wall_g1 + wall_g2 + wall_g3;

	// ── Primary spiral bands — integer arm count (no atan2 seam) ─
	float arms_a = floor(5.0 + bass * 3.0);
	float sp_a = sin(a * arms_a + r * 14.5 - t * 2.75 + beat_phase * TAU);
	sp_a = pow(max(sp_a * 0.5 + 0.5, 0.0), 2.5);

	float arms_b = arms_a + 2.0;  // always integer because arms_a is integer
	float sp_b = sin(a * arms_b  - r * 9.5  + t * 1.65 + beat_phase * TAU * 0.5);
	sp_b = pow(max(sp_b * 0.5 + 0.5, 0.0), 2.0);

	float band_I = sp_a * sp_b * outer_glow;
	new_col += neon_col * band_I * (0.28 + energy * 0.38 + beat * 0.15);

	// ── Secondary counter-rotating arm set ───────────────────────
	float arms_c = floor(3.0 + presence * 2.0);
	float sp_c = sin(a * arms_c * 2.0 + r * 22.0 + t * 3.4 + beat_phase * TAU * 0.3);
	sp_c = pow(max(sp_c * 0.5 + 0.5, 0.0), 3.5);
	vec3 comp_col = mix(vec3(0.0, 0.35, 1.0), vec3(0.55, 0.0, 1.0), beat_phase);
	new_col += comp_col * sp_c * outer_glow * (0.18 + treble * 0.25);

	// ── Inner tunnel texture — fine oscillating strands ──────────
	float strand = sin(a * 16.0 + r * 40.0 - t * 6.0)
	             * sin(a *  9.0 - r * 28.0 + t * 4.2 + beat_phase * TAU);
	strand = pow(max(strand * 0.5 + 0.5, 0.0), 4.0);
	float inner_mask = smoothstep(wall_r + 0.02, wall_r - 0.08, r);
	new_col += neon_col * strand * inner_mask * (0.06 + density * 0.10);

	// ── Volumetric center rays ────────────────────────────────────
	float vol = vol_rays(center, t);
	vec3 core_col = mix(vec3(0.8, 0.95, 1.0), neon_col, clamp(r * 2.8, 0.0, 1.0));
	new_col += core_col * vol * (0.03 + energy * 0.05);

	// Convergence point — kept dim, tunnel depth comes from the feedback zoom
	float core_r = exp(-r * (16.0 - energy * 8.5 - sub_bass * 4.5));
	new_col += vec3(1.0, 0.93, 0.82) * core_r * (0.04 + beat * 0.02);

	// ── Iridescent plasma fill (tunnel interior) ──────────────────
	float pl = plasma_field(center * 1.95, t) * 0.5 + 0.5;
	float tunnel_interior = smoothstep(wall_r + 0.03, wall_r - 0.07, r);
	vec3 plasma_col = palette(pl + hue / TAU * 0.3,
		vec3(0.5), vec3(0.5), vec3(1.0),
		vec3(0.1 + warmth * 0.2, 0.35, 0.7 - brightness * 0.2)
	);
	new_col += plasma_col * pl * pl * tunnel_interior * (0.015 + energy * 0.03);

	// ── Mercury propagating rings ─────────────────────────────────
	float rings = mercury_rings(center, t);
	vec3 merc_col = mix(vec3(0.68, 0.84, 1.0), neon_col, 0.3 + energy * 0.45);
	new_col += merc_col * rings * (0.12 + beat * 0.18);
	new_col += vec3(1.0, 1.0, 1.0) * pow(rings, 2.0) * 0.06;

	// ── Noise-driven wall iridescence ─────────────────────────────
	float n_wall  = texture(noise_tex, vec2(a / TAU + t * 0.012, r * 2.0 + t * 0.008)).r;
	float n_wall2 = texture(noise_tex, vec2(a / TAU * 0.7 - t * 0.009, r * 3.5 - t * 0.014) + 0.37).r;
	float irides = abs(n_wall - n_wall2);
	new_col += neon_col * irides * wall_g0 * (0.15 + energy * 0.25) * 0.2;

	// ── Percussion accents ────────────────────────────────────────
	new_col += vec3(0.88, 0.78, 1.0) * exp(-r * 3.8) * snare * 0.18;

	float hat_r = pow(max(sin(a * 28.0 + t * 5.5) * 0.5 + 0.5, 0.0), 7.0);
	new_col += vec3(0.75, 1.0, 0.88) * hat_r * exp(-r * 2.5) * hihat * 0.08;

	new_col += neon_col * wall_g0 * kick * 0.22;

	float onset_rr = 0.08 + onset * 0.38;
	float onset_ring = exp(-abs(r - onset_rr) * 28.0) * onset;
	new_col += mix(vec3(1.0, 0.28, 0.6), vec3(0.15, 1.0, 0.55), warmth) * onset_ring * 0.45;

	// ── Beat-phase swell ──────────────────────────────────────────
	float phase_p = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
	new_col *= 1.0 + phase_p * beat_confidence * 0.18;

	// ══════════════════════════════════════════════════════════════
	// PART 3 — COMPOSITE + POST-PROCESSING
	// ══════════════════════════════════════════════════════════════

	vec3 col = trail + new_col;
	col = col / (1.0 + col * loop_reinhard);

	COLOR = vec4(col, 1.0);
}
