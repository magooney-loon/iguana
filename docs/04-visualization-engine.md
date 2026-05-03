# Visualization Engine

The visualizer is, deliberately, very small. A fullscreen `ColorRect` with a `ShaderMaterial`, an `_process` tick that pushes audio uniforms into the material, and a hot-reload pipe that swaps the shader when the underlying file changes on disk.

There is no scene graph, no preset framework, no plugin system. The shader **is** the preset.

---

## Scene layout

```
Main (Node)
├── AudioBridge        (autoload — see §03)
├── PresetLoader       (autoload — file watcher + scan)
├── Settings           (autoload — ConfigFile)
└── Visualizer         (instance of Visualizer.tscn)
    ├── ColorRect      (anchor = full_rect, ShaderMaterial bound)
    └── CanvasLayer
        ├── PresetPicker
        ├── ParameterPanel
        ├── SettingsPanel
        └── WorkshopPanel
```

`Visualizer.tscn` is the only thing that owns rendering surfaces. Every UI element is in a `CanvasLayer` above it so the shader fills the whole window unobstructed when the UI auto-hides.

---

## VisualEngine.gd

The hot path. Runs every `_process` tick, reads the latest `AudioFrame`, pushes uniforms into the material.

```gdscript
# scripts/VisualEngine.gd
extends ColorRect

@onready var beat_detector: Node = $BeatDetector
var _time: float = 0.0
var _bins_image: Image
var _bins_texture: ImageTexture

func _ready() -> void:
    # Texture for the full FFT spectrum (sampler2D in shaders that want it)
    _bins_image = Image.create(512, 1, false, Image.FORMAT_RF)
    _bins_texture = ImageTexture.create_from_image(_bins_image)
    set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
    _time += delta
    var frame := AudioBridge.get_frame()
    if frame.is_empty():
        return

    var beat := beat_detector.process(frame.bass, frame.beat, delta)

    if material is ShaderMaterial:
        material.set_shader_parameter("bass",     frame.bass)
        material.set_shader_parameter("mid",      frame.mid)
        material.set_shader_parameter("treble",   frame.treble)
        material.set_shader_parameter("presence", frame.presence)
        material.set_shader_parameter("volume",   frame.volume)
        material.set_shader_parameter("beat",     beat)
        material.set_shader_parameter("bpm",      frame.bpm)
        material.set_shader_parameter("time_val", _time)

        # Full spectrum — only update the texture if the shader actually samples it
        if material.shader and _shader_samples_bins(material.shader):
            _bins_image.set_data(512, 1, false, Image.FORMAT_RF, frame.bins.to_byte_array())
            _bins_texture.update(_bins_image)
            material.set_shader_parameter("spectrum", _bins_texture)

func swap_shader(new_shader: Shader) -> void:
    material.shader = new_shader

func _shader_samples_bins(shader: Shader) -> bool:
    for u in shader.get_shader_uniform_list():
        if u.name == "spectrum":
            return true
    return false
```

The `_shader_samples_bins` check skips the per-frame `Image.set_data` upload when no shader needs it. This matters — uploading a 512-float texture every frame is ~2 ms on slower GPUs.

---

## Standard uniforms

Every preset can reference these. They're always pushed; if the shader doesn't declare them, Godot silently no-ops the `set_shader_parameter` call.

| Uniform | Type | Range | Description |
|---|---|---|---|
| `bass` | `float` | 0..1 | 60–250 Hz energy |
| `mid` | `float` | 0..1 | 250–4000 Hz energy |
| `treble` | `float` | 0..1 | 4000–20000 Hz energy |
| `presence` | `float` | 0..1 | 4–8 kHz sub-band (vocals/cymbals) |
| `volume` | `float` | 0..1 | Overall RMS |
| `beat` | `float` | 0..1 | Beat envelope (decays between beats) |
| `bpm` | `float` | 0..200 | Estimated tempo, 0 if unknown |
| `time_val` | `float` | 0..∞ | Seconds since launch |
| `spectrum` | `sampler2D` | — | 512×1 R32F, full magnitude spectrum |

`spectrum` is opt-in by declaration: `uniform sampler2D spectrum;`. When declared, `VisualEngine` updates the texture each frame.

See `docs/05-preset-authoring.md` for usage examples.

---

## Hot-reload pipeline

```
[author saves shader.gdshader]
    │
    ▼
[FileWatcher (Rust GDExtension)]   notify backend
    debounce 50 ms (filesystems often emit multiple events per save)
    │
    ▼  signal file_changed(path: String)
[PresetLoader.gd (autoload)]
    if path is the active preset's shader:
        var shader := ResourceLoader.load(
            path, "Shader", ResourceLoader.CACHE_MODE_REPLACE
        )
        if shader.is_valid():
            VisualEngine.swap_shader(shader)
            ParameterPanel.rebuild_from(shader)
        else:
            ErrorOverlay.show(shader_compile_error_text)
```

`CACHE_MODE_REPLACE` is essential — without it, Godot returns the cached shader and ignores the on-disk change.

