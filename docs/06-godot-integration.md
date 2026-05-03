# Godot Integration

This doc covers everything that crosses the Godot / native boundary:

- The Rust GDExtension crate (`iguana_audio`) — what classes it registers, what methods/signals each exposes
- Autoloads and the high-level GDScript surface
- GodotSteam integration for Workshop
- The shape of the addon directory on disk

---

## Rust GDExtension — `iguana_audio`

A single crate, two registered classes.

### Cargo.toml

```toml
[package]
name    = "iguana_audio"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
godot         = "0.2"
cpal          = "0.15"
rustfft       = "6"
realfft       = "3"
notify        = "6"
triple_buffer = "8"
rubato        = "0.15"   # resampling when device rate ≠ 48 kHz
crossbeam     = "0.8"
anyhow        = "1"

[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.10"
objc2          = "0.5"
objc2-foundation = "0.2"

[target.'cfg(target_os = "macos")'.build-dependencies]
cc = "1"   # compiles the ObjC bridge .m file
```

### Crate skeleton

```rust
// native/iguana_audio/src/lib.rs
use godot::prelude::*;

mod audio;     // SystemAudioCapture
mod watcher;   // FileWatcher
mod fft;
mod beat;

struct IguanaAudio;

#[gdextension]
unsafe impl ExtensionLibrary for IguanaAudio {}

// audio::SystemAudioCapture and watcher::FileWatcher are exported
// via #[derive(GodotClass)] in their own modules.
```

### `SystemAudioCapture`

Owns the audio thread, the FFT pipeline, the triple buffer.

```rust
// native/iguana_audio/src/audio/mod.rs (excerpt)
use godot::prelude::*;
use std::sync::Arc;

#[derive(GodotClass)]
#[class(base=Node)]
pub struct SystemAudioCapture {
    base: Base<Node>,
    consumer: Option<triple_buffer::Output<AudioFrame>>,
    thread: Option<std::thread::JoinHandle<()>>,
    stop_flag: Arc<std::sync::atomic::AtomicBool>,
}

#[godot_api]
impl SystemAudioCapture {
    #[signal]
    fn capture_failed(reason: GString);

    #[func]
    fn start(&mut self) -> bool { /* spawn audio thread */ true }

    #[func]
    fn stop(&mut self) { /* … */ }

    #[func]
    fn list_devices(&self) -> PackedStringArray { /* … */ PackedStringArray::new() }

    #[func]
    fn set_device(&mut self, name: GString) { /* … */ }

    #[func]
    fn is_capturing(&self) -> bool { self.thread.is_some() }

    #[func]
    fn set_beat_sensitivity(&mut self, sens: f32) { /* … */ }

    #[func]
    fn set_beat_cooldown_ms(&mut self, ms: u32) { /* … */ }

    /// Returns the latest AudioFrame as a Dictionary (see docs/03-fft-analysis.md).
    /// Returns an empty Dictionary before capture has produced its first frame.
    #[func]
    fn get_frame(&mut self) -> Dictionary {
        let Some(consumer) = self.consumer.as_mut() else { return Dictionary::new(); };
        let f = consumer.read();
        let mut d = Dictionary::new();
        d.insert("bins",          PackedFloat32Array::from(&f.bins[..]));
        d.insert("bass",          f.bass);
        d.insert("mid",           f.mid);
        d.insert("treble",        f.treble);
        d.insert("presence",      f.presence);
        d.insert("volume",        f.volume);
        d.insert("beat",          f.beat);
        d.insert("bpm",           f.bpm);
        d.insert("bpm_confidence",f.bpm_confidence);
        d.insert("timestamp_us",  f.timestamp_us);
        d
    }
}
```

The full implementations of `audio`, `fft`, `beat`, and the macOS ObjC bridge are detailed in `02-audio-capture.md` and `03-fft-analysis.md`.

### `FileWatcher`

A thin wrapper around `notify` that Godot can use as a `Node`. Debounces (50 ms) so that editor-saves which emit several events per file produce one signal.

```rust
// native/iguana_audio/src/watcher.rs (excerpt)
use godot::prelude::*;
use notify::{RecommendedWatcher, RecursiveMode, Watcher, EventKind};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[derive(GodotClass)]
#[class(base=Node)]
pub struct FileWatcher {
    base: Base<Node>,
    watcher: Option<RecommendedWatcher>,
    rx: Option<mpsc::Receiver<notify::Result<notify::Event>>>,
    last_emit: std::collections::HashMap<String, Instant>,
}

#[godot_api]
impl FileWatcher {
    #[signal]
    fn file_changed(path: GString);

    #[func]
    fn watch(&mut self, path: GString) -> bool {
        let (tx, rx) = mpsc::channel();
        let mut w = match notify::recommended_watcher(tx) {
            Ok(w) => w, Err(_) => return false,
        };
        let resolved = ProjectSettings::singleton().globalize_path(path).to_string();
        if w.watch(std::path::Path::new(&resolved), RecursiveMode::Recursive).is_err() {
            return false;
        }
        self.watcher = Some(w);
        self.rx = Some(rx);
        true
    }

    fn process(&mut self, _delta: f64) {
        let Some(rx) = self.rx.as_ref() else { return; };
        while let Ok(Ok(event)) = rx.try_recv() {
            if !matches!(event.kind, EventKind::Modify(_) | EventKind::Create(_)) { continue; }
            for p in event.paths {
                let key = p.to_string_lossy().into_owned();
                let now = Instant::now();
                let recent = self.last_emit.get(&key).map(|t| now.duration_since(*t) < Duration::from_millis(50)).unwrap_or(false);
                if recent { continue; }
                self.last_emit.insert(key.clone(), now);
                self.base_mut().emit_signal("file_changed".into(), &[GString::from(&key).to_variant()]);
            }
        }
    }
}

#[godot_api]
impl INode for FileWatcher {
    fn process(&mut self, delta: f64) { self.process(delta); }
}
```

