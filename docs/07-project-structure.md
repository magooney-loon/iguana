# Project Structure

The repository at-a-glance and what each module is for. Anything not listed here is either generated or third-party.

---

## Top level

```
iguana/
├── project.godot                  # Godot project manifest
├── icon.svg                       # App icon
├── export_presets.cfg             # Godot export presets (per platform)
├── steam_appid.txt                # git-ignored — your Steam App ID for dev
├── INIT.md                        # bootstrap guide
├── LICENSE
├── docs/                          # design documentation (this directory)
├── scenes/                        # .tscn files
├── scripts/                       # .gd files (autoloads + scene scripts)
├── shaders/                       # bundled .gdshader presets
├── presets/                       # bundled preset folders (manifest + shader)
├── native/                        # Rust GDExtension source
├── addons/                        # GDExtension binaries + third-party plugins
└── build/                         # exporter output (git-ignored)
```

---

## `scenes/`

```
scenes/
├── Main.tscn                      # root scene — autoloads + Visualizer instance
├── Visualizer.tscn                # ColorRect + ShaderMaterial + CanvasLayer
└── ui/
    ├── PresetPicker.tscn          # slide-in preset list
    ├── ParameterPanel.tscn        # auto-generated sliders for current preset
    ├── SettingsPanel.tscn         # audio device, beat sensitivity, FPS toggle
    ├── WorkshopPanel.tscn         # browse + my uploads (Steam-only)
    ├── UploadDialog.tscn          # title / description / tags / preview
    └── ErrorOverlay.tscn          # shader compile errors + capture errors
```

**Rule**: scenes contain layout and node references only. All logic lives in the matching script.

---

## `scripts/`

```
scripts/
├── Main.gd                        # wires autoloads to scene at startup
├── AudioBridge.gd                 # AUTOLOAD — owns SystemAudioCapture
├── PresetLoader.gd                # AUTOLOAD — owns FileWatcher, scans presets
├── Settings.gd                    # AUTOLOAD — ConfigFile persistence
├── VisualEngine.gd                # script attached to Visualizer's ColorRect
├── BeatDetector.gd                # beat-event → envelope smoothing
├── ParameterPanel.gd              # generates UI from shader uniform list
├── PresetPicker.gd                # list + thumbnails
├── SettingsPanel.gd               # binds UI to Settings autoload
├── Workshop.gd                    # GodotSteam UGC wrapper
├── UploadDialog.gd                # screenshot capture + Workshop.upload_preset
├── ErrorOverlay.gd                # subscribes to RenderingServer error signal
└── lib/
    ├── manifest_schema.gd         # validate manifest.json
    └── shader_uniforms.gd         # parse Shader.get_shader_uniform_list() into panel descriptors
```

### Autoload responsibilities

| Autoload | Owns | Reads from | Writes to |
|---|---|---|---|
| `AudioBridge` | `SystemAudioCapture` instance | — | logs only |
| `PresetLoader` | `FileWatcher`, preset registry | `user://presets/` | — |
| `Settings` | `ConfigFile` | `user://settings.cfg` | `user://settings.cfg` |

### Non-autoload script responsibilities

| Script | Lives on | Lifetime |
|---|---|---|
| `VisualEngine.gd` | `Visualizer/ColorRect` | scene-bound |
| `BeatDetector.gd` | child of `Visualizer` | scene-bound |
| `ParameterPanel.gd` | `CanvasLayer/ParameterPanel` | scene-bound |
| `Workshop.gd` | child of `Main` (Steam-gated) | scene-bound |

Workshop is **not** an autoload because non-Steam builds never instantiate it.

---

## `shaders/`

Bundled shaders that ship inside the PCK. Distinct from user-installed presets in `user://presets/` — these load via `res://` paths and are read-only at runtime.

```
shaders/
├── plasma.gdshader
├── nebula.gdshader
├── alien_core.gdshader
├── waveform_ring.gdshader
├── spectrum_bars.gdshader
├── ripple_grid.gdshader
└── lissajous.gdshader
```

The matching `presets/` folders give each one its `manifest.json` + `preview.png` so the bundled set behaves identically to user/Workshop presets in `PresetPicker`.

