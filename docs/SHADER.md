# Writing Visualizer Shaders

Iguana auto-discovers any `.gdshader` file dropped into `res://shaders/`. No code changes needed — just drop the file and relaunch.

---

## Minimal Shader

```glsl
shader_type canvas_item;

// @name:        My Shader
// @author:      Your Name
// @description: One line description
// @website:     optional-url.com
// @exposure:       1.42
// @tonemap_knee:   0.0
// @gamma:          2.0
// @vignette_dark:  0.30
// @grain_strength: 0.01
// @loop_reinhard:  0.0

uniform sampler2D prev_frame : hint_default_black;
uniform vec2  rect_size;
uniform float time_val;
uniform int   frame;

// Audio
uniform float beat;
uniform float energy;
uniform float bass;
uniform float sub_bass;
uniform float low_mid;
uniform float mid;
uniform float presence;
uniform float treble;

void fragment() {
    vec2 uv = UV;
    vec3 col = vec3(0.0);
    COLOR = vec4(col, 1.0);
}
```

---

## @meta Tags

The engine reads tags from the first 40 lines of the file. All are optional except `@name`.

| Tag | Purpose |
|---|---|
| `@name` | Display name in the shader dropdown |
| `@author` | Shown in Settings → Shaders → Shader Info |
| `@description` | Shown in Settings (scrolls if too long) |
| `@website` | Clickable link in Settings |
| `@exposure` | Default post-process exposure (0.1 – 3.0) |
| `@tonemap_knee` | Default Reinhard knee for the post layer |
| `@gamma` | Default output gamma |
| `@vignette_dark` | Default vignette shadow strength |
| `@grain_strength` | Default post-layer film grain |
| `@loop_reinhard` | Default Reinhard inside the feedback loop |

All six numeric tags are overridden per-user in the Settings window and saved to `iguana_settings.cfg`. The defaults in the file are the first-run values.

---

## Available Uniforms

### Geometry

| Uniform | Type | Description |
|---|---|---|
| `prev_frame` | `sampler2D` | Last frame's output — the feedback texture |
| `rect_size` | `vec2` | Viewport size in pixels |
| `time_val` | `float` | Elapsed seconds |
| `frame` | `int` | Frame counter (absolute, from engine start) |

### Full Audio Set

| Uniform | Range | Description |
|---|---|---|
| `sub_bass` | 0–1 | 20–60 Hz |
| `bass` | 0–1 | 60–250 Hz |
| `low_mid` | 0–1 | 250–800 Hz |
| `mid` | 0–1 | 800 Hz–4 kHz |
| `presence` | 0–1 | 4–8 kHz |
| `treble` | 0–1 | 8–16 kHz |
| `kick_envelope` | 0–1 | Kick drum transient envelope |
| `snare_envelope` | 0–1 | Snare transient envelope |
| `hihat_envelope` | 0–1 | Hi-hat transient envelope |
| `beat_envelope` | 0–1 | General beat envelope |
| `beat` | 0–1 | Beat pulse (alias, same as beat_envelope) |
| `beat_confidence` | 0–1 | How confident the engine is a beat occurred |
| `beat_phase` | 0–1 | Position within the current beat cycle |
| `flux_bass` | 0–1 | Spectral flux in the bass band |
| `flux_mid` | 0–1 | Spectral flux in the mid band |
| `flux_treble` | 0–1 | Spectral flux in the treble band |
| `energy` | 0–1 | Overall RMS energy |
| `activity` | 0–1 | Short-term activity level |
| `onset` | 0–1 | Transient onset strength |
| `loudness` | 0–1 | Perceived loudness (LUFS-like) |
| `warmth` | 0–1 | Low-frequency spectral weight |
| `brightness` | 0–1 | High-frequency spectral weight |
| `density` | 0–1 | Spectral density / fullness |
| `bpm` | 0–300 | Estimated BPM |

### Post-Process (feedback-internal)

| Uniform | Range | Description |
|---|---|---|
| `loop_reinhard` | 0–3 | Reinhard compression inside the loop. 0 = off. ~0.9 = moderate. Controls trail brightness accumulation. |

---

## The Feedback Loop

`prev_frame` holds last frame's completed output. Sample it with a slight zoom, rotation, and warp to get trails, tunnels, and spirals — the MilkDrop aesthetic.