`ProjectSettings.globalize_path()` resolves `user://...` and `res://...` to absolute filesystem paths that `notify` can hand to the OS.

### Manifest

```ini
; addons/iguana_audio/iguana_audio.gdextension
[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.3
reloadable = false

[libraries]
linux.x86_64    = "res://addons/iguana_audio/bin/libiguana_audio.linux.x86_64.so"
windows.x86_64  = "res://addons/iguana_audio/bin/iguana_audio.windows.x86_64.dll"
macos           = "res://addons/iguana_audio/bin/libiguana_audio.macos.universal.dylib"
```

`reloadable = false` because cpal opens audio devices that don't survive a hot-reload of the extension. Editor restart on Rust changes is the supported flow.

### Build artifacts

```sh
# Linux
cargo build --release --target x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libiguana_audio.so \
   addons/iguana_audio/bin/libiguana_audio.linux.x86_64.so

# Windows (cross from Linux via mingw, or native via MSVC)
cargo build --release --target x86_64-pc-windows-msvc
cp target/x86_64-pc-windows-msvc/release/iguana_audio.dll \
   addons/iguana_audio/bin/iguana_audio.windows.x86_64.dll

# macOS (build per arch, then lipo)
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create \
   target/x86_64-apple-darwin/release/libiguana_audio.dylib \
   target/aarch64-apple-darwin/release/libiguana_audio.dylib \
   -output addons/iguana_audio/bin/libiguana_audio.macos.universal.dylib
```

A `scripts/build_extension.sh` (created in M1) wraps these for the active platform.

---

## GDScript surface

### Autoloads

Three singletons registered in `project.godot` (`[autoload]` block — see `INIT.md`):

| Autoload | Script | Purpose |
|---|---|---|
| `AudioBridge` | `scripts/AudioBridge.gd` | Owns the `SystemAudioCapture` instance; everyone reads frames through it |
| `PresetLoader` | `scripts/PresetLoader.gd` | Owns the `FileWatcher`; scans presets, hot-reloads on file change |
| `Settings` | `scripts/Settings.gd` | Persists user choices (audio device, beat sensitivity, FPS toggle) via `ConfigFile` |

### AudioBridge.gd

```gdscript
# scripts/AudioBridge.gd
extends Node

var _capture: SystemAudioCapture

func _ready() -> void:
    _capture = SystemAudioCapture.new()
    add_child(_capture)
    _capture.capture_failed.connect(_on_capture_failed)
    var device: String = Settings.get_value("audio", "device", "")
    if device != "":
        _capture.set_device(device)
    _capture.start()

func get_frame() -> Dictionary:
    return _capture.get_frame()

func list_devices() -> PackedStringArray:
    return _capture.list_devices()

func set_device(name: String) -> void:
    _capture.set_device(name)
    Settings.set_value("audio", "device", name)

func _on_capture_failed(reason: String) -> void:
    var msg := _resolve_error(reason)
    ErrorOverlay.show(msg)

func _resolve_error(code: String) -> String:
    match code:
        "no_devices":           return "No audio output detected."
        "permission_denied":    return "Iguana needs Screen Recording permission for audio capture on macOS."
        "unsupported_os":       return "Iguana requires macOS 13+ for audio capture."
        "device_disconnected":  return "Audio device disconnected. Reconnecting…"
        "format_unsupported":   return "Unsupported audio format."
        _:                       return "Audio capture error: " + code
```

### Settings.gd

```gdscript
# scripts/Settings.gd
extends Node

const PATH := "user://settings.cfg"

var _config: ConfigFile = ConfigFile.new()

func _ready() -> void:
    _config.load(PATH)   # silently no-ops on first run

func get_value(section: String, key: String, default = null):
    return _config.get_value(section, key, default)

func set_value(section: String, key: String, value) -> void:
    _config.set_value(section, key, value)
    _config.save(PATH)
```

### Main.gd

Wires the autoloads to the scene at startup. Trivial — see `04-visualization-engine.md` for the visualizer wiring and `09-preset-creator.md` for parameter panel wiring.

---

## GodotSteam — Workshop

GodotSteam ships as a GDExtension (no custom editor build). The `Steam` singleton it registers is available globally once the addon is on disk and `steam_appid.txt` is at the project root.

### Lifecycle

