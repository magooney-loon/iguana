# What Makes MilkDrop Feel Like MilkDrop

A technical breakdown of MilkDrop's rendering pipeline, why each part matters, and where Iguana currently falls short. This document exists so we always know what we're aiming for and what's missing.

---

## The Short Answer

MilkDrop looks the way it does because of **one thing**: every frame is built on top of the previous frame. The previous frame is sampled with a slight zoom, a slight rotation, and a fade, then new geometry is drawn on top. This creates trails, tunnels, spirals, and the sense that the visuals have *weight* and *memory*. Without this feedback loop, you cannot get the MilkDrop look. Period.

Everything else — the cosine palettes, the polar warps, the IFS folding — is decoration on top of the feedback loop. The feedback is the foundation.

---

## 1. The MilkDrop Rendering Pipeline

MilkDrop renders in a very specific order every single frame:

```
┌──────────────────────────────────────────────┐
│  PREVIOUS FRAME TEXTURE (from last frame)    │
│                                              │
│  1. WARP: Displace every pixel by a         │
│     per-pixel offset vector (the "warp mesh")│
│                                              │
│  2. ZOOM + ROTATE: Sample the warped        │
│     texture at UV * zoom_factor, rotated     │
│     by a small angle                        │
│                                              │
│  3. DECAY: Multiply all colors by ~0.90-0.98│
│     (this is what creates the trails)        │
│                                              │
│  4. COMPOSITE: Draw new geometry on top      │
│     (shapes, text, particles, whatever)      │
│                                              │
│  5. OUTPUT: This becomes next frame's input  │
└──────────────────────────────────────────────┘
```

The output of step 5 is fed back into step 1 on the next frame. This is a **feedback loop**. The loop runs every frame, compounding small distortions over time.

### Why each step matters

**Warp (per-pixel displacement):** This is what makes the trails curve, spiral, and flow rather than just shrinking to the center. MilkDrop computes a full-screen displacement field using sine/cosine functions driven by time and audio. Each pixel is shifted by a different amount, creating organic flowing motion that compounds over frames. Without audio, the warp still runs on time alone, producing a slow ambient drift.

**Zoom:** Sampling the previous frame at `UV * 0.97` (slightly zoomed in) creates the classic infinite tunnel. The 3% zoom compounds: after 100 frames, the content has been magnified ~20x. Old geometry appears to fly toward the viewer and vanish. This is why MilkDrop has that "falling into the screen" look.

**Rotation:** A tiny per-frame rotation (like 0.005-0.02 radians) makes the tunnel spiral instead of just converging to a point. Combined with the zoom, it creates the iconic spiraling tunnel.

**Decay:** Multiplying the old frame by 0.90-0.98 fades it out gradually. A decay of 0.95 means a pixel's brightness halves roughly every 14 frames (~0.5 seconds at 30fps). This controls trail length. Lower decay = shorter trails. Higher decay = longer, more persistent trails.

**Composite:** New bright geometry is drawn on top of the faded, zoomed, rotated old frame. Because the old frame is faded but still visible, the new geometry appears to "leave behind" a trail that spirals inward and fades out.

### The mathematical compounding

Here's the key insight: a single frame's warp is subtle (maybe 2-5 pixels of displacement). But after 60 frames, those displacements have compounded into dramatic flowing structures. The math is cumulative:

```
Frame 1:  new geometry drawn
Frame 2:  old geometry zoomed 3%, rotated 0.01 rad, faded 5%. New geometry drawn.
Frame 3:  frames 1+2 zoomed 3%, rotated 0.01 rad, faded 5%. New geometry drawn.
...
Frame N:  everything from frames 1 through N-1, each progressively more zoomed,
          rotated, and faded, with N layers of warp distortion compounding.
```

This compounding is why MilkDrop looks "alive" in a way that single-frame shaders cannot replicate. No matter how clever your IFS folding or raymarching is, if you regenerate from scratch every frame, the result will always feel static in comparison.

---

## 2. The Warp Mesh (Per-Pixel Displacement)

This deserves its own section because it's the most misunderstood part of MilkDrop.

MilkDrop's warp is NOT just "warp the UV coordinates of new geometry." It's "warp WHERE YOU SAMPLE the previous frame." These are fundamentally different operations:

```
WRONG (what Iguana shaders do):
  uv_warped = warp(uv, time, audio)
  color = draw_geometry(uv_warped)
  // Each frame is independent. No trails.

RIGHT (what MilkDrop does):
  warp_offset = compute_warp(uv, time, audio)  // per-pixel displacement
  prev_color = texture(prev_frame, uv + warp_offset)  // sample previous frame at displaced position
  prev_color *= zoom_and_rotate(prev_color, uv)  // zoom + rotate
  prev_color *= decay  // fade
  new_color = draw_geometry(uv)  // draw new stuff
  color = prev_color + new_color  // composite
```

