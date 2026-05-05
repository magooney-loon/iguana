# Iguana — MilkDrop-Style Audio Visualizer
`It really licks the eyeballs... yeah.`

Godot 4 audio-reactive shader visualizer with a feedback rendering pipeline. Analyzes audio in real time, extracts frequency, transient, and mood uniforms, and feeds them into a feedback loop that accumulates visual history across frames — the core technique behind MilkDrop.

**Language:** GDScript  
**Renderer:** Forward+ 
**Target Godot:** 4.6

---

## Architecture

```
AudioEffectSpectrumAnalyzer
        ↓
AudioAnalyzer.process()          — runs every frame via AudioSource
        ↓
_push_uniforms()                 — 30+ values pushed to the active ShaderMaterial
        ↓
FeedbackViewport (SubViewport)   — shader renders here (ColorRect with ShaderMaterial)
        ↓
BackbufferViewport (SubViewport) — copies FeedbackViewport output each frame
        ↓
prev_frame uniform               — shader reads last frame from BackbufferViewport
        ↓
PostProcessDisplay (ColorRect)   — reads FeedbackViewport texture, applies
                                   tonemap / gamma / vignette / grain on top
```

**Two-viewport design:** a shader cannot sample its own render target. `FeedbackViewport` renders the current frame; `BackbufferViewport` (later in the scene tree, so rendered second) copies it. Next frame, `prev_frame` is `BackbufferViewport.get_texture()` — the completed previous frame, never the live target.

**Post-process layer:** `post_process.gdshader` sits above the SubViewportContainer and reads the raw feedback texture. It applies tonemap, gamma, vignette, and grain *outside* the feedback loop — so post-processing does not compound or trail.

---

## Project Structure

```
├── engine/
│   ├── audio_analyzer.gd      # Full audio analysis pipeline (FFT → uniforms)
│   ├── audio_source.gd        # AudioStreamPlayer wrapper + crossfade logic
│   ├── keymap.gd              # Rebindable key action registry
│   └── visualizer.gd          # Shader switching, feedback buffer, uniform push
├── shaders/
│   ├── post_process.gdshader  # External tonemap/gamma/grain/vignette layer
│   ├── shader_template.gdshader # Starter template for new shaders
│   └── *.gdshader             # Visualizer shaders (auto-discovered at runtime)
├── ui/
│   ├── player_ui.gd           # Player bar + settings window host
│   ├── settings_ui.gd         # Settings window (General / Post-process / Debug / Keymap)
│   ├── playlist.gd            # Playlist data model
│   ├── playlist_ui.gd         # Playlist panel UI
│   ├── styles_ui.gd           # Shared Theme/StyleBox builders
│   └── notification_ui.gd     # Overlay notification label
├── config.gd                  # Persistent settings (JSON, user://)
├── main.tscn
└── project.godot
```

Shaders are discovered automatically by scanning `res://shaders/` at startup. Any `.gdshader` file with valid `@meta` tags is loaded. See [docs/SHADER_GUIDE.md](docs/SHADER_GUIDE.md) for how to add one.

---

## The Feedback Loop

The MilkDrop aesthetic comes from one thing: every frame is built on top of the previous frame. The previous frame is sampled with a zoom, rotation, and warp displacement, faded slightly, then new geometry is drawn on top.

```glsl
void fragment() {
    vec2 uv = UV;

    // ── 1. FEEDBACK — warp + zoom + rotate previous frame ────────────
    vec2 center = uv - 0.5;
    center.x *= rect_size.x / rect_size.y;   // aspect-correct

    center *= 0.98 - sub_bass * 0.02;        // zoom (compounds into tunnel)

    float rot = 0.007 + energy * 0.008;
    float c = cos(rot), s = sin(rot);
    center = mat2(vec2(c, s), vec2(-s, c)) * center;   // rotate (compounds into spiral)

    vec2 feedback_uv = center;
    feedback_uv.x /= rect_size.x / rect_size.y;
    feedback_uv += 0.5;

    vec2 warp = vec2(
        sin(center.y * 10.0 + time_val * 1.4) * 0.015,
        cos(center.x * 8.0  + time_val * 1.1) * 0.015
    );
    warp *= 1.0 + bass * 2.5 + energy * 1.5;

    vec2 sample_uv  = feedback_uv + warp;
    vec2 edge_d     = min(sample_uv, 1.0 - sample_uv);
    float edge_fade = smoothstep(0.0, 0.04, min(edge_d.x, edge_d.y));

    vec3 trail = texture(prev_frame, sample_uv).rgb;
    trail *= (0.92 + energy * 0.05) * edge_fade;

    // ── 2. GEOMETRY — new audio-reactive shapes ───────────────────────
    vec3 new_col = /* ... */;

    // ── 3. COMPOSITE ─────────────────────────────────────────────────
    vec3 col = trail + new_col;
    col = reinhard(col, loop_reinhard);
    COLOR = vec4(col, 1.0);
}
```

See [docs/SHADER_GUIDE.md](docs/SHADER_GUIDE.md) for the complete guide and [docs/MILKDROP.md](docs/MILKDROP.md) for the conceptual breakdown of why this works.

---

## Per-Shader Post-Processing

Each shader declares its preferred post-processing values in its header. The engine reads these at load time:

```glsl
// @exposure:       1.42
// @tonemap_knee:   0.0
// @gamma:          2.0
// @vignette_dark:  0.30
// @grain_strength: 0.01
// @loop_reinhard:  0.9
```

`loop_reinhard` is applied **inside** the feedback loop (in the shader itself) to prevent trail blow-out. The other five are applied by the external post-process layer. All are tunable live in the Settings window.

## License

AGPL-v3 License.
