# What Makes MilkDrop Feel Like MilkDrop

A technical breakdown of MilkDrop's rendering pipeline, why each part matters, and where Iguana stands relative to it. Written to answer the question: *why does this feel the way it does?*

---

## The Short Answer

MilkDrop looks the way it does because of **one thing**: every frame is built on top of the previous frame. The previous frame is sampled with a slight zoom, a slight rotation, and a fade, then new geometry is drawn on top. This creates trails, tunnels, spirals, and the sense that the visuals have *weight* and *memory*. Without this feedback loop, you cannot get the MilkDrop look. Period.

Everything else — the cosine palettes, the polar warps, the IFS folding — is decoration on top of the feedback loop. The feedback is the foundation.

Iguana has this. The rest of this document explains how it works and where the gaps remain.

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
│     (shapes, particles, whatever)            │
│                                              │
│  5. OUTPUT: This becomes next frame's input  │
└──────────────────────────────────────────────┘
```

The output of step 5 is fed back into step 1 on the next frame. This is a **feedback loop**. The loop runs every frame, compounding small distortions over time.

### Why each step matters

**Warp (per-pixel displacement):** This is what makes trails curve, spiral, and flow rather than just shrinking to the center. A full-screen displacement field using sine/cosine functions driven by time and audio shifts each pixel by a different amount. Without audio, the warp still runs on time alone, producing a slow ambient drift.

**Zoom:** Sampling the previous frame at `UV * 0.97` (slightly zoomed in) creates the infinite tunnel. The 3% zoom compounds: after 100 frames, the content has been magnified ~20×. Old geometry appears to fly toward the viewer. This is why MilkDrop has that "falling into the screen" look.

**Rotation:** A tiny per-frame rotation (0.005–0.02 rad) makes the tunnel spiral instead of converging to a point. Combined with zoom, it creates the iconic spiraling tunnel.

**Decay:** Multiplying the old frame by 0.90–0.98 fades it out gradually. A decay of 0.95 means a pixel's brightness halves roughly every 14 frames (~0.5 s at 30 fps). This controls trail length. Lower = shorter trails; higher = longer, more persistent.

**Composite:** New bright geometry is drawn on top of the faded, zoomed, rotated old frame. Because the old frame is faded but still visible, the new geometry appears to "leave behind" a trail that spirals inward and fades out.

### The mathematical compounding

A single frame's warp is subtle (maybe 2–5 pixels of displacement). After 60 frames, those displacements have compounded into dramatic flowing structures:

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

This deserves its own section because it is the most misunderstood part of MilkDrop.

MilkDrop's warp is NOT "warp the UV coordinates of new geometry." It is "warp WHERE YOU SAMPLE the previous frame." These are fundamentally different:

```
WRONG (single-frame shader):
  uv_warped = warp(uv, time, audio)
  color = draw_geometry(uv_warped)
  // Each frame is independent. No trails.

RIGHT (feedback shader):
  warp_offset = compute_warp(uv, time, audio)  // per-pixel displacement
  prev_color = texture(prev_frame, uv + warp_offset)  // sample previous frame displaced
  prev_color *= zoom_and_rotate(uv)  // zoom + rotate
  prev_color *= decay                // fade
  new_color = draw_geometry(uv)      // draw new stuff
  color = prev_color + new_color     // composite
```

The warp offset is typically:

```glsl
vec2 warp = vec2(0.0);
warp.x += sin(uv.y * 10.0 + time_val * 1.4) * 0.02;
warp.y += cos(uv.x * 8.0  + time_val * 1.1) * 0.02;
warp.x += sin(length(uv) * 6.0 - time_val * 0.7) * 0.015;
warp.y += cos(length(uv) * 6.0 - time_val * 0.9) * 0.015;
warp *= 1.0 + bass * 3.0 + energy * 1.5;

vec2 sample_uv = uv + warp;
```

The displacement is small per frame, but compounding over 60+ frames creates large-scale flowing structures.

---

## 3. What Iguana Gets Right

**Feedback buffer.** Two SubViewports handle it cleanly. `FeedbackViewport` renders the current frame; `BackbufferViewport` copies its output each frame and is the source of `prev_frame`. The two-viewport design avoids the GPU error of sampling a viewport's own framebuffer. `prev_frame` always holds the completed previous frame, never the live target.

**Post-process layer outside the loop.** `post_process.gdshader` reads the raw feedback texture and applies tonemap, gamma, vignette, and grain *above* the feedback loop. Bloom and gamma applied inside the loop compound every frame and blow out. Iguana's architecture prevents this by design.

**Per-shader Reinhard inside the loop.** `loop_reinhard` is a tunable uniform that applies `col / (col + k) * (1 + k)` inside the feedback composite, preventing trail brightness from accumulating without bound. Each shader sets its own default; it is live-tunable in the Settings window.

**Audio analysis.** The adaptive normalization, asymmetric smoothing, transient detection, and mood metrics (`warmth`, `brightness`, `density`) are more sophisticated than MilkDrop's original FFT pipeline. The engine extracts a rich set of audio features and delivers them as clean, normalized uniforms.

**Beat-triggered switching.** When shuffle is on, a strong confirmed kick (`beat_confidence > 0.5`, `kick_envelope > 0.85`) triggers a shader switch. A 4-second cooldown prevents rapid-fire switches. A wall-clock timer fires as fallback when beat confidence is too low. On every switch a static snapshot of the current frame fades out over 1.5 s as a crossfade overlay.

**Frame counter.** `frame` (int) is pushed every frame, enabling per-frame parity checks and rhythm effects.

**Cosine palettes.** The Inigo Quilez `palette()` function is the right approach. MilkDrop uses essentially the same technique for color cycling.

**Shader auto-discovery.** Dropping a `.gdshader` file into `res://shaders/` is enough. The engine reads `@meta` tags from the first 40 lines of each file and populates the shader list at startup. No code changes required.