The warp offset is typically computed as:

```glsl
// Simplified MilkDrop-style warp
vec2 warp = vec2(0.0);
warp.x += sin(uv.y * 10.0 + time_val * 1.4) * 0.02;
warp.y += cos(uv.x * 8.0  + time_val * 1.1) * 0.02;
warp.x += sin(length(uv) * 6.0 - time_val * 0.7) * 0.015;
warp.y += cos(length(uv) * 6.0 - time_val * 0.9) * 0.015;

// Audio modulates the warp amplitude
warp *= 1.0 + bass * 3.0;
warp *= 1.0 + energy * 1.5;

// Apply: sample previous frame at displaced position
vec2 sample_uv = uv + warp;
```

The displacement is small (a few percent of the screen), but compounding over 60+ frames creates large-scale flowing structures.

---

## 3. What Iguana Currently Gets Right

Not everything is missing. Iguana has some genuine strengths:

**Audio analysis engine is excellent.** The adaptive normalization, asymmetric smoothing, transient detection, and mood metrics (`warmth`, `brightness`, `density`) are arguably more sophisticated than MilkDrop's original audio pipeline. The engine extracts a rich set of audio features and delivers them as clean, normalized uniforms. This is a real asset.

**Cosine palettes.** The Inigo Quilez `palette()` function used in the shaders is exactly the right approach. MilkDrop uses essentially the same technique for color cycling.

**The boilerplate is solid.** Having all uniforms declared with `hint_range` and sensible defaults makes shader development straightforward. The engine correctly handles uniform pushing every frame.

**Post-processing stack.** Tonemap → gamma → grain → vignette is the right pipeline. MilkDrop doesn't do all of these (it predates widespread tonemapping), but the modern equivalents are correct.

**Audio-reactive patterns.** The kick flash, snare flash, beat-phase pulse, and frequency-band color mapping are all valid MilkDrop-era techniques applied correctly.

**The noise texture.** Providing a seamless simplex noise texture as a uniform is a good convenience that enables organic effects.

---

## 4. What Iguana Is Missing (The Gaps)

### Gap 1: No Feedback Buffer (Critical)

**This is the single biggest missing feature.** Without a previous-frame texture, there are no trails, no tunnel, no compounding distortion, no sense of visual memory. Every frame is generated from scratch. The result might look cool for a single frame, but over time it feels flat compared to MilkDrop.

**What needs to be built:**
- A `SubViewport` that captures the Visualizer's output each frame
- A `prev_frame` sampler2D uniform pushed to the shader containing the previous frame's texture
- The viewport texture must be the *previous* frame (not the current frame being rendered)

**Implementation approach:**
1. In `visualizer.gd`, create a `SubViewport` and a `SubViewportContainer`
2. Reparent the Visualizer `ColorRect` into the SubViewport
3. Each frame in `_process()`, push `_feedback_vp.get_texture()` as the `prev_frame` uniform
4. Since `_process()` runs before the render, the shader reads the previous frame's output
5. The shader's new output becomes the next frame's `prev_frame`

**Shader-side changes:**
```glsl
uniform sampler2D prev_frame : hint_default_white, filter_linear, repeat_disable;
```

**UI consideration:** The VisualizerUI overlay must be a child of the `SubViewportContainer` (not the SubViewport) so it renders above the feedback viewport but is NOT captured in the feedback texture. If the UI is inside the viewport, debug text and the shader name label will appear as trails.

**Silence handling:** When `_analyzer.is_sounding == false`, the feedback loop keeps running. With a slow decay (e.g. 0.97), the last frame will sit there indefinitely — which can look nice, but can also mean a bright flash from just before the track stopped burns in for a long time. Two options: push a `uniform float is_sounding` and in the shader ramp decay toward 0.0 faster when it's 0, or clamp the feedback UV sampling to black outside `[0,1]` (already done via `clamp(...)`) and accept the slow natural fade. Either is fine — just don't leave it untested.

### Gap 2: No Warp-Then-Composite Split

MilkDrop separates the warp/decay pass from the new-geometry pass. In Iguana, everything happens in a single `fragment()` function with no access to the previous frame.

**What this means practically:** Even if we add `prev_frame`, current shaders would need to be restructured. The pattern becomes:

