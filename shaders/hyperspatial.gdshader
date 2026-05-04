shader_type canvas_item;

// ── Audio engine uniforms ────────────────────────────────────────────
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
uniform float bpm         = 120.0;
uniform float time_val    = 0.0;

uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D noise_tex  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define TAU 6.28318530718
#define PI  3.14159265359

// ── Utility ──────────────────────────────────────────────────────────
mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Stroboscopic time: snaps to discrete steps instead of flowing smoothly.
// The step size varies with energy, creating jittery variable-framerate feel.
float strobo_time(float t, float e) {
	float step_size = mix(0.08, 0.015, e);   // silence = big jumps, energy = finer
	return floor(t / step_size) * step_size;
}

// Quantized angle — snaps rotation to discrete increments
float strobo_angle(float a, float steps) {
	float s = max(steps, 4.0);
	return floor(a / TAU * s) / s * TAU;
}

// Integer hash for deterministic pseudo-random per-frame jitter
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 hash12(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Thin line SDF — returns 1.0 on the line, 0.0 elsewhere
// d = distance from point to line segment [a, b]
float line_segment(vec2 p, vec2 a, vec2 b, float thickness) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * h);
	return exp(-d * thickness);
}

// Wireframe circle SDF
float wire_circle(vec2 p, float radius, float thickness) {
	return exp(-abs(length(p) - radius) * thickness);
}

// Wireframe triangle SDF (equilateral, centered at origin)
float wire_triangle(vec2 p, float radius, float thickness) {
	float d = 1e9;
	float a0 = 0.0;
	for (int i = 0; i < 3; i++) {
		float a1 = a0 + TAU / 3.0;
		vec2 v0 = vec2(cos(a0), sin(a0)) * radius;
		vec2 v1 = vec2(cos(a1), sin(a1)) * radius;
		d = min(d, abs(length(p - v0) * cos(atan(p.y - v0.y, p.x - v0.x) - atan(v1.y - v0.y, v1.x - v0.x))));
		// Simpler: distance to each edge
		float d_line = line_segment(p, v0, v1, thickness);
		if (d_line > exp(-d * thickness))
			d = -log(d_line) / thickness;
		a0 = a1;
	}
	return exp(-d * thickness);
}

// Wireframe hexagon SDF
float wire_hexagon(vec2 p, float radius, float thickness) {
	float d = 1e9;
	for (int i = 0; i < 6; i++) {
		float a0 = float(i) * TAU / 6.0;
		float a1 = float(i + 1) * TAU / 6.0;
		vec2 v0 = vec2(cos(a0), sin(a0)) * radius;
		vec2 v1 = vec2(cos(a1), sin(a1)) * radius;
		d = min(d, -log(line_segment(p, v0, v1, thickness)) / thickness);
	}
	return exp(-d * thickness);
}

// Wireframe square SDF
float wire_square(vec2 p, float half_size, float thickness) {
	float d = 1e9;
	vec2 v[4];
	v[0] = vec2(-half_size, -half_size);
	v[1] = vec2( half_size, -half_size);
	v[2] = vec2( half_size,  half_size);
	v[3] = vec2(-half_size,  half_size);
	for (int i = 0; i < 4; i++) {
		int j = (i + 1) % 4;
		d = min(d, -log(line_segment(p, v[i], v[j], thickness)) / thickness);
	}
	return exp(-d * thickness);
}

// Wireframe polygon (N sides)
float wire_polygon(vec2 p, float radius, float thickness, float sides) {
	float d = 1e9;
	int n = int(sides);
	for (int i = 0; i < n; i++) {
		float a0 = float(i) * TAU / sides;
		float a1 = float(i + 1) * TAU / sides;
		vec2 v0 = vec2(cos(a0), sin(a0)) * radius;
		vec2 v1 = vec2(cos(a1), sin(a1)) * radius;
		d = min(d, -log(line_segment(p, v0, v1, thickness)) / thickness);
	}
	return exp(-d * thickness);
}

// Grid of wireframe shapes — creates Moiré when overlapping grids rotate differently
float grid_lines(vec2 p, float spacing, float thickness) {
	vec2 q = mod(p, spacing) - spacing * 0.5;
	// Vertical and horizontal lines
	float lx = exp(-abs(q.x) * thickness);
	float ly = exp(-abs(q.y) * thickness);
	return max(lx, ly);
}

// Rotating grid — returns the grid value at point p with grid rotated by angle
float rotated_grid(vec2 p, float spacing, float angle, float thickness) {
	p *= rot2(-angle);
	return grid_lines(p, spacing, thickness);
}

