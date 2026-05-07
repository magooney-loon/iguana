shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Wavepulse
//  @author:        hisadan (magooney rmx)
//  @website:       x.com/hisadan
//  @description:   3D wireframe wave interference mesh with chromatic split feedback
//
//  Post-processing defaults
//  @exposure:       1.82
//  @tonemap_knee:   0.22
//  @gamma:          1.97
//  @vignette_dark:  0.90
//  @grain_strength: 0.08
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
//
//  Original Processing code by hisadan:
//    float x,y,t,a[]=new float[8]; int i;
//    void setup(){ size(800,800,P3D);
//      for(i=0;i<8;i++) a[i]=400-random(800); }
//    void draw(){
//      background(-1); noFill();
//      camera(700,700,-t*40, 0,0,0, 0,0,-1);
//      for(x=-600;x<600;x+=9)
//        for(y=-600;y<600;y+=9){
//          stroke(0, 3e6/sq(mag(x,y)));
//          beginShape();
//            h(x,y); h(x+9,y); h(x+9,y+9); h(x,y+9);
//          endShape(); }
//      for(i=0;i<4;i++) a[i]+=(a[i+4]*=abs(a[i]+a[i+4]/99)>400?-1:1)/200;
//      t-=.01;
//    }
//    void h(float p,float q){
//      float f=dist(p,q,a[0],a[1]), g=dist(p,q,a[2],a[3]);
//      vertex(p,q, (sin(f/9+t)/f - sin(g/9+t)/g)*3000 );
//    }
//
//  Decompressed algorithm:
//    • 8 float array: a[0..3] = attractor positions (2× xy pairs),
//                     a[4..7] = attractor velocities
//    • Attractors bounce: velocity reverses when position drifts
//      beyond ±400. This creates two wandering wave sources.
//    • Grid mesh (-600..600, step 9) with vertex height:
//        h(x,y) = (sin(d1/9 + t)/d1 - sin(d2/9 + t)/d2) × 3000
//      where d1, d2 = distances from the two attractors.
//      → interference of two expanding circular waves.
//    • Camera at (700, 700, -t×40) looking at origin → oblique
//      flyover view of the ripple surface.
//    • Wireframe quads with alpha = 3e6/mag² → center-bright fade.
//
//  Shader adaptation: ray–plane intersection with parallax correction
//  for 3D perspective, grid-line rendering, normal-based lighting,
//  chromatic split feedback, and full audio reactivity.
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
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.5;

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
	return k > 0.0 ? col / (col + k) : col;
}

// Wave height: interference of two radial sine point sources
// Clamped + raised floor to keep parallax correction well-behaved.
// Processing uses *3000 / max(d, ~0) — fine for mesh vertices but
// diverges in iterative parallax. We use *800 / max(d, 10) + clamp.
float wave_height(vec2 p, vec2 a1, vec2 a2, float t) {
	float d1 = length(p - a1);
	float d2 = length(p - a2);
	float h = (sin(d1 / 9.0 + t) / max(d1, 10.0)
	         - sin(d2 / 9.0 + t) / max(d2, 10.0)) * 800.0;
	return clamp(h, -60.0, 60.0);
}