```glsl
void fragment() {
    vec2 uv = UV;

    // ── PASS 1: Feedback (warp + zoom + rotate + decay previous frame) ──
    vec2 feedback_uv = uv - 0.5;
    feedback_uv *= 0.97 + bass * 0.02;          // zoom (compounds into tunnel)
    float rot_amount = 0.008 + energy * 0.01;   // rotation (compounds into spiral)
    float c = cos(rot_amount), s = sin(rot_amount);
    feedback_uv = mat2(vec2(c, s), vec2(-s, c)) * feedback_uv;
    feedback_uv += 0.5;

    // Per-pixel warp displacement
    vec2 warp = vec2(
        sin(uv.y * 10.0 + time_val * 1.4) * 0.02,
        cos(uv.x * 8.0  + time_val * 1.1) * 0.02
    );
    warp *= 1.0 + bass * 3.0 + energy * 1.5;

    // Sample and decay
    vec3 trail = texture(prev_frame, feedback_uv + warp).rgb;
    trail *= 0.92 + 0.06 * (1.0 - energy);  // more energy = longer trails

    // ── PASS 2: Draw new geometry on top ──
    vec3 new_geom = vec3(0.0);
    // ... your audio-reactive geometry here ...

    // ── Composite ──
    vec3 col = trail + new_geom;

    COLOR = vec4(col, 1.0);
}
```

This two-pass-in-one-shader approach works once `prev_frame` is available. A true two-render-pass approach (separate warp shader + composite shader) would be even better but requires more engine restructuring.

### Gap 3: No Beat-Synced Preset Switching

MilkDrop switches between completely different presets on beat boundaries. Each preset has its own warp equations, decay rate, color palette, and geometry. The switch is typically a brief crossfade.

**What Iguana has:** Manual shader switching with `E`/`Q` keys and auto-shuffle on a 45-second wall-clock timer.

**What's missing:**
- Automatic switching triggered by beat detection (not a timer)
- Crossfade blending between the outgoing and incoming shader
- The presets themselves are just different `.gdshader` files, which is fine

**Implementation approach:**
1. Track a `_switch_cooldown` float. After any switch, don't allow another for at least ~4 seconds.
2. In `_process()`, check `_analyzer._kick_envelope > 0.85 and _analyzer._beat_confidence > 0.5` — this fires on a strong confirmed kick, not random loud noise.
3. Call `_shuffle()` when the condition fires and the cooldown has expired.
4. For crossfade: hold both `_outgoing_mat` and `_incoming_mat` simultaneously, blend their outputs by driving a `mix_factor` uniform from 0→1 over ~0.3 seconds. The simplest approach uses a third "crossfade" ColorRect that reads both textures via SubViewports and outputs the blend.

**Why this matters for the MilkDrop feel:** The sudden transformation on a beat drop is part of the experience. It's not just visual variety — it's the surprise of a new visual world opening up exactly when the music shifts.

### Gap 4: No Mouse Interaction

MilkDrop uses the mouse position as a warp center and geometry attractor. Moving the mouse warps the feedback toward the cursor. Clicking creates ripple effects.

**What needs to be added:**
```glsl
uniform vec2 mouse_pos = vec2(0.5, 0.5);   // normalized [0,1]
uniform float mouse_down : hint_range(0.0, 1.0) = 0.0;
```

Mouse-driven warp example:
```glsl
vec2 to_mouse = mouse_pos - uv;
float mouse_dist = length(to_mouse);
float mouse_pull = exp(-mouse_dist * 8.0) * 0.03 * mouse_down;
warp += normalize(to_mouse) * mouse_pull;
```

### Gap 5: No Frame Counter

Some feedback effects need to know the absolute frame number (e.g., "do something every 4th frame" or "alternate between two behaviors").

```glsl
uniform int frame = 0;
```

### Gap 6: Current Shaders Regenerate Everything Each Frame

Looking at the existing shaders:

- `cosmic_abyss.gdshader` — raymarches from scratch every frame. No persistence.
- `afterimage.gdshader` — IFS folds from scratch every frame. The name is ironic; there are no actual afterimages.
- `glitch_garden.gdshader` — raymarches from scratch every frame.
- `starfall.gdshader` — iterates a fold pipeline from scratch every frame.

All of these generate their entire visual from scratch each frame using `time_val` as the only source of temporal continuity. The result is smooth, but it has no *memory*. A bright flash on a kick drum appears for one frame and vanishes. In MilkDrop, that flash would trail, spiral, and fade over 2-3 seconds.

This is not a criticism of the shaders — they're working within the constraints of the engine. But once the feedback buffer is added, these shaders should be rewritten (or new ones created) to use it.

---

## 5. What MilkDrop Gets Wrong (Or Doesn't Need)

