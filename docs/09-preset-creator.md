# Preset Creator

The "creator" in Iguana is a deliberately small surface area. There is no in-app shader editor — authors edit `.gdshader` files in the editor of their choice and Iguana hot-reloads them. What Iguana does provide is the workflow around that:

- **Live preview** — the running visualizer is the preview. Save the shader, see it.
- **Auto-generated parameter panel** — every uniform in the active shader gets a UI control.
- **Per-preset value persistence** — slider changes survive restarts.
- **Workshop publish flow** — package the folder, capture a screenshot, upload to Steam.

The pieces that make this feel like a creator (rather than just "edit a file") are the parameter panel and the publish dialog. Both live in `scripts/`, both inspect the live `Shader` object — there's no separate spec to keep in sync.

---

## Authoring loop

```
1. Copy a bundled preset folder to user://presets/my_preset/
2. Open shader.gdshader in your editor of choice
3. Edit. Save.
   ↓
   FileWatcher → PresetLoader → VisualEngine.swap_shader()
   ParameterPanel.rebuild_from(shader)
4. Tweak sliders/colors/numbers in the in-app panel
   ↓ debounced 200 ms
   values.json saved next to the shader
5. (Optional) capture preview, fill in manifest, click Publish
   ↓
   Workshop.upload_preset()
```

Step 1 has a one-click helper in PresetPicker: **Duplicate**. It copies the selected preset folder, gives the copy a unique id, and reveals the new folder in the OS file explorer.

---

## Parameter panel

`ParameterPanel.gd` reads the shader's uniform list and generates one control per uniform. Standard uniforms (`bass`, `mid`, `treble`, `presence`, `volume`, `beat`, `bpm`, `time_val`, `spectrum`) are filtered out — they're driven by the audio pipeline, not the user.

```gdscript
# scripts/ParameterPanel.gd
extends VBoxContainer

const STANDARD_UNIFORMS := [
    "bass", "mid", "treble", "presence",
    "volume", "beat", "bpm", "time_val", "spectrum",
]

var _material: ShaderMaterial
var _values_path: String = ""
var _save_timer: Timer

func _ready() -> void:
    _save_timer = Timer.new()
    _save_timer.one_shot = true
    _save_timer.wait_time = 0.2
    _save_timer.timeout.connect(_save_values)
    add_child(_save_timer)

func bind(material: ShaderMaterial, preset_folder: String) -> void:
    _material = material
    _values_path = preset_folder + "/values.json"
    rebuild_from(material.shader)

func rebuild_from(shader: Shader) -> void:
    for child in get_children():
        if child != _save_timer:
            child.queue_free()
    var saved_values := _read_values()
    for u in shader.get_shader_uniform_list():
        if u.name in STANDARD_UNIFORMS: continue
        var initial = saved_values.get(u.name, u.hint_string)  # parsed default
        _make_control(u, initial)

func _make_control(u: Dictionary, initial) -> void:
    var row := HBoxContainer.new()
    var label := Label.new()
    label.text = u.name
    row.add_child(label)
    match u.type:
        TYPE_FLOAT:    row.add_child(_float_slider(u, initial))
        TYPE_INT:      row.add_child(_int_slider(u, initial))
        TYPE_BOOL:     row.add_child(_checkbox(u, initial))
        TYPE_VECTOR3:  row.add_child(_color_picker(u, initial, false))
        TYPE_VECTOR4:  row.add_child(_color_picker(u, initial, true))
        _:             row.add_child(_fallback_text(u, initial))
    add_child(row)

func _on_value_changed(name: String, value) -> void:
    _material.set_shader_parameter(name, value)
    _save_timer.start()  # debounced persist

func _read_values() -> Dictionary:
    if not FileAccess.file_exists(_values_path): return {}
    var text := FileAccess.open(_values_path, FileAccess.READ).get_as_text()
    var parsed = JSON.parse_string(text)
    return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _save_values() -> void:
    var dict := {}
    for u in _material.shader.get_shader_uniform_list():
        if u.name in STANDARD_UNIFORMS: continue
        dict[u.name] = _material.get_shader_parameter(u.name)
    var f := FileAccess.open(_values_path, FileAccess.WRITE)
    if f: f.store_string(JSON.stringify(dict, "  "))
```

The interesting bit: `Shader.get_shader_uniform_list()` returns a Godot `Dictionary` per uniform with `name`, `type`, `hint`, `hint_string`, `usage` — enough to choose a control type and a min/max range without any parallel spec file.

`scripts/lib/shader_uniforms.gd` factors out the parsing of `hint_range(min, max[, step])` strings (Godot returns them as a comma-separated string via `hint_string`), so `ParameterPanel.gd` itself stays focused on UI.

