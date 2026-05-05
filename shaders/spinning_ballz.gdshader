shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════════════
//  @name:          Spinning Ballz
//  @author:        TinyTexel (magooney rmx)
//  @website:       shadertoy.com/view/Xljcz1
//  @description:   Fibonacci-mapped pulsing sphere of spinning circles
//
//  Post-processing defaults — tune these to taste, then leave them.
//  @exposure:       1.3
//  @tonemap_knee:   0.0
//  @gamma:          2.0
//  @vignette_dark:  0.25
//  @grain_strength: 0.008
//  @loop_reinhard:  0.00
// ═══════════════════════════════════════════════════════════════════════
//
//  Original: "oOoOoOoOoOoOoOoOoOoOoOoOoOoOoOo" by TinyTexel
//  Analytical AA for disks + Spherical Fibonacci Mapping.
//  Adapted to the Iguana MilkDrop-style feedback pipeline with
//  audio-reactive camera, pulsing, and color shifting.
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

// ── Feedback loop ────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Per-shader Reinhard · tunable in Settings UI ────────────────────
uniform float loop_reinhard : hint_range(0.0, 3.0) = 0.9;

// ── Utility · auto-provided ──────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2  rect_size = vec2(1600.0, 900.0);

// ── Constants ────────────────────────────────────────────────────────
#define TAU  6.28318530718
#define PI   3.14159265359
#define PHI  1.6180339887498948482045868343656

#define SPOT_COUNT_MUL 12.0

// ── Helpers ──────────────────────────────────────────────────────────

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec3 reinhard(vec3 col, float k) {
	return k > 0.0 ? col / (col + k) * (1.0 + k) : col;
}

float Pow2(float x) { return x * x; }
float Pow3(float x) { return x * x * x; }
float Pow4(float x) { return Pow2(Pow2(x)); }

float SqrLen(float v) { return v * v; }
float SqrLen(vec2 v)  { return dot(v, v); }
float SqrLen(vec3 v)  { return dot(v, v); }

// ── Ray–Sphere intersection ──────────────────────────────────────────
// Returns vec3: x = hit flag (>0 hit, <0 behind, 0 miss), y = t_near, z = t_far

vec3 IntersectRaySphere(vec3 rp, vec3 rd, vec3 sp, float sr2) {
	rp -= sp;
	float a = dot(rd, rd);
	float b = 2.0 * dot(rp, rd);
	float c = dot(rp, rp) - sr2;
	float D = b * b - 4.0 * a * c;
	if (D < 0.0) return vec3(0.0);
	float sqrtD = sqrt(D);
	vec2 t = (-b + vec2(-sqrtD, sqrtD)) / a * 0.5;
	if (c < 0.0) t.xy = t.yx;
	float hit = t.x > 0.0 || c < 0.0 ? 1.0 : -1.0;
	return vec3(hit, t);
}

// ── Spherical Fibonacci Mapping ──────────────────────────────────────
// Keinert / Innmann / Sänger / Stamminger (2015)

float madfrac(float a, float b) { return a * b - floor(a * b); }
vec2  madfrac(vec2 a, float b)  { return a * b - floor(a * b); }

float sf2id(vec3 p, float n) {
	float phi_val = min(atan(p.y, p.x), PI);
	float cosTheta = p.z;

	float k = max(2.0, floor(log(n * PI * sqrt(5.0) * (1.0 - cosTheta * cosTheta)) / log(PHI * PHI)));
	float Fk = pow(PHI, k) / sqrt(5.0);

	vec2 F = vec2(round(Fk), round(Fk * PHI));

	vec2 ka = -2.0 * F / n;
	vec2 kb = 2.0 * PI * madfrac(F + 1.0, PHI - 1.0) - 2.0 * PI * (PHI - 1.0);
	mat2 iB = mat2(vec2(ka.y, -ka.x), vec2(-kb.y, kb.x)) / (ka.y * kb.x - ka.x * kb.y);

	vec2 c = floor(iB * vec2(phi_val, cosTheta - (1.0 - 1.0 / n)));
	float d = 8.0;
	float j = 0.0;
	for (int si = 0; si < 4; si++) {
		vec2 uv_s = vec2(float(si - 2 * (si / 2)), float(si / 2));
		float ct = dot(ka, uv_s + c) + (1.0 - 1.0 / n);
		ct = clamp(ct, -1.0, 1.0) * 2.0 - ct;
		float i = floor(n * 0.5 - ct * n * 0.5);
		float phi3 = 2.0 * PI * madfrac(i, PHI - 1.0);
		ct = 1.0 - (2.0 * i + 1.0) / n;
		float sinT = sqrt(max(1.0 - ct * ct, 0.0));
		vec3 q = vec3(cos(phi3) * sinT, sin(phi3) * sinT, ct);
		float sd = dot(q - p, q - p);
		if (sd < d) {
			d = sd;
			j = i;
		}
	}
	return j;
}

