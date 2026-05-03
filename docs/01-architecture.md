# Architecture Overview

## What is Iguana?

> *"It really licks the iguana's eyeball!"*

Iguana is a standalone desktop audio visualizer and GDShader preset creator with Steam Workshop support.

- **Visualizer** — captures system audio loopback, renders real-time Milkdrop-style fragment-shader visuals that react to whatever is playing on the OS
- **Preset authoring** — write `.gdshader` files in your editor of choice; Iguana hot-reloads them and auto-generates a parameter panel from the shader's `uniform` declarations
- **Workshop marketplace** — share, discover, and subscribe to community presets via Steam Workshop (free, standard Workshop)

There is no music player, no library, no playlists. Iguana sits next to your player of choice and visualizes it.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Engine | Godot 4.3+ |
| Application Language | GDScript |
| Native Plugin | Rust GDExtension (`gdext`) |
| Audio Capture | `cpal` (Linux PipeWire / Windows WASAPI) + ScreenCaptureKit FFI (macOS) |
| FFT Analysis | `rustfft` + `realfft` |
| Filesystem Watcher | `notify` (Rust) |
| Audio→Render Handoff | `triple_buffer` (lock-free) |
| Shader Language | GDShader (GLSL ES 3.0 dialect) |
| Workshop | GodotSteam GDExtension |
| Distribution | Steam · Flathub · AUR · winget · Homebrew Cask |

---

## Core Pillars

```
┌──────────────────────────────────────────────────────────────────┐
│              Rust GDExtension  (libiguana_audio)                  │
│   SystemAudioCapture · FileWatcher                                │
│   loopback PCM → Hann window → rustfft → bands → beat             │
│   notify watcher → file_changed signal                            │
├──────────────────────────────────────────────────────────────────┤
│                       GDScript Application                        │
│   AudioBridge (autoload)  · PresetLoader (autoload)               │
│   VisualEngine            · BeatDetector                          │
│   ParameterPanel · Workshop · Settings · UI scenes                │
├──────────────────────────────────────────────────────────────────┤
│              GDShader  (preset .gdshader files)                   │
│   Fragment shader on a fullscreen ColorRect                       │
│   Reads bass / mid / treble / beat / time uniforms +              │
│     custom uniforms declared per-preset                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Visualizer

```
[System audio output — any app, any source]
       │
       ▼
[SystemAudioCapture] (Rust GDExtension)
  Linux : PipeWire monitor source (cpal)
  Win   : WASAPI loopback         (cpal)
  macOS : ScreenCaptureKit         (FFI)
  stereo f32 PCM → mono mix, ~60 frames/sec
       │
       ▼
[FFT + band extraction] (rustfft + realfft, audio thread)
  Hann window 1024 → magnitude [512]
  log-scale normalize
  bass / mid / treble scalars
  beat threshold pulse
       │
       ▼  triple_buffer publish
[AudioBridge] (GDScript autoload)
  reads latest frame each _process tick
       │
       ├──► [Settings overlay]    BPM badge, level meters
       │
       └──► [VisualEngine]
             material.set_shader_parameter(...)
             ColorRect renders fullscreen
```

### Preset authoring

```
[Author edits shader.gdshader in their editor of choice]
       │  save
       ▼
[FileWatcher] (Rust, notify) → emits file_changed(path)
       │
       ▼
[PresetLoader] (GDScript)
  ResourceLoader.load(path, "", CACHE_MODE_REPLACE)
       │
       ├──► [VisualEngine]    swap material.shader, no restart
       │
       └──► [ParameterPanel]
             read shader.get_shader_uniform_list()
             diff against current panel
             add/remove sliders to match new uniforms
```

### Workshop

```
[User clicks Publish]
  → screenshot captured (or user-supplied preview.png)
  → preset folder packed: shader.gdshader + manifest.json + preview.png
  → Workshop.upload_preset(folder, existing_id?)
  → GodotSteam createItem → setItemContent → submitItemUpdate
  → published_file_id written back to manifest.json

[User subscribes to a Workshop preset]
  → Steam downloads it to its Workshop content folder
  → GodotSteam emits item_downloaded(folder)
  → Workshop.gd copies into user://presets/<id>/
  → FileWatcher signals new directory
  → PresetLoader.scan() registers it
  → appears in PresetPicker immediately (no restart)
```

---

## Key Design Principles

**Capture anything** — Iguana doesn't play audio. It listens to whatever the OS is already playing — Spotify, a browser, a game, anything.

**Thin native shell** — The Rust GDExtension handles only what the engine can't natively: loopback capture, FFT at audio-thread rate, lock-free handoff to the render thread, filesystem watching. Application logic, UI, and visualization all live in GDScript + GDShader.

**Hot-reload first** — There is no in-app shader editor. Authors use their editor of choice (VS Code with the GLSL extension, Neovim, Godot's own script editor) and save to disk; the running app picks up changes within milliseconds. This avoids reinventing tooling that already exists.

**Self-describing presets** — A preset's parameter panel is generated entirely from the shader's `uniform` declarations and their `hint_range(...)` annotations. There is no separate parameter spec file to keep in sync.

**Uniform preset sandbox** — Every preset, whether bundled, hot-loaded from disk, or Workshop-downloaded, runs the same way: a `Shader` resource bound to a `ShaderMaterial` on a fullscreen `ColorRect`. GDShader has no filesystem, network, or compute access by design — sandboxing is the engine's default.

**WebGL2-equivalent target** — GDShader is GLSL ES 3.0 with sugar. The vast Shadertoy ecosystem ports with light syntax tweaks (see `docs/05-preset-authoring.md` § Porting).

**Workshop is free sharing** — The Workshop integration uses standard Steam Workshop (free subscribe/publish). No paid item monetization.

---

## System Boundaries

| Boundary | Mechanism |
|---|---|
| Audio thread → Main thread | `triple_buffer` (lock-free) |
| GDExtension → GDScript | Class methods + signals (`SystemAudioCapture`, `FileWatcher`) |
| AudioBridge → VisualEngine | Pulled per-frame via `_process` |
| FileWatcher → PresetLoader | Signal `file_changed(path: String)` |
| PresetLoader → VisualEngine | `material.shader = new_shader` |
| Shader ↔ ParameterPanel | `Shader.get_shader_uniform_list()` |
| GodotSteam ↔ Workshop.gd | Singleton `Steam.*` calls + Steam signals |
| Workshop content → Registry | `item_downloaded` signal → PresetLoader.scan() |

---

## Further Reading

| Doc | Topic |
|---|---|
| `02-audio-capture.md` | cpal / ScreenCaptureKit per-platform loopback |
| `03-fft-analysis.md` | FFT pipeline, beat detection, `AudioFrame` contract |
| `04-visualization-engine.md` | ColorRect renderer, hot-reload pipeline |
| `05-preset-authoring.md` | `.gdshader` format, standard + custom uniforms |
| `06-godot-integration.md` | GDExtension class surface, autoloads, GodotSteam |
| `07-project-structure.md` | Module layout |
| `08-platform.md` | Config, shortcuts, distribution channels |
| `09-preset-creator.md` | Auto-generated parameter panel, publishing flow |
