# Preset Authoring

A preset is a folder. The folder contains exactly two required files (and one optional):

```
my_preset/
├── shader.gdshader     # required — the fragment shader
├── manifest.json       # required — metadata only
└── preview.png         # optional — 620×620 thumbnail for Workshop / picker
```

That's the entire format. There is no preset framework, no JS module, no JSON parameter spec. Everything that drives the shader is declared **inside the shader file**, using GDShader's native `uniform` syntax and `hint_*` annotations.

---

## shader.gdshader

GDShader is a GLSL ES 3.0 dialect. For fragment-only visualizers it's effectively as capable as Shadertoy.

A minimal preset:

```glsl
shader_type canvas_item;

// ── Standard uniforms (always provided by VisualEngine) ──────────
uniform float bass     : hint_range(0.0, 1.0) = 0.0;
uniform float mid      : hint_range(0.0, 1.0) = 0.0;
uniform float treble   : hint_range(0.0, 1.0) = 0.0;
uniform float beat     : hint_range(0.0, 1.0) = 0.0;
uniform float time_val = 0.0;

// ── Custom uniforms (drive the parameter panel) ──────────────────
uniform float zoom_amount  : hint_range(0.0, 1.0) = 0.4;
uniform float color_shift  : hint_range(0.0, 1.0) = 0.3;
uniform vec3  tint_color   : source_color = vec3(1.0, 1.0, 1.0);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);

    float zoom = 1.0 + bass * zoom_amount;
    uv *= zoom;

    float angle = atan(uv.y, uv.x) + time_val * 0.3;
    float plasma = sin(angle * 6.0 + mid * 5.0 + time_val)
                 + cos(dist * 12.0 - bass * 8.0);

    vec3 col = vec3(
        0.5 + 0.5 * sin(plasma + color_shift * 6.28 + 0.0),
        0.5 + 0.5 * sin(plasma + color_shift * 6.28 + 2.1),
        0.5 + 0.5 * sin(plasma + color_shift * 6.28 + 4.2)
    ) * tint_color + beat * 0.3;

    COLOR = vec4(col, 1.0);
}
```

Save the file. Iguana's hot-reload (`docs/04-visualization-engine.md`) picks up the change in milliseconds. The parameter panel rebuilds itself from the new uniform list — `zoom_amount`, `color_shift`, and `tint_color` get sliders / a color picker. The standard uniforms are filtered out of the panel because their values come from the audio pipeline.

---

## Standard uniforms

These are always pushed by `VisualEngine`. Declare them by name and they get audio-reactive values; omit them and they cost nothing.

| Uniform | Type | Range | Source |
|---|---|---|---|
| `bass` | `float` | 0..1 | 60–250 Hz |
| `mid` | `float` | 0..1 | 250–4000 Hz |
| `treble` | `float` | 0..1 | 4000–20000 Hz |
| `presence` | `float` | 0..1 | 4–8 kHz (vocals/cymbals) |
| `volume` | `float` | 0..1 | overall RMS |
| `beat` | `float` | 0..1 | beat envelope (decays between hits) |
| `bpm` | `float` | 0..200 | tempo estimate, 0 if unknown |
| `time_val` | `float` | 0..∞ | seconds since launch |
| `spectrum` | `sampler2D` | — | full 512-bin spectrum (R32F, 512×1) |

**Sampling the spectrum**:

```glsl
uniform sampler2D spectrum;

void fragment() {
    // Sample bin at horizontal screen position
    float bin = texture(spectrum, vec2(UV.x, 0.5)).r;
    COLOR = vec4(bin, bin * 0.5, bin * 0.2, 1.0);   // FFT bars
}
```

Only declare `spectrum` if you actually use it — `VisualEngine` skips the per-frame texture upload when no shader samples it.

---

## Custom uniforms — driving the parameter panel

The parameter panel inspects the live shader's uniform list and generates one control per uniform. The control type is chosen from the GDShader hint:

| Declaration | Generated control |
|---|---|
| `uniform float x : hint_range(0.0, 1.0) = 0.5;` | Slider, 0..1, default 0.5 |
| `uniform float x : hint_range(-2.0, 2.0, 0.1) = 0.0;` | Slider, step 0.1 |
| `uniform vec3 c : source_color = vec3(1.0);` | Color picker (RGB) |
| `uniform vec4 c : source_color = vec4(1.0);` | Color picker (RGBA) |
| `uniform int n : hint_range(1, 8) = 4;` | Integer slider |
| `uniform bool flag = true;` | Checkbox |
| `uniform sampler2D tex;` | (omitted from panel — internal) |
| `uniform vec2 v = vec2(0.0);` | Two number inputs (no hint = no slider) |

**Authoring rules**:

1. **Always provide a default.** Without one, the panel has nothing to fall back to and the shader compiles with junk values.
2. **Use `hint_range` for anything you want as a slider.** Without it, the panel falls back to a number input — usable but worse UX.
3. **Use `source_color` for any color uniform.** Otherwise the panel renders three cryptic float sliders.
4. **Don't reuse standard-uniform names for custom logic.** Naming a custom uniform `bass` will shadow the audio value and confuse users.