```gdscript
# scripts/Workshop.gd
extends Node

signal item_downloaded(preset_path: String)
signal upload_complete(item_id: int)
signal upload_failed(reason: String)

var _enabled: bool = false

func _ready() -> void:
    _enabled = Steam.isSteamRunning()
    if not _enabled:
        return
    Steam.ugc_query_completed.connect(_on_query_done)
    Steam.item_downloaded.connect(_on_item_downloaded)
    Steam.item_updated.connect(_on_item_updated)
    Steam.item_created.connect(_on_item_created)

func is_available() -> bool:
    return _enabled
```

Every Workshop UI element gates on `Workshop.is_available()`. Non-Steam builds (Flathub, AUR, winget, Homebrew) hide the Workshop tab entirely.

### Browse

```gdscript
func fetch_workshop_items(page: int = 1) -> void:
    Steam.queryAllUGC(
        page,
        Steam.UGC_MATCHING_UGC_TYPE_ITEMS,
        Steam.UGC_QUERY_RANKED_BY_VOTE
    )

func _on_query_done(handle: int, result: int, results_returned: int,
                    total_matching: int, cached: bool) -> void:
    var items: Array[Dictionary] = []
    for i in results_returned:
        items.append(Steam.getQueryUGCResult(handle, i))
    Steam.releaseQueryUGCRequest(handle)
    # emit to WorkshopPanel UI
```

### Subscribe / download

```gdscript
func subscribe_and_download(item_id: int) -> void:
    Steam.subscribeItem(item_id)
    # Download starts automatically; _on_item_downloaded fires when complete

func _on_item_downloaded(result: int, app_id: int, item_id: int) -> void:
    if result != Steam.RESULT_OK: return
    var info := Steam.getItemInstallInfo(item_id)
    var src: String = info["folder"]
    var dst := "user://presets/ws_%d/" % item_id
    DirAccess.make_dir_recursive_absolute(dst)
    _copy_dir(src, dst)
    item_downloaded.emit(dst)
```

### Upload

```gdscript
var _pending_preset_path: String = ""

func upload_preset(preset_path: String, existing_id: int = 0) -> void:
    _pending_preset_path = preset_path
    if existing_id > 0:
        _begin_update(existing_id)
    else:
        Steam.createItem(Steam.getAppID(),
                         Steam.WORKSHOP_FILE_TYPE_COMMUNITY)
        # Wait for item_created signal → _begin_update

func _on_item_created(result: int, item_id: int, accept_tos: bool) -> void:
    if result != Steam.RESULT_OK:
        upload_failed.emit("create_failed: %d" % result); return
    _write_workshop_id(item_id)
    _begin_update(item_id)

func _begin_update(item_id: int) -> void:
    var handle: int = Steam.startItemUpdate(Steam.getAppID(), item_id)
    var manifest := _load_manifest(_pending_preset_path)
    Steam.setItemTitle(handle, manifest.get("name", "Untitled"))
    Steam.setItemDescription(handle, manifest.get("description", ""))
    Steam.setItemTags(handle, manifest.get("tags", []))
    Steam.setItemContent(handle, ProjectSettings.globalize_path(_pending_preset_path))
    Steam.setItemVisibility(handle,
        Steam.REMOTE_STORAGE_PUBLISHED_FILE_VISIBILITY_PUBLIC)
    var preview_path := _pending_preset_path + "/preview.png"
    if FileAccess.file_exists(preview_path):
        Steam.setItemPreview(handle, ProjectSettings.globalize_path(preview_path))
    Steam.submitItemUpdate(handle, "Updated via Iguana")

func _on_item_updated(result: int, accept_tos: bool, item_id: int) -> void:
    if result == Steam.RESULT_OK:
        upload_complete.emit(item_id)
    else:
        upload_failed.emit("submit_failed: %d" % result)
```

GodotSteam's exact signal signatures vary slightly between versions; check the version you've installed and adjust callback parameter order accordingly.

### Required files for a Steam build

- `steam_appid.txt` next to the executable (and at the project root during dev — git-ignored)
- The Steamworks redistributable (`steam_api64.dll` / `libsteam_api.so` / `libsteam_api.dylib`) — bundled inside the GodotSteam addon
- The GodotSteam GDExtension `.so` / `.dll` / `.dylib` — also inside the addon

---

## Workshop user flow

| Action | GDScript call | Steam signal |
|---|---|---|
| Browse items | `fetch_workshop_items(page)` | `ugc_query_completed` |
| Subscribe / download | `subscribe_and_download(item_id)` | `item_downloaded` |
| Unsubscribe | `Steam.unsubscribeItem(item_id)` | `item_unsubscribed` |
| Upload new | `upload_preset(path)` | `item_created` → `item_updated` |
| Update existing | `upload_preset(path, existing_id)` | `item_updated` |
| Open in browser | `Steam.activateGameOverlayToWebPage(url)` | — |

---

## What this layer does **not** do

- **No paid items.** Standard free Workshop only.
- **No achievements / leaderboards.** Out of scope.
- **No moderation tooling.** Rely on Steam's built-in reporting.
- **No Workshop voting from inside the app** (v1). Open the Workshop page in the Steam overlay; users vote there.