### Reset to defaults

A "Reset" button at the bottom of the panel deletes `values.json` and rebuilds the panel — every control returns to the value declared in the shader source.

### Hot-reload diff behavior

When the shader is hot-reloaded:

1. `rebuild_from` re-reads the uniform list.
2. Saved values from `values.json` are reapplied for any uniform whose **name and type** match.
3. Removed uniforms vanish from the panel; their saved values are pruned on the next save.
4. Newly added uniforms appear with their declared default.

This means renaming a uniform resets that one slider — fine, expected.

---

## Per-preset value file

```
user://presets/my_preset/
├── shader.gdshader
├── manifest.json
├── values.json          # ← written by ParameterPanel
└── preview.png
```

```json
// values.json
{
  "zoom_amount": 0.62,
  "color_shift": 0.41,
  "tint_color": [0.92, 0.40, 0.85, 1.0]
}
```

`values.json` is **not** uploaded to Workshop — it's per-user state. The Workshop package contains only the shader, manifest, and preview. Subscribers start with the shader's declared defaults; if they like specific tweaks, those land in their own `values.json`.

---

## Preview screenshot capture

`UploadDialog.gd` includes a "Capture preview" button that takes the current viewport, downsamples it to 620×620 (Workshop's recommended preview size), and writes `preview.png` into the preset folder.

```gdscript
func capture_preview() -> Error:
    var img := get_viewport().get_texture().get_image()
    img.resize(620, 620, Image.INTERPOLATE_LANCZOS)
    return img.save_png(_preset_folder + "/preview.png")
```

If the user supplies their own `preview.png` (drops it into the folder), the file watcher picks it up and the dialog uses that without re-capturing.

---

## Publish flow

```
[User opens UploadDialog for a preset folder]
   │
   ▼
[Dialog populates fields from manifest.json]
   name, description, tags, preview thumbnail
   │
   ▼
[User edits, hits "Publish"]
   │
   ├──► first time: Workshop.upload_preset(folder)
   │      → Steam.createItem
   │      → on item_created: write workshop_id to manifest.json
   │      → Steam.startItemUpdate → setItemContent → submitItemUpdate
   │
   └──► subsequent updates: Workshop.upload_preset(folder, manifest.workshop_id)
          → skip createItem, go straight to startItemUpdate
   │
   ▼
[on item_updated success]
   Toast: "Published! Open in Workshop?"
   Steam.activateGameOverlayToWebPage(item_url)
```

Validation before sending to Steam:

| Check | Failure message |
|---|---|
| `shader.gdshader` compiles | "Shader has compile errors. Fix before publishing." |
| `manifest.json` schema | "Manifest is missing required field: {field}" |
| `preview.png` exists | "No preview image. Capture one first?" (warning, not blocking) |
| Preset folder size < 8 MB | "Preset is too large for Workshop ({size})." |
| Tags ≤ 30 chars each, ≤ 100 total | "Tags must be 30 characters or less; max 100 total characters." |

---

## Discovery flow (subscribing)

```
[User opens WorkshopPanel]
   │
   ▼
Workshop.fetch_workshop_items(page = 1)
   ├──► grid populates with thumbnails, titles, vote counts
   ▼
[User clicks Subscribe on an item]
   │
   ▼
Workshop.subscribe_and_download(item_id)
   ├──► Steam downloads to its UGC folder
   ▼
on item_downloaded:
   copy → user://presets/ws_<id>/
   FileWatcher fires
   PresetLoader.scan() registers the new preset
   PresetPicker shows it (no app restart)
```

Subscribed presets carry a Workshop badge in `PresetPicker` and an "Unsubscribe" option in their context menu (calls `Steam.unsubscribeItem`).

Auto-update: when the Steam client downloads an updated version of a subscribed item, `item_downloaded` fires again with the same `item_id` — the existing folder is overwritten, the file watcher signals the changed shader, the active preset hot-reloads if it happens to be that one. No restart, no UI prompt.

---

## What this layer does **not** do

- **No GLSL editor.** Authors use VS Code, Neovim, the Godot editor's script panel, or whatever they prefer. The hot-reload pipeline ensures the loop is tight.
- **No GLSL syntax help.** GLSL LSPs in external editors handle that.
- **No version control.** Workshop tracks updates per-item; for finer-grained history, authors use git on their preset folder.
- **No preset gallery scraping outside Workshop.** Iguana doesn't fetch from godotshaders.com or Shadertoy at runtime — too much licensing risk. Users copy/paste manually.
- **No collaboration / multi-user editing.** Single-author per preset.