```glsl
// ── 1. FEEDBACK ────────────────────────────────────────────────────
vec2 center = uv - 0.5;
center.x *= rect_size.x / rect_size.y;           // aspect-correct

center *= 0.98 - sub_bass * 0.02;                // zoom (tunnel)

float rot = 0.007 + energy * 0.008;
float c = cos(rot), s = sin(rot);
center = mat2(vec2(c, s), vec2(-s, c)) * center; // spiral rotation

vec2 feedback_uv = center;
feedback_uv.x /= rect_size.x / rect_size.y;
feedback_uv += 0.5;

vec2 warp = vec2(
    sin(center.y * 10.0 + time_val * 1.4) * 0.015,
    cos(center.x *  8.0 + time_val * 1.1) * 0.015
);
warp *= 1.0 + bass * 2.5 + energy * 1.5;

vec2 sample_uv = feedback_uv + warp;
float edge_fade = smoothstep(0.0, 0.04,
    min(min(sample_uv.x, 1.0 - sample_uv.x),
        min(sample_uv.y, 1.0 - sample_uv.y)));

vec3 trail = texture(prev_frame, sample_uv).rgb;
trail *= (0.92 + energy * 0.05) * edge_fade;

// ── 2. GEOMETRY ────────────────────────────────────────────────────
vec3 new_col = /* ... */;

// ── 3. FEEDBACK TONEMAP (inside the loop) ──────────────────────────
vec3 col = trail + new_col;
float k = loop_reinhard;
if (k > 0.0) col = col / (col + k) * (1.0 + k);

COLOR = vec4(col, 1.0);
```

See [MILKDROP.md](MILKDROP.md) for the full breakdown of why each step matters and how to tune it.

---

## Per-Shader Post-Processing Defaults

The six `@` tags in the file header set the default values that appear in Settings → Shaders → Post-Processing when this shader is first selected. They are saved per-shader in `iguana_settings.cfg` after the user adjusts them.

`loop_reinhard` is the only one applied inside the shader itself. The other five (`exposure`, `tonemap_knee`, `gamma`, `vignette_dark`, `grain_strength`) are applied by the external `post_process.gdshader` layer after the feedback texture is complete — so they cannot compound or trail.

Good starting points:

```glsl
// @exposure:       1.42   — mild boost
// @tonemap_knee:   0.0    — no external Reinhard (use loop_reinhard instead)
// @gamma:          2.0    — standard
// @vignette_dark:  0.30   — moderate edge shadow
// @grain_strength: 0.01   — barely perceptible grain
// @loop_reinhard:  0.9    — moderate trail clamp inside the loop
```

---

## Common Patterns

### Cosine Palette

```glsl
vec3 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

// Audio-driven hue shift
float hue = time_val * 0.1 + beat * 0.3;
vec3 col = palette(hue,
    vec3(0.5, 0.5, 0.5),
    vec3(0.5, 0.5, 0.5),
    vec3(1.0, 1.0, 1.0),
    vec3(0.0, 0.33, 0.67));
```

### Beat Flash

```glsl
// Adds a white flash on kick, fades out over ~10 frames
float flash = kick_envelope * 0.4;
col += flash;
```

### Polar Coordinates

```glsl
vec2 p = uv - 0.5;
float angle = atan(p.y, p.x);          // -PI to PI
float radius = length(p);
float bands = sin(angle * 8.0 + time_val * 2.0 + bass * 3.0);
float ring = smoothstep(0.02, 0.0, abs(radius - 0.3 - energy * 0.1));
```

### Onset Spike

```glsl
// Single-frame zoom jolt on a hard transient
float jolt = onset * 0.04;
center *= 0.98 - sub_bass * 0.02 - jolt;
```

---

## Checklist Before Publishing

- [ ] `@name` tag present (required for auto-discovery)
- [ ] `prev_frame` sampled with zoom + warp — shaders that ignore `prev_frame` have no visual memory
- [ ] Per-pixel emission kept low (see [MILKDROP.md §6](MILKDROP.md#6-feedback-brightness--equilibrium-formula)) to avoid trail blow-out
- [ ] `loop_reinhard` used as the brightness safety valve
- [ ] Post-process defaults set to sensible values for your visual
- [ ] Tested at multiple volumes (quiet → loud) to verify audio-reactivity feels proportional