void fragment() {
	vec2 uv = UV;
	float aspect = rect_size.x / rect_size.y;
	vec2 uv_c = uv - 0.5;
	uv_c.x *= aspect;

	// ── Stroboscopic time ───────────────────────────────────────────
	float t = strobo_time(time_val, energy);

	// Per-frame jitter: hash by integer frame count (using time as proxy)
	float frame_hash = hash11(floor(time_val * 30.0));
	float jitter_x = (hash12(frame_hash * 137.0).x - 0.5) * 0.004 * (1.0 + kick * 3.0);
	float jitter_y = (hash12(frame_hash * 137.0).y - 0.5) * 0.004 * (1. + kick * 3.0);
	uv_c += vec2(jitter_x, jitter_y);

	// ── Feedback loop ───────────────────────────────────────────────
	vec2 fb_center = uv - 0.5;
	fb_center.x *= aspect;

	// Zoom: tight spiral tunnel, sub_bass breathes it
	float zoom = 0.975 - sub_bass * 0.015;
	fb_center *= zoom;

	// Rotation: energy drives spiral tightness, quantized for jittery feel
	float rot_rate = 0.006 + energy * 0.008;
	float rot_angle = strobo_angle(t * rot_rate * 60.0, floor(12.0 + energy * 24.0));
	fb_center *= rot2(rot_angle);

	// Per-pixel warp: very subtle, only when active
	vec2 warp = vec2(
		sin(fb_center.y * 12.0 + t * 2.0) * 0.008,
		cos(fb_center.x * 10.0 + t * 1.7) * 0.008
	);
	warp *= activity;

	vec2 fb_uv = fb_center;
	fb_uv.x /= aspect;
	fb_uv += 0.5;
	vec2 sample_uv = fb_uv + warp;

	// Edge fade
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	float decay = 0.90 + energy * 0.06;
	trail *= decay * edge_fade;

	// ── Bass inversion: on strong kick, invert feedback brightness ──
	float invert_trigger = smoothstep(0.6, 0.9, kick);
	trail = mix(trail, vec3(1.0) - trail, invert_trigger * 0.3);

	// ── Geometry emission ───────────────────────────────────────────
	vec3 col = vec3(0.0);

	// Hyperspace white
	vec3 white = vec3(1.0);
	// Neon accent colors
	vec3 magenta = vec3(1.0, 0.0, 0.6);
	vec3 teal    = vec3(0.0, 0.95, 0.85);

	// Line thickness: razor sharp, slightly modulated
	float thick = 120.0 + energy * 60.0;

	// ── 1. OVERLAPPING ROTATING GRIDS (Moiré interference) ──────────
	// Multiple grids at different angles create intense Moiré patterns
	float moire = 0.0;
	float grid_spacing = 0.12 + bass * 0.04;

	// Grid layer 1: slow rotation
	float g1_angle = t * 0.15;
	moire += rotated_grid(uv_c, grid_spacing, g1_angle, thick * 0.8);

	// Grid layer 2: counter-rotation
	float g2_angle = -t * 0.12 + 0.7;
	moire += rotated_grid(uv_c, grid_spacing * 1.05, g2_angle, thick * 0.8);

	// Grid layer 3: faster, slightly different spacing — the interference is wild
	float g3_angle = t * 0.22 + PI * 0.33;
	float g3_spacing = grid_spacing * 0.97;
	moire += rotated_grid(uv_c * rot2(t * 0.05), g3_spacing, g3_angle, thick * 0.6);

	// Modulate: grids flicker in and out
	float grid_vis = 0.5 + 0.5 * sin(t * 3.0);
	grid_vis *= 0.7 + activity * 0.3;
	moire *= grid_vis;

	// ── 2. CONCENTRIC CIRCLES (non-Euclidean breathing) ─────────────
	float circles = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		// Phase offset per circle
		float phase = fi * 1.3;
		// Breathing radius: discrete steps, audio-reactive
		float breathe = strobo_time(t * 0.5 + phase, 0.3 + energy * 0.5);
		float r = 0.06 + fi * 0.06 + sin(breathe * 2.0) * 0.03 + sub_bass * 0.04;

		// Slight offset per circle for organic feel
		vec2 offset = vec2(
			sin(t * 0.3 + fi * 2.1) * 0.01,
			cos(t * 0.25 + fi * 1.7) * 0.01
		) * energy;

		circles += wire_circle(uv_c + offset, r, thick * 1.2);
	}
	circles *= 0.6 + 0.4 * sin(t * 4.0 + 1.0);  // flicker

	// ── 3. FLOATING TRIANGLES (folding through themselves) ──────────
	float triangles = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float tri_angle = strobo_angle(t * 0.3 + fi * PI * 0.5, floor(8.0 + kick * 8.0));
		vec2 tri_offset = vec2(
			sin(fi * 1.7 + t * 0.15) * 0.12,
			cos(fi * 2.3 + t * 0.12) * 0.08
		) * (0.5 + energy * 0.5);
		float tri_r = 0.08 + fi * 0.04 + bass * 0.03;

		vec2 p_tri = uv_c - tri_offset;
		p_tri *= rot2(tri_angle);

		// "Morph": triangle suddenly becomes hexagon on beat
		float morph_trigger = smoothstep(0.5, 0.8, beat) * beat_confidence;
		float sides = mix(3.0, 6.0, morph_trigger);
		triangles += wire_polygon(p_tri, tri_r, thick * 1.0, sides);
	}
	triangles *= 0.5 + 0.5 * sin(t * 5.0 + 2.0);

	// ── 4. FLOATING SQUARES (glitch in the matrix) ─────────────────
	float squares = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float sq_angle = strobo_angle(t * 0.2 + fi * TAU / 3.0, floor(6.0 + snare * 12.0));
		vec2 sq_offset = vec2(
			cos(fi * 2.0 + t * 0.1) * 0.15,
			sin(fi * 1.5 + t * 0.13) * 0.1
		) * (0.5 + energy * 0.5);
		float sq_size = 0.06 + fi * 0.03 + low_mid * 0.02;

		vec2 p_sq = uv_c - sq_offset;
		p_sq *= rot2(sq_angle);
		squares += wire_square(p_sq, sq_size, thick * 0.9);
	}
	squares *= 0.5 + 0.5 * cos(t * 3.5 + 0.5);

	// ── 5. DIAGONAL CROSS-HATCH (extra Moiré layer) ────────────────
	float cross = 0.0;
	vec2 p_cross = uv_c;
	// Diagonal lines at 45° and 135°
	float diag_spacing = 0.1 + treble * 0.04;
	p_cross *= rot2(PI * 0.25 + t * 0.08);
	float cx = exp(-abs(mod(p_cross.x + 10.0, diag_spacing) - diag_spacing * 0.5) * thick * 0.7);
	p_cross *= rot2(PI * 0.5);
	float cy = exp(-abs(mod(p_cross.x + 10.0, diag_spacing) - diag_spacing * 0.5) * thick * 0.7);
	cross = max(cx, cy);
	cross *= 0.4 + 0.3 * sin(t * 2.7);
	cross *= 0.5 + activity * 0.5;

	// ── 6. INTERSECTION NODES (blinking points at crossings) ────────
	float nodes = 0.0;
	{
		// Detect approximate grid intersections from grid layer 1
		vec2 p_g = uv_c * rot2(-t * 0.15);
		float gs = grid_spacing;
		vec2 nearest = round(p_g / gs) * gs;
		float d_node = length(p_g - nearest);
		float node_r = 0.003 + presence * 0.004;
		// Blink: only show some nodes, randomly
		float node_hash = hash11(dot(nearest, vec2(127.1, 311.7)) + floor(t * 8.0));
		float blink = step(0.6, node_hash);
		nodes = exp(-d_node * d_node / (node_r * node_r)) * blink;
	}

	// ── COMPOSITE: layer it all ─────────────────────────────────────
	float line_intensity = 0.035 + energy * 0.02;

	// Grids: pure white (this is where Moiré lives)
	col += white * moire * line_intensity * 0.8;

	// Circles: white with slight teal tint
	col += mix(white, teal, 0.3) * circles * line_intensity;

	// Triangles: white, magenta accent on beat
	vec3 tri_col = mix(white, magenta, beat * 0.6);
	col += tri_col * triangles * line_intensity;

	// Squares: pure white
	col += white * squares * line_intensity;

	// Cross-hatch: white
	col += white * cross * line_intensity * 0.5;

	// Nodes: neon accent, blinking
	vec3 node_col = mix(teal, magenta, sin(t * 7.0) * 0.5 + 0.5);
	col += node_col * nodes * (0.12 + presence * 0.15);

	// ── Percussion strikes ──────────────────────────────────────────
	// Kick: geometry inversion flash + magenta burst
	col += magenta * kick * 0.06;

	// Snare: teal snap
	col += teal * snare * 0.05;

	// Hihat: white flicker
	col += white * hihat * 0.03;

	// Onset: white flash that makes everything visible for one frame
	col += white * onset * 0.08;

	// ── Beat-phase pulse: geometry "breathes" with the beat ─────────
	float phase_pulse = pow(1.0 - abs(fract(beat_phase) - 0.5) * 2.0, 4.0);
	col *= 1.0 + phase_pulse * beat_confidence * 0.25;

	// ── "Camera snap" on kick: offset everything briefly ────────────
	// This is already handled by the jitter above, but we add an extra
	// frame-brightness inverter for the "teleportation" feel
	float snap_flash = smoothstep(0.7, 1.0, kick) * beat_confidence;
	col = mix(col, vec3(max(col.r, max(col.g, col.b))) * white, snap_flash * 0.15);

	// ── FINAL COMPOSITE with feedback ───────────────────────────────
	vec3 final_col = trail + col;

	// Subtle vignette to frame the void
	float vig = 1.0 - smoothstep(0.4, 1.1, length(uv - 0.5) * 1.6);
	final_col *= mix(0.7, 1.0, vig);

	// Very mild tonemap to keep whites from clipping harshly while
	// maintaining the high-contrast aesthetic
	final_col = final_col / (1.0 + final_col * 0.3);

	COLOR = vec4(clamp(final_col, 0.0, 1.0), 1.0);
}
