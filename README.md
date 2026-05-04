# Iguana — MilkDrop-Style Audio Visualizer

Iguana is a Godot 4 audio-reactive shader visualizer built around a feedback rendering pipeline. It analyzes audio in real time, extracts a rich set of frequency, transient, and mood uniforms, and feeds them into a feedback loop that accumulates visual history across frames — the same core technique that makes MilkDrop look alive.

**Language:** GDScript  
**Renderer:** Compatibility  
**Target Godot:** 4.6

---

## Architecture

```
AudioEffectSpectrumAnalyzer
		↓
AudioAnalyzer.process()          — runs every frame in visualizer.gd
		↓
_push_uniforms()                 — 30+ values pushed to the active ShaderMaterial
		↓
FeedbackViewport (SubViewport)   — shader renders here
		↓
BackbufferViewport (SubViewport) — copies FeedbackViewport output each frame
		↓
prev_frame uniform               — shader reads last frame from BackbufferViewport
```

The two-viewport design is required: a shader cannot sample its own render target. `FeedbackViewport` renders the current frame; `BackbufferViewport` copies it immediately after (it sits later in the scene tree, so it renders second). Next frame, `prev_frame` is `BackbufferViewport.get_texture()` — the completed previous frame, never the live target.

---

## The Feedback Loop

This is the foundation of the MilkDrop aesthetic. Without it, shaders have no visual memory — every frame is independent and nothing trails.

```glsl
void fragment() {
	vec2 uv = UV;

	// ── 1. WARP + ZOOM + ROTATE previous frame ────────────────────────
	vec2 center = uv - 0.5;
	center.x *= rect_size.x / rect_size.y;   // aspect-correct

	center *= 0.98 - sub_bass * 0.02;        // zoom inward (compounds into tunnel)

	float rot = 0.007 + energy * 0.008;
	float c = cos(rot), s = sin(rot);
	center = mat2(vec2(c, s), vec2(-s, c)) * center;   // rotate (compounds into spiral)

	vec2 feedback_uv = center;
	feedback_uv.x /= rect_size.x / rect_size.y;
	feedback_uv += 0.5;

	// Per-pixel warp — use aspect-corrected center to avoid seams on 16:9
	vec2 warp = vec2(
		sin(center.y * 10.0 + time_val * 1.4) * 0.015,
		cos(center.x * 8.0  + time_val * 1.1) * 0.015
	);
	warp *= 1.0 + bass * 2.5 + energy * 1.5;

	// Soft edge fade: avoids the hard seam from repeat_disable clamping
	vec2 sample_uv  = feedback_uv + warp;
	vec2 edge_d     = min(sample_uv, 1.0 - sample_uv);
	float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

	vec3 trail = texture(prev_frame, sample_uv).rgb;
	trail *= (0.92 + energy * 0.05) * edge_fade;   // decay

	// ── 2. DRAW new geometry on top ────────────────────────────────────
	vec3 new_col = /* your audio-reactive shapes */;

	// ── 3. COMPOSITE ───────────────────────────────────────────────────
	COLOR = vec4(trail + new_col, 1.0);
}
```

**Key rules:**
- Warp inputs must use **aspect-corrected** coordinates (`center`, not raw `uv`) — raw UV coordinates produce a stretched warp field on 16:9 displays.
- Spiral arms must use an **integer arm count** (`floor(4.0 + bass * 3.0)`). A non-integer `N` in `sin(angle * N)` leaves a hard seam along the left-center horizontal line because `atan2` has a branch cut there.
- **Never use `atan()` in the warp field.** `atan2` jumps ±π at the negative x-axis. With a non-integer coefficient that discontinuity survives the `sin()`, and the warp compounds it every frame into a hard vertical cut on the left side of the screen. Use Cartesian `warped.x / warped.y / length(warped)` in warp expressions instead. `atan` is fine in the new-geometry layer (current frame only), not in the feedback path.
- **Do not clamp** the sample UV. Use `smoothstep` edge fade instead — clamping smears the border pixel into a visible artifact.
- `prev_frame` uses `hint_default_black` so the first frame starts from black.

---

## Feedback Brightness — Equilibrium Formula

Every pixel in a feedback shader converges to a steady-state brightness. If a pixel has `new_col` added to it each frame and the trail decays by factor `d`, the equilibrium is:

```
brightness_equilibrium = new_col_per_pixel / (1.0 - d)
```

With `d = 0.928` (common starting point), equilibrium is `new_col / 0.072 ≈ 14× emission`. A per-pixel emission of just `0.07` converges to 1.0 — clipped white. Broadly lit areas (plasma fills, volumetric rays, wide glow shells) white out fast because they add `new_col > 0` to every pixel on every frame.

**Practical limits:**

| Decay | Equilibrium multiplier | Max safe per-pixel emission |
|---|---|---|
| 0.98 | 50× | 0.02 |
| 0.93 | 14× | 0.07 |
| 0.90 | 10× | 0.10 |
| 0.85 |  7× | 0.14 |