Iguana shouldn't blindly copy everything MilkDrop does. Some things are better left in the early 2000s:

**MilkDrop's audio analysis is primitive.** It uses a simple FFT with fixed band extraction. Iguana's adaptive normalization, spectral flux, and mood metrics are genuinely better. Don't regress here.

**MilkDrop's resolution is low.** It typically renders at 320x240 or 640x480 and stretches. This actually helps the feedback look (lower res = blurrier trails = dreamier). Iguana renders at full resolution, which is sharper but loses some of the soft trail aesthetic. This is a tradeoff, not a bug.

**MilkDrop doesn't raymarch.** Its geometry is simple: circles, lines, and text rendered via a fixed-function pipeline. The complex visuals come entirely from the feedback loop compounding simple shapes. Iguana's raymarching and IFS folding shaders are more technically sophisticated than anything MilkDrop renders. But they don't benefit from feedback, so they feel less "MilkDrop-like" than a simple circle drawn into a feedback buffer.

**MilkDrop's color is 16-bit.** Banding in the trails actually looks nice (it creates posterization effects as trails fade). Don't try to eliminate all banding.

---

## 6. The Priority Order

If we want to close the gap with MilkDrop, here's the order to tackle things:

1. **Feedback buffer** — Without this, nothing else matters. This is the foundation.
2. **Feedback-aware shader template** — A starter shader that demonstrates the warp → decay → composite pattern with `prev_frame`.
3. **Mouse uniforms** — Small addition, big interactivity improvement.
4. **Frame counter** — Trivial to add, enables rhythm-based effects.
5. **At least one feedback-based shader** — Convert or create a shader that actually uses `prev_frame`. A simple one: draw a circle at the center, pulse it with kick, let it trail.
6. **Beat-synced preset switching** — Larger feature, but completes the experience.
7. **Two-pass rendering** — Separate warp shader from composite shader. Optional optimization; the single-shader approach works.

---

## 7. The Feedback Shader Template

Once the feedback buffer is implemented, this is the minimum viable MilkDrop-style shader:

```glsl
shader_type canvas_item;

// ── Audio uniforms (same as always) ──
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;  // 20-60Hz — use this for kick-drum zoom, not bass
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;  // kick envelope driven by sub_bass band
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float time_val    = 0.0;

// ── New uniforms (from feedback buffer) ──
uniform sampler2D prev_frame : hint_default_white, filter_linear, repeat_disable;
uniform vec2 mouse_pos = vec2(0.5, 0.5);
uniform float mouse_down : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);

#define TAU 6.28318530718

vec3 palette(float t, vec3 shift) {
    return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}

void fragment() {
    vec2 uv = UV;
    float t = time_val;

    // ════════════════════════════════════════════════════════════════
    //  PART 1: FEEDBACK — warp, zoom, rotate, and decay previous frame
    // ════════════════════════════════════════════════════════════════

    vec2 center = uv - 0.5;
    center.x *= rect_size.x / rect_size.y;  // aspect correct the feedback too

    // Zoom: sample slightly inward. 0.97 = aggressive tunnel. 0.995 = subtle drift.
    float zoom = 0.98 - bass * 0.015;
    center *= zoom;

    // Rotate: small per-frame rotation compounds into a spiral
    float rot = 0.008 + energy * 0.008 + beat * 0.005;
    float c = cos(rot), s = sin(rot);
    center = mat2(vec2(c, s), vec2(-s, c)) * center;

    // Back to UV space
    vec2 feedback_uv = center;
    feedback_uv.x /= rect_size.x / rect_size.y;
    feedback_uv += 0.5;

    // Per-pixel warp displacement (this is what makes trails curve and flow)
    // Use aspect-corrected 'center' for spatial inputs so the warp field
    // is isotropic on non-square displays (otherwise horizontal sine waves
    // appear stretched on 16:9 screens).
    vec2 warp = vec2(
        sin(center.y * 10.0 + t * 1.4) * 0.015,
        cos(center.x * 8.0  + t * 1.1) * 0.015
    );
    warp.x += sin(length(center) * 6.0 - t * 0.7) * 0.01;
    warp.y += cos(length(center) * 6.0 - t * 0.9) * 0.01;
    warp *= 1.0 + bass * 3.0 + energy * 1.5;

    // Mouse attraction
    vec2 to_mouse = mouse_pos - uv;
    float md = length(to_mouse);
    warp += normalize(to_mouse + 0.001) * exp(-md * 8.0) * 0.03 * mouse_down;

    // Sample previous frame at warped position
    vec3 trail = texture(prev_frame, clamp(feedback_uv + warp, 0.0, 1.0)).rgb;

    // Decay: how fast trails fade. 0.90 = short, 0.97 = long, 0.99 = very long
    float decay = 0.94 - energy * 0.03;
    trail *= decay;

    // ════════════════════════════════════════════════════════════════
    //  PART 2: NEW GEOMETRY — draw fresh audio-reactive shapes on top
    // ════════════════════════════════════════════════════════════════

    vec2 uv_c = uv - 0.5;
    uv_c.x *= rect_size.x / rect_size.y;
    float radius = length(uv_c);
    float angle = atan(uv_c.y, uv_c.x);

    // Spiral arms that pulse with kick
    float arms = 5.0 + bass * 3.0;
    float spiral = sin(angle * arms + radius * 12.0 - t * 3.0);
    spiral = pow(max(spiral, 0.0), 3.0);  // sharp positive peaks only

    // Ring at a radius that breathes with energy
    float ring_r = 0.15 + energy * 0.1 + kick * 0.08;
    float ring = exp(-abs(radius - ring_r) * 40.0);

    // Center glow on kick
    float core = exp(-radius * 8.0) * kick * 1.5;

    // Combine new geometry
    float shape = spiral * 0.3 + ring * 0.5 + core;

    // Color with cycling palette
    vec3 shift = vec3(warmth * 0.15, 0.33 + warmth * 0.15, 0.67 + brightness * 0.15);
    vec3 new_col = palette(shape + t * 0.2, shift) * shape;

    // Onset flash
    new_col += vec3(0.15) * onset;

    // ════════════════════════════════════════════════════════════════
    //  PART 3: COMPOSITE — combine feedback trail + new geometry
    // ════════════════════════════════════════════════════════════════

    vec3 col = trail + new_col;

    // Post-processing
    col = col / (1.0 + col);  // tonemap
    col = pow(max(col, vec3(0.0)), vec3(0.4545));  // gamma

    // Grain
    float grain = texture(noise_tex, uv * 200.0 + fract(t * 0.1)).r;
    col += (grain - 0.5) * 0.03;

    // Vignette
    float vig = 1.0 - smoothstep(0.3, 1.2, length(uv - 0.5) * 1.8);
    col *= mix(0.6, 1.0, vig);

    COLOR = vec4(col, 1.0);
}
```