// Render one wave mesh layer — ray-cast, parallax, grid, lighting, color.
// Each layer uses different camera, attractors, grid step, palette,
// and ground-plane tilt (vec2: x-tilt, y-tilt → sheared plane normal).
vec3 render_wave_layer(vec3 eye, vec2 a1, vec2 a2, float t,
                       vec2 ndc, float aspect, float fov, float grid_step,
                       vec3 col_pos, vec3 col_neg, vec3 col_flat,
                       vec3 light_dir, vec2 tilt) {
	vec3 target = vec3(0.0, 0.0, 0.0);
	vec3 cam_up = vec3(0.0, 0.0, -1.0);

	vec3 fwd   = normalize(target - eye);
	vec3 right_v = normalize(cross(fwd, cam_up));
	vec3 up_v    = normalize(cross(right_v, fwd));

	vec3 ray = normalize(fwd + right_v * ndc.x / fov
	                            + up_v    * ndc.y / fov);

	// Tilted plane: normal = normalize(-tilt.x, -tilt.y, 1)
	// tilt.x shears left/right, tilt.y shears front/back
	vec3 plane_n = normalize(vec3(-tilt.x, -tilt.y, 1.0));

	float denom = dot(plane_n, ray);
	if (denom >= -0.01) return vec3(0.0);

	float t_hit = -dot(plane_n, eye) / denom;
	if (t_hit <= 0.0) return vec3(0.0);

	vec3 p = eye + ray * t_hit;

	// Parallax correction — damped, 4 steps
	for (int i = 0; i < 4; i++) {
		float h = wave_height(p.xy, a1, a2, t);
		if (abs(ray.z) > 0.01) {
			p -= ray / ray.z * (p.z - h) * 0.5;
		}
		p.z = h;
	}

	if (abs(p.x) > 700.0 || abs(p.y) > 700.0) return vec3(0.0);

	// Grid lines
	float gx = abs(fract(p.x / grid_step + 0.5) - 0.5) * 2.0;
	float gy = abs(fract(p.y / grid_step + 0.5) - 0.5) * 2.0;
	float dist_to_eye = length(p - eye);
	float line_w = 0.06 + dist_to_eye / 18000.0;
	float grid_line = 1.0 - smoothstep(0.0, line_w, min(gx, gy));

	// Fade with distance from center
	float fade = min(3.0e6 / max(dot(p.xy, p.xy), 100.0), 1.0);
	fade *= smoothstep(650.0, 600.0, max(abs(p.x), abs(p.y)));

	// Height-based color + radial gradient + position-based hue shift
	float h0 = p.z;
	float dist_from_center = length(p.xy);
	float angle_from_center = atan(p.y, p.x);

	// Hue shift — wider sweep so all colors appear around the grid
	float hue_shift = angle_from_center * 0.3 + dist_from_center * 0.004 + t * 0.12;
	vec3 hue_tint = cos(vec3(0.0, 2.094, 4.189) + hue_shift) * 0.18 + vec3(1.0);

	vec3 wave_col = mix(col_neg, col_pos, smoothstep(-25.0, 25.0, h0));
	wave_col = mix(wave_col, col_flat, exp(-abs(h0) * 0.008));

	// Radial gradient — warm gold center → rose edges (not blue)
	float radial_t = smoothstep(0.0, 500.0, dist_from_center);
	vec3 warm_center = vec3(1.0, 0.9, 0.75);
	vec3 rose_edge   = vec3(0.95, 0.75, 0.85);
	vec3 gradient_tint = mix(warm_center, rose_edge, radial_t);
	wave_col = mix(wave_col, gradient_tint * wave_col * 1.2, 0.3);

	// Apply hue tint
	wave_col *= hue_tint;

	// Surface normal + lighting
	float eps = 3.0;
	float hx = wave_height(p.xy + vec2(eps, 0.0), a1, a2, t);
	float hy = wave_height(p.xy + vec2(0.0, eps), a1, a2, t);
	vec3 normal = normalize(vec3(h0 - hx, h0 - hy, eps));

	float diffuse  = max(dot(normal, light_dir), 0.0);
	float specular = pow(max(dot(reflect(-light_dir, normal),
	                           normalize(eye - p)), 0.0), 12.0);

	vec3 lit = wave_col * (0.4 + diffuse * 0.4 + specular * 0.2);

	return lit * fade * 0.09 + lit * grid_line * fade * 0.07;
}