Keep per-pixel emissions low. Narrow features (thin rings, sharp spiral bands, point sources) are safe at higher values because most pixels see `new_col ≈ 0` most frames.

**Post-processing lives inside the loop.** The final `COLOR` becomes `prev_frame` next frame. Any tonemap, gamma, or bloom applied before `COLOR = ...` is baked into the feedback and amplifies over time. Bloom is the worst offender — it expands bright areas spatially, increasing the number of pixels that receive `new_col > 0` next frame. Either skip bloom in feedback shaders or apply it very mildly after the feedback composite is already converged.

---

## Feedback Tuning Reference

| Parameter | Typical Range | Effect |
|---|---|---|
| Zoom factor | 0.95 – 0.995 | Lower = faster tunnel. Compounds multiplicatively. |
| Rotation per frame | 0.003 – 0.02 rad | Makes tunnel spiral rather than converge to a point. |
| Decay multiplier | 0.88 – 0.98 | How fast trails fade. 0.95 ≈ 14 frames to half-brightness at 30 fps. |
| Warp amplitude | 0.005 – 0.04 | Per-pixel displacement. Tiny per-frame, dramatic after 60+ frames. |
| Warp frequency | 3 – 15 | Spatial frequency of sine/cosine warp. Higher = tighter ripples. |

**Audio-reactive feedback:**
- `sub_bass` → zoom pulse (kick makes the tunnel breathe)
- `bass` + `energy` → warp amplitude (more energy = wilder flow)
- `energy` + `beat` → rotation rate (spiral tightens on beats)
- `energy` → decay (louder music = longer trails)
- `onset` → single-frame zoom spike (everything rushes inward on a transient)

---

## All Uniforms

### Frequency Bands

Adaptive normalized, smoothed with fast attack / slow release. Usable without per-track tuning.

| Uniform | Range | Hz | Notes |
|---|---|---|---|
| `sub_bass` | 0–1 | 20–60 | Deep sub, kick thump, 808s. **Use this for kick-driven zoom**, not `bass`. |
| `bass` | 0–1 | 60–250 | Bass body, low rhythm |
| `low_mid` | 0–1 | 250–800 | Snare body, low vocals, guitar fundamentals |
| `mid` | 0–1 | 800–4k | Vocals, leads, snare crack |
| `presence` | 0–1 | 4–8k | Attack, consonants, cymbal presence |
| `treble` | 0–1 | 8–16k | Air, shimmer, hi-hat sizzle |

### Percussion Envelopes

Fire at `1.0` on detection and decay each frame. Each detector has independent history and cooldown.

| Uniform | Decay | Source band | Cooldown |
|---|---|---|---|
| `kick` | 5×/s | sub_bass | 150 ms |
| `snare` | 4×/s | low_mid | 150 ms |
| `hihat` | 6×/s | presence + treble | 80 ms |
| `beat` | 3×/s | bass | 200 ms |

Use kick/snare/hihat for sharp single-frame accents. Use `beat` for sustained rhythmic pulses.

### Spectral Flux

Positive-only change: how much each range just increased this frame. Good for flashes, shockwaves, and cuts.

| Uniform | Description |
|---|---|
| `flux_bass` | Bass onset strength |
| `flux_mid` | Mid onset strength |
| `flux_treble` | Treble onset strength |
| `onset` | Combined max of all three flux values |

### Energy & Mood

| Uniform | Description |
|---|---|
| `energy` | Adaptive normalized overall energy. Use for visual size and intensity. |
| `activity` | Energy + flux + transient contribution. Good for gating motion when music is absent. |
| `loudness` | Pre-normalization loudness. Reflects whether the source is quiet or mastered hot. |
| `warmth` | Bass/low-mid spectral balance (0 = treble-heavy, 1 = bass-heavy). |
| `brightness` | Presence/treble spectral balance. Inverse of warmth. |
| `density` | Mid-band density + activity. High on complex harmonic content. |

### Timing

| Uniform | Description |
|---|---|
| `bpm` | Estimated tempo from median of recent beat intervals. Settles after ~4 beats. |
| `beat_phase` | 0→1 ramp through the current beat period. Wraps each beat. Only advances when music is active. |
| `beat_confidence` | Stability of the BPM estimate. Use to suppress beat-sync effects while BPM is settling. |
| `time_val` | Audio-driven clock. Advances faster with higher energy. Frozen during silence. |

### Feedback & Interaction

| Uniform | Type | Description |
|---|---|---|
| `prev_frame` | `sampler2D` | Previous frame's completed output. `hint_default_black`. The feedback loop. |
| `frame` | `int` | Absolute frame counter. Use for per-frame parity, alternating behaviors, rhythm gating. |

### Utility