Notice how simple the geometry is — a spiral, a ring, and a center glow. Nothing fancy. The visual complexity comes entirely from the feedback loop compounding this simple pattern over hundreds of frames.

---

## 8. Why Existing Shaders Won't Look Like MilkDrop (Yet)

| Shader | Why it doesn't feel like MilkDrop |
|---|---|
| `cosmic_abyss` | Raymarches from scratch each frame. Beautiful but no memory. A bright kick flash lasts exactly one frame. |
| `afterimage` | Despite the name, there are no actual afterimages. The IFS folding regenerates completely each frame. No trails. |
| `glitch_garden` | Raymarches from scratch. The box geometry is complex but ephemeral — nothing persists between frames. |
| `starfall` | Iterates a fold pipeline from scratch. The result is a dense crystalline pattern, but it has no visual history. |
| `signal_scope` | Waveform/scope display rendered fresh each frame from the current audio bands. No persistence, by design — scopes are diagnostic tools, not feedback-loop candidates. |

All four shaders are technically impressive. But they all share the same fundamental limitation: they have amnesia. They cannot remember what happened last frame. Once `prev_frame` exists, we can build shaders that do.

---

## 9. Quick Reference: MilkDrop's Core Parameters

For anyone implementing the feedback loop, these are the key tuning knobs:

| Parameter | Typical Range | Effect |
|---|---|---|
| **Zoom** | 0.95 – 0.995 | How much the previous frame is scaled down. Lower = faster tunnel. |
| **Rotation** | 0.0 – 0.03 rad/frame | Per-frame rotation. Creates spiral vs. straight tunnel. |
| **Decay** | 0.88 – 0.98 | Color multiplier on previous frame. Lower = shorter trails. |
| **Warp amplitude** | 0.005 – 0.05 | Per-pixel displacement strength. Creates organic flow. |
| **Warp frequency** | 3.0 – 15.0 | Spatial frequency of the sine/cosine warp. Higher = tighter ripples. |

**Audio reactivity of feedback parameters:**
- Bass controls zoom (bass kicks → zoom pulses → tunnel breathes)
- Energy controls warp amplitude (more energy → more displacement → wilder flow)
- Beat controls rotation (beat → brief rotation spike → spiral tightens on the beat)
- Treble can control warp frequency (treble → tighter warp ripples → more detailed flow)
- Onset can trigger a single-frame zoom spike (everything rushes inward for one frame)