void fragment() {
	vec2 uv = UV;
	float t = time_val;
	float aspect = rect_size.x / rect_size.y;

	// ══════════════════════════════════════════════════════════════════
	//  1. FEEDBACK — chromatic split
	//
	//  Radial + tangential flow keeps trails swirling and breathing
	//  without any net lateral drift. Per-channel rotation diverges
	//  over hundreds of frames → prismatic rainbow-edged echoes.
	//  Kick/snare burst the rotation; beat_phase drives flow rhythm.
	// ══════════════════════════════════════════════════════════════════

	vec2 center = uv - 0.5;
	center.x *= aspect;

	float dist_c = length(center);
	vec2 radial     = dist_c > 0.001 ? center / dist_c : vec2(0.0, 1.0);
	vec2 tangential = vec2(-radial.y, radial.x);

	float zoom = 0.985 - energy * 0.005 - kick * 0.015 - onset * 0.008;
	vec2 zoomed = center * zoom;

	// Per-channel rotation — kick bursts, snare stutters, beat_phase oscillates
	float beat_rhythm = sin(beat_phase * TAU) * 0.5 + 0.5;
	float ang_r = 0.002 + energy * 0.002 + kick * 0.008 + beat_rhythm * 0.003;
	float ang_g = 0.004 + energy * 0.003 + snare * 0.006 - beat_rhythm * 0.002;
	float ang_b = 0.006 + energy * 0.004 + kick * 0.005 + snare * 0.004;

	// Flow pulses with kick and beat_phase
	float flow = 0.002 * (1.0 + bass * 1.5 + kick * 2.0 + beat_rhythm * 0.5);

	vec2 ruv = rot2(ang_r) * zoomed;
	vec2 guv = rot2(ang_g) * zoomed;
	vec2 buv = rot2(ang_b) * zoomed;

	float flow_ph_r = t * 1.2 + kick * 3.0;
	float flow_ph_g = t * 0.9 + snare * 2.5;
	float flow_ph_b = t * 1.5 + beat_phase * TAU;

	ruv += (radial * sin(dist_c * 8.0 + flow_ph_r)
	      + tangential * cos(dist_c * 5.0 + flow_ph_r * 0.6) * 0.5) * flow;
	guv += (radial * sin(dist_c * 7.0 + flow_ph_g)
	      + tangential * sin(dist_c * 4.5 + flow_ph_g * 0.8) * 0.4) * flow * 0.7;
	buv += (radial * cos(dist_c * 6.0 + flow_ph_b)
	      + tangential * sin(dist_c * 6.0 + flow_ph_b * 0.4) * 0.45) * flow;

	ruv = vec2(ruv.x / aspect, ruv.y) + 0.5;
	guv = vec2(guv.x / aspect, guv.y) + 0.5;
	buv = vec2(buv.x / aspect, buv.y) + 0.5;

	vec2 avg_uv = (ruv + guv + buv) / 3.0;
	vec2 edge_d = min(avg_uv, 1.0 - avg_uv);
	float edge_fade = smoothstep(0.0, 0.05, min(edge_d.x, edge_d.y));

	float decay = mix(0.93, 0.87, energy);

	vec3 trail;
	trail.r = texture(prev_frame, ruv).r * decay * edge_fade;
	trail.g = texture(prev_frame, guv).g * decay * edge_fade;
	trail.b = texture(prev_frame, buv).b * decay * edge_fade;

	// ══════════════════════════════════════════════════════════════════
	//  2. GEOMETRY — Wavepulse 3 interlapping mesh layers
	//
	//  Three wave interference meshes viewed from different oblique
	//  angles. Each layer has its own camera rotation, attractor
	//  phase, grid scale, and color tint. The overlapping grids and
	//  wave patterns create rich visual depth.
	// ══════════════════════════════════════════════════════════════════

	vec2 ndc = (uv - 0.5) * 2.0;
	ndc.x *= aspect;
	vec3 light_dir = normalize(vec3(-1.0, -1.0, 2.0));

	float cam_h = 500.0 + sin(t * 0.03) * 80.0 + energy * 50.0;
	float att_amp = 350.0 * (1.0 + bass * 0.3 + sub_bass * 0.2);

	// ── Layer 1: Main — teal/amber, full scale, bass-driven ──────────
	vec3 eye1 = vec3(700.0, 700.0, cam_h);
	vec2 a1_1 = vec2(sin(t * 0.17)        * att_amp,
	                 cos(t * 0.23 + 1.0)  * att_amp);
	vec2 a2_1 = vec2(sin(t * 0.13 + 2.0)  * att_amp,
	                 cos(t * 0.19 + 3.0)  * att_amp);
	vec3 col1 = render_wave_layer(eye1, a1_1, a2_1, t,
		ndc, aspect, 1.5, 9.0,
		vec3(0.05, 0.85, 0.95),   // peaks: teal
		vec3(0.95, 0.35, 0.08),   // troughs: amber
		vec3(0.35, 0.28, 0.2),    // flat: warm brown
		light_dir,
		vec2(0.0, 0.0));          // no tilt — reference plane

	// ── Layer 2: Rotated 40°, blue/violet, mid-driven ──────────────
	vec2 eye2_xy = rot2(0.70) * vec2(700.0, 700.0);
	vec3 eye2 = vec3(eye2_xy, cam_h * 0.92);
	float att_amp2 = att_amp * (0.8 + mid * 0.3);
	vec2 a1_2 = vec2(sin(t * 0.21 + 4.0)  * att_amp2,
	                 cos(t * 0.19 + 5.0)  * att_amp2);
	vec2 a2_2 = vec2(sin(t * 0.15 + 6.0)  * att_amp2,
	                 cos(t * 0.25 + 7.0)  * att_amp2);
	vec3 col2 = render_wave_layer(eye2, a1_2, a2_2, t * 0.85,
		ndc, aspect, 1.6, 11.0,
		vec3(0.4, 0.5, 0.95),    // peaks: blue-violet
		vec3(0.95, 0.55, 0.25),  // troughs: warm orange
		vec3(0.35, 0.22, 0.15),  // flat: warm umber
		light_dir,
		vec2(0.30, 0.12));       // tilted right + slightly forward

	// ── Layer 3: Rotated -25°, green/magenta, treble-driven ────────
	vec2 eye3_xy = rot2(-0.44) * vec2(650.0, 650.0);
	vec3 eye3 = vec3(eye3_xy, cam_h * 1.08);
	float att_amp3 = att_amp * (0.6 + treble * 0.4);
	vec2 a1_3 = vec2(sin(t * 0.14 + 8.0)  * att_amp3,
	                 cos(t * 0.22 + 9.0)  * att_amp3);
	vec2 a2_3 = vec2(sin(t * 0.18 + 10.0) * att_amp3,
	                 cos(t * 0.16 + 11.0) * att_amp3);
	vec3 col3 = render_wave_layer(eye3, a1_3, a2_3, t * 1.15,
		ndc, aspect, 1.7, 7.0,
		vec3(0.1, 0.9, 0.6),     // peaks: emerald
		vec3(0.9, 0.2, 0.5),     // troughs: magenta
		vec3(0.3, 0.2, 0.18),    // flat: warm sienna
		light_dir,
		vec2(-0.25, 0.10));      // tilted left + slightly forward

	// ── Combine layers ───────────────────────────────────────────────
	// Audio color shift applied to combined result
	vec3 audio_tint = vec3(warmth * 0.12, -warmth * 0.06, -warmth * 0.1);
	vec3 new_col = col1 + col2 * 0.6 * (1.0 + audio_tint) + col3 * 0.45;
	new_col *= 1.0 + energy * 0.25 + kick * 0.15;

	// Kick radial pulse — warm glow from center
	new_col += vec3(0.3, 0.5, 0.7) * kick * exp(-dist_c * 3.5) * 0.1;

	// ══════════════════════════════════════════════════════════════════
	//  3. COMPOSITE — blend trail + new geometry, apply loop_reinhard
	// ══════════════════════════════════════════════════════════════════

	vec3 col = trail + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