vec3 id2sf(float i, float n) {
	float phi_val = 2.0 * PI * madfrac(i, PHI);
	float zi = 1.0 - (2.0 * i + 1.0) / n;
	float sinT = sqrt(max(1.0 - zi * zi, 0.0));
	return vec3(cos(phi_val) * sinT, sin(phi_val) * sinT, zi);
}

// ── Disk / sphere projection helpers ─────────────────────────────────

float ProjSphereArea(float rdz, vec3 p, float rr) {
	float zz = p.z * p.z;
	float ll = dot(p, p);
	float denom = rr - ll;
	if (abs(denom) < 0.0001) return 0.0;
	return PI * rdz * rdz * rr * inversesqrt(max(abs(Pow3(rr - zz) / denom), 0.0001));
}

vec4 ProjDisk(vec3 rd, vec3 p, vec3 n, float rr) {
	vec3 np0 = n * p.xyz;
	vec3 np1 = n * p.yzx;
	vec3 np2 = n * p.zxy;

	mat3 k_mat = mat3(
		vec3( np0.y + np0.z,  np2.x,          np1.x),
		vec3(-np2.y,           np1.y,         -np0.x - np0.z),
		vec3(-np1.z,          -np0.x - np0.y,  np2.z)
	);

	vec3 u = k_mat * rd;
	vec3 k = u * k_mat;

	float nrd = dot(n, rd);
	float nrd_rr = nrd * rr;

	float v = dot(u, u) - nrd * nrd_rr;
	vec3 g = (k - n * nrd_rr) * 2.0;

	return vec4(g.xy, 0.0, v);
}

float SphX0(float d, float rr0, float rr1) { return 0.5 * (d + (rr0 - rr1) / d); }

// ── Scene evaluation ─────────────────────────────────────────────────

vec3 EvalScene(vec3 cpos, mat3 cam_mat, float focalLen, vec2 uv0) {
	// Background tinted by energy
	vec3 cBG = 0.014 * vec3(0.9, 1.0, 1.2) * (1.0 + energy * 0.4);

	vec2 uv2 = uv0 - rect_size * 0.5;
	vec3 rdir0 = vec3(uv2, focalLen);
	rdir0 /= focalLen;                       // unnormalized view-space ray

	vec3 rdir = normalize(cam_mat * rdir0);   // world-space ray

	// Ray vs unit sphere
	vec3 hit_info = IntersectRaySphere(cpos, rdir, vec3(0.0), 1.0);
	if (hit_info.x <= 0.0) return cBG;

	vec3 pf = cpos + rdir * hit_info.y;       // front intersection point

	// Fibonacci spot lookup
	const float s = SPOT_COUNT_MUL;
	const float n = 1024.0 * s;

	float id = sf2id(pf.xzy, n);
	vec3 p2 = id2sf(id, n).xzy;

	float u_val = id / n;

	// Pulsing phase — kick adds transient burst
	float arg = (-u_val * 615.5 * 2.0 * s) + time_val * 1.0 + kick * 3.0;
	float rra = sin(arg);
	rra = mix(abs(rra), Pow2(rra), 0.75);

	float rr = 0.0025 / s * rra;

	vec3 n2 = normalize(p2);
	const float maskS = 0.5;

	if (SqrLen(pf - p2) > rr) return cBG;

	float d = length(p2);
	float x0 = SphX0(d, 1.0, rr);
	vec3 d0c = n2 * x0;
	float d0rr = 1.0 - x0 * x0;

	vec3 dp_c = (d0c - cpos) * cam_mat;
	vec3 dn_c = n2 * cam_mat;

	// Analytical disk coverage (outer)
	vec4 r = ProjDisk(rdir0, dp_c, dn_c, d0rr);
	float rsq = dot(r.xy, r.xy);
	float cmask = rsq > 0.0 ? clamp(-r.w * inversesqrt(rsq) * focalLen * maskS, 0.0, 1.0) : 0.0;

	// Inner mask — the colored disk center
	float cmask2 = 0.0;
	{
		vec3 d1c = n2 * (x0 - 0.005);
		vec4 r2 = ProjDisk(rdir0, (d1c - cpos) * cam_mat, n2 * cam_mat, (1.0 - x0 * x0) * rra);
		float rsq2 = dot(r2.xy, r2.xy);
		cmask2 = rsq2 > 0.0 ? clamp(-r2.w * inversesqrt(rsq2) * focalLen * maskS, 0.0, 1.0) : 0.0;
	}

	// Area-based coverage guard
	float A = ProjSphereArea(rdir0.z, dp_c, d0rr);
	A *= focalLen * focalLen;
	float NdV = abs(dot(dn_c, normalize(dp_c)));
	A *= NdV;
	A *= NdV;
	cmask *= clamp((A - 2.0) * 0.125, 0.0, 1.0);

	// Audio-reactive color palette
	vec3 cB = mix(vec3(0.1, 0.4, 1.0), vec3(0.1, 0.75, 0.8), brightness * 0.4);
	vec3 cR = mix(vec3(1.0, 0.02, 0.2), vec3(1.0, 0.5, 0.05), warmth * 0.4);

	return mix(cBG, mix(cR, vec3(0.0), cmask2), cmask);
}