---

## `presets/`

Bundled preset folders. One subdirectory per preset, matching shader by name:

```
presets/
├── plasma/
│   ├── shader.gdshader            # symlink (or duplicate) to ../shaders/plasma.gdshader
│   ├── manifest.json
│   └── preview.png
├── nebula/
│   ├── shader.gdshader
│   ├── manifest.json
│   └── preview.png
└── …
```

At first launch, `PresetLoader` copies the bundled set into `user://presets/` so users have something to start from. Bundled presets carry `"bundled": true` in their manifest so `PresetPicker` can flag them and prevent destructive edits.

---

## `native/`

```
native/
└── iguana_audio/
    ├── Cargo.toml
    ├── build.rs                   # compiles the macOS ObjC bridge via cc
    └── src/
        ├── lib.rs                 # ExtensionLibrary, class registration
        ├── audio/
        │   ├── mod.rs             # SystemAudioCapture node
        │   ├── linux.rs           # PipeWire monitor source picker
        │   ├── windows.rs         # WASAPI loopback
        │   └── macos/
        │       ├── mod.rs         # FFI declarations
        │       └── bridge.m       # ScreenCaptureKit ObjC bridge
        ├── fft.rs                 # window + FFT + normalize + bands
        ├── beat.rs                # BeatDetector (event-only)
        ├── frame.rs               # AudioFrame struct
        └── watcher.rs             # FileWatcher node
```

`build.rs` compiles `bridge.m` only on macOS targets. Linux and Windows builds skip it entirely.

---

## `addons/`

```
addons/
├── iguana_audio/                  # built artifacts of native/iguana_audio
│   ├── iguana_audio.gdextension
│   └── bin/
│       ├── libiguana_audio.linux.x86_64.so
│       ├── iguana_audio.windows.x86_64.dll
│       └── libiguana_audio.macos.universal.dylib
└── godotsteam/                    # third-party — not in version control by default
    ├── godotsteam.gdextension
    ├── bin/...
    └── sdk/...
```

`addons/godotsteam/` is added to `.gitignore` — the binary is large and per-platform; CI fetches it during the Steam build job. Local devs install it once per the GodotSteam docs.

---

## `build/`

Exporter output. Always git-ignored.

```
build/
├── linux/
│   ├── iguana.x86_64
│   └── iguana.pck                 # if not embedded
├── windows/
│   └── iguana.exe
├── macos/
│   └── Iguana.app/
└── flatpak/
    └── …
```

---

## File naming conventions

| Kind | Convention | Examples |
|---|---|---|
| Scene | `PascalCase.tscn` | `PresetPicker.tscn` |
| Script | `PascalCase.gd` | `AudioBridge.gd` |
| Shader | `snake_case.gdshader` | `waveform_ring.gdshader` |
| Preset folder | `snake_case` | `plasma_wave/` |
| Workshop folder | `ws_<id>` | `ws_3284191/` (set by `Workshop.gd`) |
| Rust module | `snake_case.rs` | `audio/linux.rs` |

---

## What lives where — quick lookup

| Topic | File(s) |
|---|---|
| Audio capture impl | `native/iguana_audio/src/audio/*` |
| FFT impl | `native/iguana_audio/src/fft.rs` |
| Beat detection (native) | `native/iguana_audio/src/beat.rs` |
| Beat envelope (smoothing) | `scripts/BeatDetector.gd` |
| AudioFrame schema | `native/iguana_audio/src/frame.rs` + `docs/03-fft-analysis.md` |
| Hot-reload | `native/iguana_audio/src/watcher.rs` + `scripts/PresetLoader.gd` |
| Standard uniforms | `scripts/VisualEngine.gd` |
| Parameter panel generation | `scripts/ParameterPanel.gd` + `scripts/lib/shader_uniforms.gd` |
| Workshop browse / upload | `scripts/Workshop.gd` |
| Settings persistence | `scripts/Settings.gd` |
| Capture failure UX | `scripts/AudioBridge.gd` + `scripts/ErrorOverlay.gd` |
| Shader compile error UX | `scripts/ErrorOverlay.gd` |