| Uniform | Type | Description |
|---|---|---|
| `noise_tex` | `sampler2D` | 512×512 seamless Simplex noise (4 octaves, freq 0.04). |
| `rect_size` | `vec2` | Visualizer rect in pixels. Use for aspect correction and pixel-precise drawing. |

### Debug / Threshold

Pushed every frame, only useful for diagnostic shaders.

| Uniform | Description |
|---|---|
| `beat_threshold` | Current dynamic threshold for beat detector |
| `kick_threshold` | Current dynamic threshold for kick detector |
| `snare_threshold` | Current dynamic threshold for snare detector |
| `hihat_threshold` | Current dynamic threshold for hihat detector |
| `peak_00`–`peak_14` | Peak-hold values for the 15 debug meter rows |

---

## Full Uniform Template

```glsl
shader_type canvas_item;

// ── Frequency bands ───────────────────────────────────────────────
uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;

// ── Percussion envelopes ──────────────────────────────────────────
uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;

// ── Spectral flux ─────────────────────────────────────────────────
uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;

// ── Energy / mood ─────────────────────────────────────────────────
uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;

// ── Timing ────────────────────────────────────────────────────────
uniform float beat_phase      : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm             = 120.0;
uniform float time_val        = 0.0;

// ── Feedback ─────────────────────────────────────────────────────
uniform sampler2D prev_frame : hint_default_black, filter_linear, repeat_disable;

// ── Utility ───────────────────────────────────────────────────────
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);
```

Shaders that don't declare a uniform silently ignore it — only declare what you use.

---

## Common Patterns

### Cosine palette (Inigo Quilez)
```glsl
#define TAU 6.28318530718
vec3 palette(float t, vec3 shift) {
	return vec3(0.5) + vec3(0.5) * cos(TAU * (t + shift));
}
// Drive shift with mood: vec3(warmth * 0.15, 0.33, 0.67 + brightness * 0.15)
```

### Seamless polar spiral (integer arms — no atan2 seam)
```glsl
vec2 uv_c = uv - 0.5;
uv_c.x   *= rect_size.x / rect_size.y;
float r   = length(uv_c);
float a   = atan(uv_c.y, uv_c.x);
float arms   = floor(4.0 + bass * 3.0);   // must be integer
float spiral = sin(a * arms + r * 12.0 - time_val * 3.0 + beat_phase * TAU);
spiral = pow(max(spiral, 0.0), 3.0);
```

### Kick-pulse breathing ring
```glsl
float ring_r = 0.15 + energy * 0.08 + sub_bass * 0.06;
float ring   = exp(-abs(length(uv_c) - ring_r) * 50.0);
```

### Onset flash
```glsl
col += vec3(0.25, 0.18, 0.10) * onset;
```

### Post-processing chain
```glsl
col  = col / (1.0 + col);                                                         // Reinhard tonemap
col  = pow(max(col, vec3(0.0)), vec3(0.4545));                                    // gamma
col += (texture(noise_tex, uv * 300.0 + fract(time_val * 0.07)).r - 0.5) * 0.025; // grain
col *= mix(0.5, 1.0, 1.0 - smoothstep(0.3, 1.2, length(uv - 0.5) * 1.8));        // vignette
```

---

## Adding a Shader

1. Create `shaders/your_shader.gdshader`
2. Add an entry to `SHADERS` in `engine/visualizer.gd`:

```gdscript
const SHADERS := [
	{ "path": "res://shaders/cosmic_abyss.gdshader",   "name": "Cosmic Abyss" },
	{ "path": "res://shaders/your_shader.gdshader",    "name": "Your Shader" },
]
```

3. Cycle to it with `E` / `Q` or select it in the Settings window (⚙).

---

## Controls

| Input | Action |
|---|---|
| `E` | Next shader |
| `Q` | Previous shader |
| `S` | Toggle auto-shuffle |
| `F` | Toggle fullscreen |
| `Space` | Play / Pause |
| `Escape` | Stop |


The player bar has Load, ▶/⏸, ⏹, seek bar, ⛶ fullscreen, and ⚙ settings.  
The ⚙ settings window has a **General** tab (shuffle interval, keyboard shortcuts), a **Shaders** tab (shader selector), and a **Debug** tab (live progress bars for all 22+ uniforms).

---

## Project Structure

```
├── engine/
│   ├── audio_analyzer.gd          # Full audio analysis pipeline
│   └── visualizer.gd              # Shader switching, feedback buffer, uniform push
├── shaders/
├── ui/
│   ├── player_ui.gd               # Player bar + floating settings window
│   └── visualizer_ui.gd           # Shader name label overlay
├── main.tscn
├── project.godot
├── GUIDE.md                       # Deep-dive: MilkDrop pipeline, gaps, decisions
└── default.ogg
```

`GUIDE.md` has the full technical breakdown of the MilkDrop rendering pipeline, what makes it feel the way it does, and where Iguana's implementation stands relative to it.

---

## License

MIT License.
