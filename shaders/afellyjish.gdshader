shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          aFellyJish
//  @author:        magooney
//  @website:       github.com/magooney-loon
//  @description:   Parametric jellyfish spiral with polar vortex feedback
//
//  Post-processing defaults
//  @exposure:       1.5
//  @tonemap_knee:   0.0
//  @gamma:          2.2
//  @vignette_dark:  0.99
//  @grain_strength: 0.008
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
// ── Audio · all values 0–1, pushed every frame by AudioAnalyzer ─────
//
// Frequency bands (smoothed)
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;
//
// Percussion envelopes (attack/decay shaped)
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;
//
// Spectral flux / onset (rate of change per band)
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;
//
// Global descriptors
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;
//
// Beat tracking
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float beat_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float kick_threshold  : hint_range(0.0, 1.0) = 0.3;
uniform float snare_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float hihat_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;
uniform int   frame           = 0;

// ── Feedback loop ────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.6;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Spectral rows (32 bands, 0–1 peak per row) ───────────────────────
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
uniform float peak_15 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_16 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_17 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_18 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_19 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_20 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_21 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_22 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_23 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_24 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_25 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_26 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_27 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_28 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_29 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_30 : hint_range(0.0, 1.0) = 0.0;
uniform float peak_31 : hint_range(0.0, 1.0) = 0.0;

// ── Constants ────────────────────────────────────────────────────────
#define TAU 6.28318530718
#define PI  3.14159265359