```gdscript
# scripts/PresetLoader.gd
extends Node

const PRESETS_DIR := "user://presets"

signal preset_list_changed(presets: Array[Dictionary])
signal active_preset_reloaded(shader: Shader)

var _watcher: FileWatcher
var _active_path: String = ""
var _presets: Array[Dictionary] = []

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(PRESETS_DIR)
    _watcher = FileWatcher.new()
    add_child(_watcher)
    _watcher.watch(PRESETS_DIR)
    _watcher.file_changed.connect(_on_file_changed)
    scan()

func scan() -> Array[Dictionary]:
    _presets.clear()
    var dir := DirAccess.open(PRESETS_DIR)
    if dir == null:
        return _presets
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if dir.current_is_dir() and not name.begins_with("."):
            var folder := PRESETS_DIR + "/" + name
            var shader_path := folder + "/shader.gdshader"
            var manifest_path := folder + "/manifest.json"
            if FileAccess.file_exists(shader_path):
                _presets.append({
                    "id": name,
                    "shader": shader_path,
                    "manifest": _read_manifest(manifest_path),
                })
        name = dir.get_next()
    preset_list_changed.emit(_presets)
    return _presets

func load_preset(id: String) -> void:
    var entry := _presets.filter(func(p): return p.id == id).front()
    if entry == null: return
    _active_path = entry.shader
    var shader := ResourceLoader.load(_active_path, "Shader",
                                      ResourceLoader.CACHE_MODE_REPLACE) as Shader
    if shader:
        active_preset_reloaded.emit(shader)

func _on_file_changed(path: String) -> void:
    # Re-scan if a manifest or directory changed
    if path.ends_with("manifest.json") or DirAccess.dir_exists_absolute(path):
        scan()
        return
    # Hot-reload if it's the active shader
    if path == _active_path:
        var shader := ResourceLoader.load(_active_path, "Shader",
                                          ResourceLoader.CACHE_MODE_REPLACE) as Shader
        if shader:
            active_preset_reloaded.emit(shader)

func _read_manifest(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var text := FileAccess.open(path, FileAccess.READ).get_as_text()
    var parsed = JSON.parse_string(text)
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
```

`Main.gd` wires `active_preset_reloaded` to `VisualEngine.swap_shader` and `ParameterPanel.rebuild_from` once at startup.

---

## Shader compile error handling

When `ResourceLoader.load` returns a shader that failed to compile, Godot logs the error to stdout but the `Shader` object still exists in a degraded state. To surface errors to the user:

1. Hook `RenderingServer.shader_compile_error` (Godot 4.3+) — fires per failed shader compilation.
2. Capture the error text and display it in an `ErrorOverlay` (a `RichTextLabel` in the CanvasLayer).
3. Keep the previous valid shader bound to the material — don't blank the screen on every typo.

```gdscript
# scripts/ErrorOverlay.gd
extends RichTextLabel

func _ready() -> void:
    visible = false
    RenderingServer.shader_compile_error.connect(_on_compile_error)

func _on_compile_error(shader_rid: RID, error: String) -> void:
    text = "[color=red]Shader error:[/color]\n" + error
    visible = true
    # Auto-hide after the next successful compile of the same RID
```

If `RenderingServer.shader_compile_error` is not wired in your Godot version, fall back to scraping `OS.execute` on the script's stderr — but the signal is the supported path going forward.

---

## Frame budget

| Stage | Target | Notes |
|---|---|---|
| `AudioBridge.get_frame()` | < 5 µs | atomic triple-buffer read + dict construct |
| `BeatDetector.process()` | < 5 µs | float math |
| 8× `set_shader_parameter` | ~10 µs | constant-time per call |
| Spectrum texture upload (when used) | < 2 ms | 512 floats, GPU dependent |
| Shader render | dominant | 1–4 ms typical for fullscreen fragment shaders |

At 60 fps, the entire frame must fit in 16.6 ms. The CPU-side work above is comfortably under 1 ms; the rest belongs to the shader. Preset authors who blow the budget see frame drops; the engine doesn't try to police them (`05-preset-authoring.md` includes guidance).

---

## Multi-pass / feedback presets

Some shaders want a previous-frame texture (feedback loops, blurs that accumulate over time). Godot supports this via `SubViewport` — render the shader into a viewport, sample its texture in the next frame.

V1 keeps the single-pass `ColorRect` path as the default. Multi-pass is a future extension: a preset opts in by declaring `// @passes 2` in a header comment, and `VisualEngine` swaps in a `SubViewport` chain. Out of scope for the initial release; flag in M9+ planning.

---

## What this layer does **not** do

- **No preset DSL.** Presets are plain GDShader files. No Three.js-style preset interface, no JS modules.
- **No GPU resource budgeting.** Fragment shaders on `canvas_item` materials have no SSBOs, no compute — the worst a preset can do is run slow.
- **No transitions between presets.** Switching is instant. Crossfade is a future polish item.
- **No per-preset audio routing.** Every preset gets the same `AudioFrame`; preset-specific filtering happens inside the shader.
