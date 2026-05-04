# Iguana Shader Writing Guide

This guide covers the techniques and patterns used to write audio-reactive visualizer shaders for the Iguana engine. It is written so you can open it, grab what you need, and start coding.

For the full uniform reference and project setup, see `README.md`.

---

## Table of Contents

1. [The Boilerplate](#1-the-boilerplate)
2. [Coordinate Setup](#2-coordinate-setup)
3. [Pillar 1: The Warp (Coordinate Distortion)](#3-pillar-1-the-warp-coordinate-distortion)
4. [Pillar 2: Polar Coordinates and Spirals](#4-pillar-2-polar-coordinates-and-spirals)
5. [Pillar 3: Color Cycling (Cosine Palettes)](#5-pillar-3-color-cycling-cosine-palettes)
6. [Pillar 4: Fractal Iteration (IFS Folding)](#6-pillar-4-fractal-iteration-ifs-folding)
7. [Pillar 5: Raymarching and Glow Accumulation](#7-pillar-5-raymarching-and-glow-accumulation)
8. [Pillar 6: Post-Processing (Tonemap, Grain, Vignette)](#8-pillar-6-post-processing-tonemap-grain-vignette)
9. [Audio-Reactive Patterns](#9-audio-reactive-patterns)
10. [The Checklist](#10-the-checklist)

---

## 1. The Boilerplate

Every Iguana shader starts the same way. Copy this block verbatim — it declares every uniform the engine will feed you.

```glsl
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

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);
```

### Key Points

- `time_val` is your clock. It advances faster when the music is active. Use it for all animation — never `TIME` or frame-counting.
- `UV` is normalized `[0, 1]` from Godot. You almost always want to center it (see next section).
- `rect_size` is the viewport resolution in pixels.
- `noise_tex` is a 512x512 seamless simplex noise texture. Use it for organic variation, particles, and dithering.
- `COLOR` is the output. Write to it in `fragment()`.

---

## 2. Coordinate Setup

The first thing your `fragment()` function should do is build centered, aspect-corrected coordinates. There are two conventions used in this project:

### Option A: Centered UV (0.0 = center, scaled by aspect ratio)

This is the most common pattern. `uv` will be centered at `(0, 0)` with values roughly in `[-0.9, 0.9]` on the short axis and wider on the long axis.

```glsl
void fragment() {
    vec2 uv = UV - 0.5;
    uv.x *= rect_size.x / rect_size.y; // aspect correction
    // uv is now centered at (0,0), aspect-corrected
    // ...
    COLOR = vec4(col, 1.0);
}
```

### Option B: Pixel Coordinates (for shadertoy-style math)

Useful when your math works in pixel space rather than normalized space.

```glsl
void fragment() {
    float min_dim = min(rect_size.x, rect_size.y);
    vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);
    // p is centered at (0,0), the shortest axis spans [-1, 1]
    // ...
    COLOR = vec4(col, 1.0);
}
```

---

## 3. Pillar 1: The Warp (Coordinate Distortion)

MilkDrop-style shaders don't draw shapes — they **distort space** and then sample from the warped coordinates. This creates the liquid, breathing look.

### Sinusoidal Warp

The simplest warp. Shift UVs with sine waves to create a wobble/ripple.

```glsl
vec2 uv_warped = uv;
uv_warped.x += sin(uv.y * 10.0 + time_val) * 0.05 * energy;
uv_warped.y += cos(uv.x * 10.0 + time_val) * 0.05 * energy;
```

### Polar Warp (Ripple from Center)

Distort the radius to create concentric ripples.

```glsl
vec2 center = uv;
float dist = length(center);
float angle = atan(center.y, center.x);

// Ripple the radius
float ripple = sin(dist * 10.0 - time_val * 2.0) * 0.05 * (0.3 + bass * 0.7);
float new_dist = dist + ripple;

// Rebuild cartesian from warped polar
vec2 uv_warped = vec2(cos(angle), sin(angle)) * new_dist;
```

### Domain Repetition + Fold

The workhorse pattern from `afterimage.gdshader`. Repeatedly fold and rotate coordinates to create fractal structures.

```glsl
vec2 p = uv * 1.6; // start scale

for (int i = 0; i < 8; i++) {
    float fi = float(i);

    // Convert to polar, warp angle and radius
    float r = length(p);
    float a = atan(p.y, p.x);
    a += sin(time_val * 0.3 + fi) * 0.12;          // angular wobble
    r *= 1.0 + cos(time_val * 0.2 + fi) * 0.05;    // radial pulse
    p = vec2(cos(a), sin(a)) * r;                   // rebuild cartesian

    // Rotate
    float c = cos(time_val * 0.25 + fi), s = sin(time_val * 0.25 + fi);
    p = mat2(vec2(c, s), vec2(-s, c)) * p;

    // Fold — this creates the fractal symmetry
    p = abs(p) - 0.03;
    p = mat2(vec2(c2, s2), vec2(-s2, c2)) * p;     // post-fold rotation

    // Scale up slightly for the next iteration
    p *= 1.015;
}
```

**Why this works:** The `abs() - offset` fold creates kaleidoscopic symmetry. Combined with rotation and scaling, it produces infinitely detailed fractal patterns — the signature MilkDrop look.

---

## 4. Pillar 2: Polar Coordinates and Spirals

Spirals are a MilkDrop staple. Convert from Cartesian `(x, y)` to polar `(angle, radius)` and use both to drive patterns.

```glsl
vec2 center = uv; // already centered at (0,0) from coordinate setup
float angle = atan(center.y, center.x);
float radius = length(center);

// Spiral pattern: angle creates rotational arms, radius creates radial spacing
float spiral = sin(angle * 5.0 + radius * 10.0 - time_val * 3.0);
float pattern = spiral * 0.5 + 0.5; // remap to [0, 1]
```

### Audio-Reactive Spiral

```glsl
// Arms multiply with bass, spacing scales with energy
float arms = 3.0 + bass * 2.0;
float spacing = 10.0 + energy * 5.0;
float spiral = sin(angle * arms + radius * spacing - time_val * 3.0);

// Modulate radius with kick for a pulsing feel
float pulse_radius = radius * (1.0 + kick * 0.3);
float spiral_pulse = sin(angle * arms + pulse_radius * spacing - time_val * 3.0);
```

### Concentric Rings

Use radius alone to create expanding ring patterns.

```glsl
float ring = sin(radius * 20.0 - time_val * 2.0) * 0.5 + 0.5;
// ring pulses outward over time
```

---

## 5. Pillar 3: Color Cycling (Cosine Palettes)

MilkDrop never uses static colors. It uses **cosine palettes** — a compact math function that produces smooth, cycling gradients. This is the Inigo Quilez technique used in virtually every demoscene shader.

### The Palette Function

```glsl
vec3 palette(float t, vec3 shift) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    return a + b * cos(6.28318 * (c * t + shift));
}
```

- `t` — the input value. Feed it your pattern value + `time_val` for cycling.
- `shift` — a `vec3` that offsets the red, green, and blue channels. This is your "color choice."

### Usage

```glsl
// Cycle colors over time based on pattern position
vec3 color = palette(pattern + time_val * 0.2, vec3(0.263, 0.416, 0.557));
```

### Palette Shift Cheat Sheet

The `shift` vector controls the palette's hue. Here are some starting points:

| Shift `vec3` | Vibe |
|---|---|
| `(0.0, 0.33, 0.67)` | Rainbow — classic full spectrum |
| `(0.263, 0.416, 0.557)` | Cool teal-to-pink (Iq default) |
| `(0.5, 0.5, 0.5)` | Warm amber monochrome |
| `(0.0, 0.1, 0.2)` | Fire — red to orange to yellow |
| `(0.3, 0.2, 0.2)` | Warm sunset tones |
| `(0.2, 0.4, 0.7)` | Ocean — deep blue to cyan |

### Audio-Reactive Palettes

Use the mood uniforms to shift the palette in real time:

```glsl
vec3 shift = vec3(warmth * 0.15, 0.33 + warmth * 0.15, 0.67 + brightness * 0.15);
vec3 color = palette(pattern + time_val * 0.15, shift);
```

- `warmth` shifts toward reds/ambers
- `brightness` shifts toward blues/cyans

---

## 6. Pillar 4: Fractal Iteration (IFS Folding)

The most visually complex Iguana shaders (like `afterimage.gdshader`) build their geometry through **Iterated Function Systems (IFS)**. The core idea: repeatedly fold, rotate, and scale a coordinate space to create self-similar patterns.

### The Building Blocks

```glsl
// 2D rotation helper
mat2 rot2d(float a) {
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));
}
```

### The Pattern: Fold → Rotate → Scale → Repeat

```glsl
vec2 p = uv * 1.6;
float amp = 1.0; // brightness accumulator per layer

for (int i = 0; i < 8; i++) {
    float fi = float(i);
    float phase = time_val * (0.3 + fi * 0.05);

    // 1. Polar warp — organic bending
    float r = length(p);
    float a = atan(p.y, p.x);
    a += sin(phase) * 0.12 * (0.2 + mid * 0.3);
    r *= 1.0 + cos(phase * 0.6) * 0.05 * bass;
    p = vec2(cos(a), sin(a)) * r;

    // 2. Rotate — musical swing
    p = rot2d(p, sin(phase) * 0.25 + beat * 0.12);

    // 3. FOLD — this creates symmetry/fractal structure
    float fold_offset = 0.03 + fi * 0.005;
    p = abs(p) - fold_offset * (1.0 + bass * 0.12);

    // 4. Post-fold rotation — creates the kaleidoscope arms
    float arms = 3.0 + bass * 2.5;
    p = rot2d(p, PI / arms * (0.2 + fi * 0.05));

    // 5. Measure distance to a shape — this creates the visible lines
    float d = length(p) - 0.1 - bass * 0.04;
    d = abs(d) - 0.0025; // turn ring into double line

    // 6. Glow from distance (closer = brighter)
    float glow = 0.003 / (0.001 + abs(d));
    glow *= 0.4 + energy * 0.3;

    // 7. Color this layer
    vec3 shift = vec3(0.1 + fi * 0.02, 0.33 + fi * 0.02, 0.67 + fi * 0.02);
    vec3 layer_col = palette(r * 0.5 - time_val * 0.04 + fi * 0.03, shift);
    layer_col *= 1.0 + beat * 0.3;

    col += layer_col * glow * amp;

    // 8. Scale up for the next iteration
    p *= 1.015 + energy * 0.003;
    amp *= 0.42; // each successive layer is dimmer
}
```

**Why each step matters:**
- **Polar warp** makes the structure breathe and bend organically
- **Rotation** tied to `phase` gives each iteration its own time offset, creating motion
- **`abs() - offset`** (the fold) mirrors the space, creating kaleidoscopic symmetry
- **Post-fold rotation** controls the number of arms/symmetry
- **Distance field + glow** turns the folded geometry into glowing lines
- **`amp *= decay`** makes outer iterations fainter, creating depth

### Smoothing the Glow

Raw `1/dist` glow can be harsh. A smoothstep wrapper tames it:

```glsl
float smootherstep(float x) {
    return x * x * (3.0 - 2.0 * x);
}

// Then:
glow = smootherstep(glow);
```

---

## 7. Pillar 5: Raymarching and Glow Accumulation

For 3D shaders (like `cosmic_abyss.gdshader` and `glitch_gdshader`), raymarching through a signed distance field with glow accumulation produces ethereal volumetric shapes.

### The Pattern

```glsl
void fragment() {
    // Centered pixel coordinates
    float min_dim = min(rect_size.x, rect_size.y);
    vec2 p = (UV * 2.0 - 1.0) * (rect_size / min_dim);

    // Camera — driven by smooth time_val only, never audio
    float t_cam = time_val;
    vec3 ro = vec3(0.0, 0.0, -3.0 * t_cam); // move forward through the scene
    vec3 ray = normalize(vec3(p, 1.5));

    // Glow accumulation
    float acc = 0.0;
    float dist = 0.0;

    for (int i = 0; i < 99; i++) {
        vec3 pos = ro + ray * dist;

        // Distance function — defines the shape of the scene
        float d = map(pos);

        // Clamp minimum step to avoid overstepping
        d = max(abs(d), 0.01);

        // Accumulate glow — exponential falloff from surface
        float glow_strength = 3.0 + energy * 4.0;
        acc += exp(-d * glow_strength);

        dist += d * 0.5; // march forward
    }

    // Turn accumulated glow into a color
    vec3 col = vec3(acc * 0.02);

    // Audio-reactive coloring
    col.r += bass * acc * 0.008;
    col.g += mid * acc * 0.004;
    col.b += treble * acc * 0.002;

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
```

### Camera Rules

**Never drive the camera position or ray direction with audio uniforms.** Audio values jitter frame-to-frame. Camera jitter causes nausea and visual instability. Instead:

- Camera movement → `time_val` only (smooth, continuous)
- Audio reactivity → glow falloff, color, SDF shape modulation

```glsl
// GOOD: smooth camera driven by time only
vec3 ro = vec3(0.0, 0.0, time_val * 4.0);

// BAD: audio jitter on the camera
vec3 ro = vec3(bass * 2.0, 0.0, time_val * 4.0); // will shake violently
```

### SDF Building Blocks

```glsl
// Box SDF
float sd_box(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// 2D rotation matrix
mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(vec2(c, s), vec2(-s, c));
}

// Domain repetition (tile the SDF along axes)
vec3 repeated = mod(pos - cell_size * 0.5, cell_size) - cell_size * 0.5;
```

---

## 8. Pillar 6: Post-Processing (Tonemap, Grain, Vignette)

Every Iguana shader should end with post-processing. This polishes the raw math into something cinematic.

### Reinhard Tonemap

Prevents blown-out whites and compresses HDR values.

```glsl
col = col / (1.0 + col);
```

### Gamma Correction

Godot expects sRGB output. Apply gamma at the end.

```glsl
col = pow(max(col, vec3(0.0)), vec3(0.4545)); // 1/2.2
```

### Film Grain

Adds organic texture. Use the noise texture with high-frequency UV.

```glsl
float grain = texture(noise_tex, UV * 200.0 + fract(time_val * 0.1)).r;
grain = (grain - 0.5) * 0.04 * (1.0 + energy * 0.5);
col += grain;
```

### Vignette

Darkens the edges to focus attention on the center.

```glsl
float vignette = 1.0 - smoothstep(0.3, 1.2, length(UV - 0.5) * 1.8);
vignette = mix(0.6, 1.0, vignette);
col *= vignette;
```

### Mood Brightness

Use the mood uniforms for a final overall brightness pass.

```glsl
col *= 0.38 + brightness * 0.45;     // overall brightness
col.r *= 1.0 + warmth * 0.03;         // subtle warm tint
col.b *= 1.0 + brightness * 0.025;    // subtle cool tint
```

### Full Post-Processing Stack

```glsl
// 1. Tonemap
col = col / (1.0 + col);

// 2. Mood brightness
col *= 0.38 + brightness * 0.45;
col.r *= 1.0 + warmth * 0.03;
col.b *= 1.0 + brightness * 0.025;

// 3. Gamma (before grain, so grain is linear-space)
col = pow(max(col, vec3(0.0)), vec3(0.4545));

// 4. Film grain (after gamma, so it's perceptually uniform)
float grain = texture(noise_tex, UV * 200.0 + fract(time_val * 0.1)).r;
col += (grain - 0.5) * 0.04;

// 5. Vignette
float vignette = 1.0 - smoothstep(0.3, 1.2, length(UV - 0.5) * 1.8);
col *= mix(0.6, 1.0, vignette);

COLOR = vec4(col, 1.0);
```

---

## 9. Audio-Reactive Patterns

### Quick Reference: Which Uniform for What

| Goal | Uniform | Example |
|---|---|---|
| Pulse/breathe with the kick drum | `kick` | `radius *= 1.0 + kick * 0.3;` |
| React to any beat | `beat` | `col *= 1.0 + beat * 0.4;` |
| Flash on transient hits | `onset` | `col += vec3(0.1) * onset;` |
| Snare crack | `snare` | `p.xy *= rot2d(snare * 0.3);` |
| Hihat shimmer | `hihat` | `glow += hihat * 0.15;` |
| Bass body/expansion | `bass` | `scale *= 1.0 + bass * 0.5;` |
| Mid-range detail | `mid` | `fold_angle += mid * 1.0;` |
| Treble sparkle | `treble` | `detail = 10.0 + treble * 5.0;` |
| Overall intensity | `energy` | `brightness = 0.3 + energy * 0.7;` |
| Gate motion to activity | `activity` | `speed *= activity;` |
| Color warmth | `warmth` | `shift.r += warmth * 0.15;` |
| Color coolness | `brightness` | `shift.b += brightness * 0.15;` |
| Sync to beat phase | `beat_phase` | `float pulse = pow(beat_phase, 3.0);` |
| Only sync when confident | `beat_confidence` | `pulse *= beat_confidence;` |

### Beat-Phase Pulse

A smooth brightness swell that peaks on each beat.

```glsl
float phase_pulse = pow(1.0 - abs(fract(beat_phase * 2.0) - 0.5) * 2.0, 3.0);
col *= 1.0 + phase_pulse * beat_confidence * 0.2;
```

### Kick Flash

A brief warm flash on kick hits.

```glsl
col += vec3(0.12, 0.06, 0.02) * kick;
```

### Snare Flash

A brief cool flash on snare hits.

```glsl
col += vec3(0.02, 0.06, 0.12) * snare;
```

### Onset Flash

A neutral white flash on any transient.

```glsl
col += vec3(0.08) * onset;
```

### Audio-Gated Motion

Only allow animation when the music is active.

```glsl
float speed = time_val * (0.3 + activity * 0.7);
```

### Frequency-Band Color Mapping

Map specific bands to specific color channels for a "spectrum visualization" look.

```glsl
col.r += (bass + sub_bass) * 0.35;   // bass = red
col.g += low_mid * 0.2 + mid * 0.15; // mids = green
col.b += (treble + presence) * 0.3;   // treble = blue
```

---

## 10. The Checklist

Before saying a shader is done, verify these:

1. **Is it pulsing?** — At minimum, multiply some parameter by `beat` or `kick`.
2. **Is it swirling?** — Rotate UVs over `time_val` in at least one layer.
3. **Are the colors cycling?** — Use `palette(x + time_val * speed, shift)`, not static colors.
4. **Is the camera smooth?** — Camera uses `time_val` only, never audio uniforms.
5. **Does it tonemap?** — `col = col / (1.0 + col)` before output.
6. **Does it gamma correct?** — `pow(col, vec3(0.4545))` at the end.
7. **Does it have grain?** — Even subtle grain (`0.02` strength) adds life.
8. **Does it have a vignette?** — Darkened edges focus the eye.
9. **Is aspect ratio corrected?** — Always multiply `uv.x` by `rect_size.x / rect_size.y`.
10. **Is it using the right clock?** — Use `time_val`, never `TIME`.

---

## Quick-Start: Minimal Shader

Copy this as a starting point for a new shader.

```glsl
shader_type canvas_item;

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
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define PI 3.14159265359
#define TAU 6.28318530718

vec3 palette(float t, vec3 shift) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    return a + b * cos(TAU * (c * t + shift));
}

void fragment() {
    // Centered, aspect-corrected coordinates
    vec2 uv = UV - 0.5;
    uv.x *= rect_size.x / rect_size.y;

    float t = time_val;
    vec3 col = vec3(0.0);

    // ── Your shader goes here ──────────────────────────────────────

    // Polar coordinates
    float angle = atan(uv.y, uv.x);
    float radius = length(uv);

    // Spiral pattern
    float spiral = sin(angle * 5.0 + radius * 10.0 - t * 3.0 + bass * 3.0);
    spiral = spiral * 0.5 + 0.5;

    // Color with cycling palette
    vec3 shift = vec3(warmth * 0.15, 0.33 + warmth * 0.15, 0.67 + brightness * 0.15);
    col = palette(spiral + t * 0.2, shift);

    // Beat pulse
    col *= 1.0 + beat * 0.3;

    // Kick flash
    col += vec3(0.08) * kick;

    // ── End of your shader ─────────────────────────────────────────

    // Post-processing
    col = col / (1.0 + col);
    col = pow(max(col, vec3(0.0)), vec3(0.4545));

    // Grain
    float grain = texture(noise_tex, UV * 200.0 + fract(t * 0.1)).r;
    col += (grain - 0.5) * 0.03;

    // Vignette
    float vignette = 1.0 - smoothstep(0.3, 1.2, length(UV - 0.5) * 1.8);
    col *= mix(0.6, 1.0, vignette);

    COLOR = vec4(col, 1.0);
}
```