---

## 4. What Remains Open

### Open: No Mouse Interaction

MilkDrop uses the mouse position as a warp center and geometry attractor. Clicking creates ripple effects. Iguana doesn't push mouse position to shaders yet.

What is needed:
```glsl
uniform vec2 mouse_pos = vec2(0.5, 0.5);   // normalized [0,1]
uniform float mouse_down : hint_range(0.0, 1.0) = 0.0;
```

Engine side: push `get_viewport().get_mouse_position() / get_viewport().size` each frame. Shader side: a pull-toward-mouse warp term:

```glsl
vec2 to_mouse = mouse_pos - uv;
float mouse_pull = exp(-length(to_mouse) * 8.0) * 0.03 * mouse_down;
warp += normalize(to_mouse + 0.001) * mouse_pull;
```

### Open: Existing Shaders Don't Use the Feedback Buffer

The current shaders (afterimage, starfall, phosphorescence, etc.) were written before the feedback buffer existed. They raymarch or fold from scratch each frame and use `time_val` as their only temporal continuity. They look fine but have no visual memory.

This is not a bug — they work within the current engine. But the MilkDrop feel comes from shaders that actually use `prev_frame`. A simple ring that trails and spirals inward will feel more alive than a complex raymarcher that regenerates every frame.

### Open: True Two-Pass Rendering

MilkDrop separates the warp/decay pass from the new-geometry pass at the GPU level. In Iguana, both passes happen in a single `fragment()` function, which works but makes it harder to separate feedback tuning from geometry design. A second SubViewport dedicated to the warp pass would be the proper split. This is a nice-to-have optimization, not a blocker.

---

## 5. What MilkDrop Gets Wrong (Or Doesn't Need)

Iguana should not blindly copy everything MilkDrop does.

**MilkDrop's audio analysis is primitive.** Fixed band extraction from a simple FFT. Iguana's adaptive normalization, spectral flux, and mood metrics are genuinely better. Don't regress here.

**MilkDrop's resolution is low.** 320×240 or 640×480 stretched. This helps the feedback look — lower res means blurrier trails, dreamier result. Iguana at full resolution is sharper and loses some of that softness. This is a tradeoff, not a bug.

**MilkDrop doesn't raymarch.** Its geometry is simple circles, lines, and text from a fixed-function pipeline. The complex visuals come entirely from feedback compounding simple shapes. Iguana's raymarching shaders are technically more sophisticated, but they don't benefit from feedback, so they feel less "MilkDrop-like" than a simple circle in a feedback buffer.

**MilkDrop's color is 16-bit.** The banding in trails creates posterization as they fade. Eliminating all banding is not always desirable.

---

## 6. Feedback Brightness — Equilibrium Formula

Every pixel in a feedback shader converges to a steady-state brightness. If a pixel has `new_col` added each frame and the trail decays by factor `d`:

```
brightness_equilibrium = new_col_per_pixel / (1.0 - d)
```

With `d = 0.928`, equilibrium is `new_col / 0.072 ≈ 14× emission`. A per-pixel emission of just `0.07` converges to 1.0 — clipped white. Broadly lit areas (plasma fills, volumetric rays, wide glow shells) white out fast because they add `new_col > 0` to every pixel every frame.

| Decay | Equilibrium multiplier | Max safe per-pixel emission |
|---|---|---|
| 0.98 | 50× | 0.02 |
| 0.93 | 14× | 0.07 |
| 0.90 | 10× | 0.10 |
| 0.85 |  7× | 0.14 |

Keep per-pixel emissions low. Narrow features (thin rings, sharp spiral bands, point sources) are safe at higher values because most pixels see `new_col ≈ 0` most frames.

**Use `loop_reinhard` as the safety valve.** It compresses trail brightness inside the loop, preventing unbounded accumulation without forcing you to manually tune decay. Start at `0.9` and adjust from there.

---

## 7. Feedback Tuning Reference

| Parameter | Typical Range | Effect |
|---|---|---|
| Zoom factor | 0.95 – 0.995 | Lower = faster tunnel. Compounds multiplicatively. |
| Rotation per frame | 0.003 – 0.02 rad | Makes tunnel spiral rather than converge to a point. |
| Decay multiplier | 0.88 – 0.98 | How fast trails fade. 0.95 ≈ 14 frames to half-brightness at 30 fps. |
| Warp amplitude | 0.005 – 0.04 | Per-pixel displacement. Tiny per-frame, dramatic after 60+ frames. |
| Warp frequency | 3 – 15 | Spatial frequency of sine/cosine warp. Higher = tighter ripples. |
| loop_reinhard | 0.0 – 3.0 | 0 = off (raw accumulation), ~0.9 = moderate clamp, 3.0 = heavy. |

**Audio-reactive feedback mappings:**
- `sub_bass` → zoom pulse (kick makes the tunnel breathe)
- `bass` + `energy` → warp amplitude (more energy = wilder flow)
- `energy` + `beat` → rotation rate (spiral tightens on beats)
- `energy` → decay (louder music = longer trails)
- `onset` → single-frame zoom spike (everything rushes inward on a transient)