// ── Fragment ─────────────────────────────────────────────────────────

void fragment() {
	vec2 uv  = UV;
	float t  = time_val;
	float aspect = rect_size.x / rect_size.y;

	// Aspect-corrected center
	vec2 center = uv - 0.5;
	center.x *= aspect;

	// ── 1. FEEDBACK ──────────────────────────────────────────────────

	// Zoom — compounding inward tunnel, onset = hard rush
	float zoom = 0.994 - energy * 0.004 - onset * 0.006;
	vec2 warped = center * zoom;

	// Rotation — compounding spiral
	warped = rot2(0.003 + bass * 0.005) * warped;

	// Per-pixel warp field
	float rc = length(warped);
	vec2 warp = vec2(
		sin(warped.y * 7.0 + t * 1.1) * 0.005,
		cos(warped.x * 5.0 + t * 0.9) * 0.005
	);
	warp *= 1.0 + bass * 2.0 + energy * 1.0;
	warped += warp;

	// Convert back to UV space for sampling
	vec2 sample_uv = warped;
	sample_uv.x /= aspect;
	sample_uv += 0.5;

	// Edge fade to prevent hard borders
	vec2 edge_d = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= edge_fade;

	// ── 2. GEOMETRY — spinning ballz ─────────────────────────────────

	// Camera orbit with audio reactivity
	vec2 ang = vec2(0.0, -PI * 0.3);
	ang.x += t * (0.15 + energy * 0.12);
	ang.y += sin(t * 0.2) * 0.15 * (1.0 + bass * 0.5);

	float fov = PI * 0.5;

	float sinPhi   = sin(ang.x);
	float cosPhi   = cos(ang.x);
	float sinTheta = sin(ang.y);
	float cosTheta = cos(ang.y);

	vec3 front = vec3(cosPhi * cosTheta, sinTheta, sinPhi * cosTheta);
	vec3 right = vec3(-sinPhi, 0.0, cosPhi);
	vec3 up    = cross(right, front);

	float focalLen = rect_size.x * 0.5;   // 90° FOV → focalLen = half-width
	mat3 cam_mat = mat3(right, up, front);

	// Camera distance — sub_bass pushes closer (sphere swells)
	vec3 cpos = -cam_mat[2] * exp2(-0.3 - sub_bass * 0.15);
	cpos.y += 0.75;

	vec2 uv0 = uv * rect_size;             // pixel coordinates
	vec3 new_col = EvalScene(cpos, cam_mat, focalLen, uv0);

	// ── 3. COMPOSITE ─────────────────────────────────────────────────

	float decay = 0.92 + energy * 0.04;    // louder → longer trails
	vec3 col = trail * decay + new_col;
	col = reinhard(col, loop_reinhard);

	COLOR = vec4(col, 1.0);
}