User adjustments are persisted per-preset in `user://presets/<id>/values.json` (a flat `name → value` dict). When a preset is loaded, the panel reads the saved values and pushes them back into the shader before the first render. See `docs/09-preset-creator.md`.

---

## manifest.json

Metadata only. Parameter values do **not** live here.

```json
{
  "name":        "Nebula Storm",
  "author":      "yourhandle",
  "version":     "1.0.0",
  "description": "Swirling plasma reacting to bass",
  "tags":        ["psychedelic", "bass-heavy"],
  "preview":     "preview.png",
  "workshop_id": null
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Display name in PresetPicker |
| `author` | yes | Free-form |
| `version` | yes | Semver string; bumped on Workshop updates |
| `description` | no | Shown in PresetPicker tooltip and Workshop page |
| `tags` | no | Free-form array; Workshop search uses these |
| `preview` | no | Filename, relative to preset folder; defaults to `preview.png` |
| `workshop_id` | no | Set by `Workshop.gd` after first publish; identifies the preset for updates |

The `Settings` autoload validates the manifest with a small schema check on load. Invalid manifests don't crash the app — the preset is skipped with a log entry.

---

## Porting from Shadertoy

Shadertoy's `mainImage` shaders translate to GDShader with a small set of substitutions:

| Shadertoy | GDShader |
|---|---|
| `void mainImage(out vec4 fragColor, in vec2 fragCoord)` | `void fragment()` |
| `fragCoord` | `FRAGCOORD.xy` |
| `iResolution.xy` | `1.0 / SCREEN_PIXEL_SIZE` |
| `fragCoord / iResolution.xy` | `UV` |
| `iTime` | `time_val` |
| `iMouse` | (no equivalent — drop, or wire a `mouse_pos` custom uniform) |
| `texture2D(...)` | `texture(...)` (GLSL ES 3.0 already uses `texture`) |
| `gl_FragColor` | `COLOR` |
| `varying` (vert→frag) | `varying` (same; or use `INSTANCE_CUSTOM` patterns) |

[godotshaders.com](https://godotshaders.com) has hundreds of pre-ported community shaders — usually a faster starting point than direct Shadertoy translation.

---

## What GDShader (canvas_item) gives you

| Feature | Available |
|---|---|
| Trig / math (sin, cos, atan, pow, exp, log, mix, smoothstep, clamp, …) | yes |
| `vec2`/`vec3`/`vec4`, `mat2`/`mat3`/`mat4`, swizzles | yes |
| Texture sampling (`texture`, `textureLod`, `textureSize`) | yes |
| Hand-rolled hash / value / Perlin / Simplex noise | yes (a few dozen lines) |
| Loops with constant or runtime bounds | yes (constant bounds optimise better) |
| `discard` | yes |
| Multiple render targets / SubViewport feedback | yes (deferred to v1.x) |
| Compute shaders | no — Godot has compute, but not in `canvas_item` |
| SSBOs / image load-store | no |
| Geometry / tessellation shaders | no |

For audio-reactive visuals, the fragment-only canvas pipeline is enough — Shadertoy proves the point with tens of thousands of effects.

---

## Built-ins quick reference

Inside `void fragment()`:

| Built-in | Type | What |
|---|---|---|
| `UV` | `vec2` | 0..1 fragment UV |
| `FRAGCOORD` | `vec4` | Pixel coords (`.xy` is what you usually want) |
| `SCREEN_PIXEL_SIZE` | `vec2` | `1.0 / viewport_size` |
| `TIME` | `float` | Engine time. Iguana provides `time_val` instead — same thing, but kept independent of engine pause behavior |
| `COLOR` | `vec4` (out) | Fragment output |
| `SCREEN_UV` | `vec2` | UV in screen space (use `UV` unless you need post-process effects) |

---

## Performance guidelines

- **Stay under 4 ms per frame** at 1080p. Anything more pushes 60 fps machines into drops.
- **Loops cost.** A 32-iteration ray march is fine; a 256-iteration one will struggle on integrated GPUs.
- **`pow`, `exp`, `log` are not free.** Cache results when possible.
- **Avoid `if` on per-pixel branching** when the branch is wide — modern GPUs are reasonable but extreme cases (4× overdraw conditional) tank performance.
- **Profile with the in-app FPS overlay** (Settings → Show FPS). If your preset drops below 60 on a 5-year-old laptop, simplify.

---

## What is **not** in a preset

- No GDScript. Presets are pure shader code.
- No file reads, no network. The shader sandbox forbids both by definition.
- No persistent state across launches. Save user-tunable parameters in `values.json` (handled by the parameter panel); shader state is recomputed every frame from `time_val` and audio inputs.
- No multi-shader compositions. One preset = one `.gdshader` (until multi-pass lands; see `04-visualization-engine.md`).