// ── Helpers ──────────────────────────────────────────────────────────

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv = UV;
	float aspect = rect_size.x / rect_size.y;
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);  // centered, aspect-corrected
	float t = time_val;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — polar vortex with concentric ripples
	//
	//  Operates in polar (r, θ) space instead of cartesian:
	//
	//    • Vortex rotation ∝ radius — inner trails barely drift,
	//      outer trails spin into fast spirals. Creates a natural
	//      whirlpool rather than the flat uniform rotation.
	//
	//    • Sine-modulated radial zoom — adds concentric breathing
	//      rings that expand/contract, not a flat tunnel shrink.
	//
	//    • Outward-pulsing ripple displacement along the radial
	//      direction — organic jellyfish pulsation on the trails.
	//
	//  Together these create a whirlpool/mandala trail pattern that
	//  compounds differently from the standard zoom+rotate+warp.
	// ══════════════════════════════════════════════════════════════════

	vec2 center = uv - 0.5;
	center.x *= aspect;

	// Polar decomposition
	float r = length(center);
	float theta = atan(center.y, center.x);

	// Vortex — rotation scales with distance from center
	// Bass adds heavy low-frequency swirl, energy sustains it
	float vortex = r * (0.035 + energy * 0.025 + bass * 0.02);
	theta += vortex;

	// Radial zoom with breathing modulation
	// The sine term creates concentric pulsing rings
	float breathe = sin(r * 14.0 - t * 1.8) * 0.006;
	float zoom = 0.978 - sub_bass * 0.008 - onset * 0.005 - breathe;
	r *= zoom;

	// Concentric ripple — outward-pulsing radial displacement
	// Snare adds transient ripple bursts
	float ripple_amp = 0.003 * (1.0 + bass * 2.5 + snare * 1.5);
	float ripple = sin(r * 25.0 - t * 3.5) * ripple_amp;
	r += ripple;

	// Reconstruct cartesian, undo aspect correction
	vec2 fb_center = vec2(cos(theta), sin(theta)) * max(r, 0.0);
	vec2 fb_uv = fb_center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;

	// Edge fade — clamp to texture bounds
	vec2 edge_d = min(fb_uv, 1.0 - fb_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, fb_uv).rgb;

	// Decay — louder music = shorter trails (fresh geometry dominates)
	float decay = mix(0.91, 0.85, energy);
	trail *= decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — FellyJish parametric jellyfish
	//
	//  140–220 samples along the parametric curve, each contributing
	//  a Gaussian glow. The curve has:
	//    • Two interleaved spirals (m=0, m=9) rotating at different
	//      speeds due to the angular offset in c = d²/9 - t/16 + m
	//    • A bifurcation at k²<19: inner points evolve fast with
	//      sin(t*3 + d*4), outer points drift slowly with sin(d/2+4)
	//    • Audio warps the cosine frequency and expands the pattern
	// ══════════════════════════════════════════════════════════════════

	// Time scale — energy makes the jellyfish writhe faster
	float t_speed = t * (1.0 + energy * 0.25);

	// Map original 400×400 canvas coordinates to UV space
	float scale = 1.0 / 400.0;

	// Kick expands the jellyfish momentarily
	float size_pulse = 1.0 + kick * 0.1;

	// Dynamic point count — more energy reveals more structure
	int num_pts = 140 + int(energy * 80.0);  // 140–220

	// Gaussian sharpness — treble tightens glow, bass softens it
	float glow_sharp = 600.0 + treble * 400.0;

	// Cosine palette — bioluminescent jellyfish colors
	// Warmth → gold/crimson shift, brightness → cyan/teal shift
	vec3 pal_c = vec3(1.0, 0.7 + warmth * 0.3, 0.4 + brightness * 0.4);
	vec3 pal_d = vec3(0.0, 0.15, 0.2 + activity * 0.15);

	// Accumulate glow from parametric samples
	vec3 glow = vec3(0.0);

	for (int idx = 0; idx < 220; idx++) {
		if (idx >= num_pts) break;

		float fi = float(idx);
		// Map index to original parameter range (0 – 20000)
		float i_param = fi * 20000.0 / float(num_pts);

		// ── Parametric computation (faithful to original) ────────

		// Two interleaved spiral offsets
		float m = mod(fi, 2.0) * 9.0;

		// Bass subtly warps the cosine frequency — structure breathes
		float k = 9.0 * cos(i_param / (81.0 - bass * 8.0));
		float e_val = i_param / 765.0 - 13.0;
		float d = length(vec2(k, e_val)) / 4.0;

		// q with bifurcation — k²<19 splits into two dynamical regimes
		float q = 79.0 - 2.0 * sin(k * 3.0);
		float sin_arg = (k * k < 19.0) ? t_speed * 3.0 + d * 4.0
		                               : d / 2.0 + 4.0;
		q += sin(sin_arg) / 2.0 * k
		     * (9.0 + 5.0 * sin(d * d - e_val / 6.0 - t_speed + m));

		// Angle parameter — per-spiral offset drives interleaving
		float c = d * d / 9.0 - t_speed / 16.0 + m;

		// Point position in UV space
		vec2 pt = vec2(q * sin(c), (q + 50.0) * cos(c)) * scale * size_pulse;

		// Gaussian glow falloff — soft luminous halos per point
		float dist_sq = dot(p - pt, p - pt);
		float falloff = exp(-dist_sq * glow_sharp);

		// Color from palette — index-varying for rainbow banding
		vec3 pt_col = 0.5 + 0.5 * cos(TAU * (pal_c * (fi / 220.0 + t * 0.03) + pal_d));

		glow += falloff * pt_col;
	}

	// Central radial glow — soft breathing pulse at the core
	float r_p = length(p);
	float core_glow = exp(-r_p * r_p * 10.0) * beat * 0.08;
	glow += vec3(0.3, 0.5, 0.9) * core_glow;

	// ══════════════════════════════════════════════════════════════════
	//  2b. PLANKTON — drifting bioluminescent particles
	//
	//  Tiny scattered dots that fill the outer screen, like
	//  bioluminescent plankton drifting around the jellyfish.
	//  • Multiple noise layers at different scales for depth
	//  • High threshold picks out discrete bright specks
	//  • Outer mask keeps them away from the central jellyfish
	//  • Gentle drift + twinkle + audio reactivity
	// ══════════════════════════════════════════════════════════════════

	float plankton = 0.0;

	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);

		// Different scale per layer — finer dots in front, coarser behind
		float layer_scale = 4.0 + fl * 3.0;

		// Gentle drifting — each layer moves at its own speed
		float drift = 0.015 + fl * 0.008;
		vec2 drift_uv = uv * layer_scale
		               + vec2(t * drift, t * drift * 0.6 + fl * 1.3);

		float n = texture(noise_tex, drift_uv).r;

		// Threshold to isolate discrete bright specks
		float thresh = 0.72 - energy * 0.04 - bass * 0.02;
		float dot = smoothstep(thresh, thresh + 0.04, n);

		// Twinkle — phase offset per layer and noise position
		float twinkle = 0.65 + 0.35 * sin(t * (1.8 + fl * 0.5) + n * 25.0);

		plankton += dot * twinkle;
	}

	// Fade near center — plankton lives in the outer regions
	float outer_mask = smoothstep(0.2, 0.55, r_p);

	// Brightness — visible but not overpowering, scaled by audio
	float plankton_brightness = plankton * outer_mask
	                           * (0.06 + energy * 0.04 + treble * 0.02);

	// Color — cool blue-green bioluminescence with warmth tint
	vec3 plankton_col = plankton_brightness
	                  * vec3(0.3 + warmth * 0.15,
	                         0.55 + brightness * 0.1,
	                         0.85 + activity * 0.1);

	// ══════════════════════════════════════════════════════════════════
	//  2c. EDGE AURA — flowing glow hugging the screen border
	//
	//  Lives exclusively in the vignette zone (outermost rim).
	//  • Distance-from-edge metric confines it to the perimeter
	//  • Noise texture adds organic flowing variation
	//  • Pulses gently with the beat, swells with bass/energy
	// ══════════════════════════════════════════════════════════════════

	// Distance from nearest screen edge (0 at border, ~0.5 at center)
	float rim_d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

	// Two noise samples at different scales for organic edge flow
	float edge_n1 = texture(noise_tex, uv * 2.5 + vec2(t * 0.04, t * 0.02)).r;
	float edge_n2 = texture(noise_tex, uv * 5.0 - vec2(t * 0.06, t * 0.03)).r;
	float edge_flow = edge_n1 * 0.6 + edge_n2 * 0.4;

	// Mask: only the outermost ~10–12% of the screen
	float edge_mask = smoothstep(0.12, 0.01, rim_d);

	// Breathing pulse — slow ambient + beat transient
	float edge_pulse = 1.0 + beat * 0.4 + bass * 0.2;

	// Intensity — visible rim glow, boosted by audio
	float edge_intensity = edge_mask * edge_flow * edge_pulse
	                     * (0.08 + energy * 0.06);

	// Color — warm-cool blend that shifts with audio mood
	vec3 edge_col = edge_intensity
	              * mix(vec3(0.2, 0.35, 0.7),   // cool blue
	                    vec3(0.5, 0.25, 0.6),    // warm violet
	                    warmth)
	              * (1.0 + presence * 0.3);

	// Tanh tonemap — clamps per-frame output, then scale low for
	// safe feedback equilibrium.  With decay ~0.88:
	//   equilibrium = 0.10 / 0.12 ≈ 0.83  (stays ≤ 1.0)
	vec3 new_col = tanh(glow * 0.5) * 0.10 + plankton_col + edge_col;

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + new geometry, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════

	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
