# Iguana — Project Initialization Guide

This guide takes a fresh clone (which contains only `docs/`, `LICENSE`, and this file) and scaffolds the Godot 4 + GDScript + Rust GDExtension application on top of it.

> **Primary target: Fedora Atomic** (`rpm-ostree`-based — Silverblue, Kinoite, Bazzite, Bluefin, etc.). The base OS is immutable, so all dev tooling lives inside a **toolbox** container instead of being layered onto the host. Other platforms are covered at the bottom of this document.

---

## 1 · Development environment (Fedora Atomic)

### Create the toolbox

```sh
# Match your host Fedora release; check with: cat /etc/os-release
toolbox create --release f43 iguana
toolbox enter iguana
```

From here on, every command runs **inside the toolbox** unless prefixed with `[host]`. Your home directory is shared with the host, so `~/Documents/Git/iguana` is the same path in both places.

### System packages

```sh
sudo dnf install -y \
  gcc gcc-c++ make pkgconf-pkg-config clang \
  alsa-lib-devel pipewire-devel \
  libX11-devel libXcursor-devel libXrandr-devel libXi-devel \
  mesa-libGL-devel mesa-libGLU-devel \
  git unzip
```

`alsa-lib-devel` and `pipewire-devel` are for `cpal` — the Rust GDExtension uses PipeWire monitor sources for system audio loopback on Linux (`docs/02-audio-capture.md`). The X11 / GL packages are for running the Godot editor against the host display via toolbox pass-through.

### Rust toolchain

`rustup` installs into `$HOME/.cargo`, which is shared across host and toolbox, so you only do this once:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup update stable
```

### Godot 4 editor

The Godot editor is a single self-contained binary. Drop it under `~/bin` (which is on the toolbox `PATH`):

```sh
mkdir -p ~/bin
cd /tmp
curl -LO https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip
mv Godot_v4.3-stable_linux.x86_64 ~/bin/godot
chmod +x ~/bin/godot
godot --version   # 4.3.stable.official
```

> Use the **standard** build, not the .NET/Mono build. Iguana is GDScript-only; the C# toolchain is unnecessary weight.

---

## 2 · Scaffold the application

The repo only ships docs at this point. Create the project skeleton next to the docs.

### Initialise the Godot project

```sh
cd ~/Documents/Git/iguana
godot --headless --path . --quit-after 1   # creates project.godot if missing
```

If that doesn't write a `project.godot` (older Godot versions), create it by hand:

```ini
; project.godot
config_version=5

[application]
config/name="Iguana"
config/description="Audio-reactive GDShader visualizer with Steam Workshop"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.3", "GL Compatibility")
config/icon="res://icon.svg"

[autoload]
AudioBridge="*res://scripts/AudioBridge.gd"
PresetLoader="*res://scripts/PresetLoader.gd"
Settings="*res://scripts/Settings.gd"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

### Lay out the module tree

```sh
mkdir -p scenes/ui
mkdir -p scripts
mkdir -p shaders
mkdir -p presets
mkdir -p addons/iguana_audio/bin
mkdir -p addons/godotsteam
mkdir -p native/iguana_audio/src
```

The `presets/` dir at the repo root holds **bundled** presets that ship with the build. User-installed and Workshop-downloaded presets live under `user://presets/` at runtime (resolves to `~/.local/share/godot/app_userdata/Iguana/presets/` on Linux).

Then fill in modules from the design docs:

| Skeleton path | Fill from |
|---|---|
| `native/iguana_audio/` | `docs/02-audio-capture.md`, `docs/03-fft-analysis.md` |
| `addons/iguana_audio/` | `docs/06-godot-integration.md` § GDExtension layout |
| `scripts/AudioBridge.gd` | `docs/03-fft-analysis.md` § GDScript surface |
| `scripts/VisualEngine.gd` | `docs/04-visualization-engine.md` |
| `scripts/PresetLoader.gd` | `docs/04-visualization-engine.md` § Hot reload |
| `scripts/Workshop.gd` | `docs/06-godot-integration.md` § Steamworks |
| `scenes/Main.tscn`, `scenes/ui/*` | `docs/09-preset-creator.md` |
| `shaders/*.gdshader` | `docs/05-preset-authoring.md` |

---

## 3 · Build the Rust GDExtension

The audio capture, FFT, beat detection, and filesystem watcher all live in a single Rust crate compiled to a platform-native shared library.

### Bootstrap the crate

```sh
cd native/iguana_audio
cargo init --lib
```

Set `Cargo.toml`:

```toml
[package]
name    = "iguana_audio"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
godot         = "0.2"          # godot-rust (gdext)
cpal          = "0.15"
rustfft       = "6"
realfft       = "3"            # real-valued FFT wrapper around rustfft
notify        = "6"            # filesystem watcher for shader hot-reload
triple_buffer = "8"            # lock-free audio→main thread handoff
```

Build:

```sh
cargo build --release
```

The artifact lands at `target/release/libiguana_audio.so` (Linux), `iguana_audio.dll` (Windows), or `libiguana_audio.dylib` (macOS).

### Wire the extension into Godot

Copy or symlink the built library into the addon's `bin/` and write the manifest Godot loads at startup:

```sh
ln -sf "$(pwd)/target/release/libiguana_audio.so" \
       ../../addons/iguana_audio/bin/libiguana_audio.linux.x86_64.so
```

`addons/iguana_audio/iguana_audio.gdextension`:

```ini
[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.3

[libraries]
linux.x86_64    = "res://addons/iguana_audio/bin/libiguana_audio.linux.x86_64.so"
windows.x86_64  = "res://addons/iguana_audio/bin/iguana_audio.windows.x86_64.dll"
macos           = "res://addons/iguana_audio/bin/libiguana_audio.macos.universal.dylib"
```

See `docs/06-godot-integration.md` for the full crate skeleton and the classes (`SystemAudioCapture`, `FileWatcher`) it registers.

---

## 4 · Steam / GodotSteam (optional)

Required only for Steam Workshop builds. Standard distribution builds (Flathub, AUR, winget, Homebrew) compile without it and hide all Workshop UI at runtime.

GodotSteam is shipped as a **GDExtension addon** — no custom editor build, no replacing your Godot binary.

1. Download the GDExtension build matching your Godot version from <https://godotsteam.com>.
2. Extract into `addons/godotsteam/` so the layout matches:

   ```
   addons/godotsteam/
   ├── godotsteam.gdextension
   ├── bin/
   │   ├── linux/libgodotsteam.linux.x86_64.so
   │   ├── win64/godotsteam.windows.x86_64.dll
   │   └── osx/libgodotsteam.macos.universal.dylib
   └── sdk/
       ├── redistributable_bin/...
       └── steam_api.h
   ```

3. Create `steam_appid.txt` at the project root with your Steam App ID (use `480` for Spacewar during development):

   ```
   480
   ```

   This file is git-ignored.

4. Gate the Workshop UI on `Steam.isSteamRunning()` so non-Steam builds skip it cleanly. See `docs/06-godot-integration.md` § Steamworks.

---

## 5 · Development

Inside the toolbox, repo root:

```sh
godot --editor .          # open the project in the editor
godot .                   # run the project headless of the editor
```

When you change Rust code, rebuild the GDExtension and restart Godot — Godot only loads `.gdextension` libraries at process start:

```sh
cd native/iguana_audio && cargo build --release && cd ../..
```

When you change `.gdshader` files, **Godot hot-reloads them automatically in the editor**. In a running export build, the `FileWatcher` exposed by the Rust extension watches `user://presets/` and signals `PresetLoader.gd` to reload the active shader (`docs/04-visualization-engine.md`).

---

## 6 · Production build

Godot's CLI exporter consumes `export_presets.cfg`. Standard build:

```sh
godot --headless --path . --export-release "Linux/X11" build/iguana.x86_64
```

Steam build (same command — the Steamworks code is gated at runtime by the presence of the GodotSteam addon and `steam_appid.txt`):

```sh
godot --headless --path . --export-release "Linux/X11" build/iguana.x86_64
```

Artifacts land in `build/`. See `docs/08-platform.md` for per-channel details.

| Channel | Steam features | Signing |
|---|---|---|
| Flathub (Linux) | off | GPG (Flathub) |
| AUR `iguana-bin` | off | maintainer key |
| winget (Windows) | off | EV certificate |
| Homebrew Cask (macOS) | off | Apple notarization |
| Steam (all OS) | on | platform cert |

---

## 7 · Useful commands

```sh
godot --editor .                                 # open editor
godot .                                          # run game
godot --headless --path . --check-only           # script parse check
cargo build --release                            # rebuild GDExtension
cargo test                                       # Rust unit tests
cargo clippy --all-targets                       # Rust linter
godot --headless --path . --export-release "..." # production build
```

---

## 8 · Project structure (quick reference)

```
iguana/
├── project.godot
├── scenes/
│   ├── Main.tscn
│   ├── Visualizer.tscn
│   └── ui/
│       ├── PresetPicker.tscn
│       ├── Settings.tscn
│       ├── WorkshopPanel.tscn
│       └── UploadDialog.tscn
├── scripts/
│   ├── AudioBridge.gd        # autoload — wraps SystemAudioCapture
│   ├── BeatDetector.gd
│   ├── VisualEngine.gd       # FFT → shader uniforms each frame
│   ├── PresetLoader.gd       # autoload — scans + hot-reloads presets
│   ├── ParameterPanel.gd     # generates UI from shader uniform list
│   ├── Settings.gd           # autoload — ConfigFile persistence
│   └── Workshop.gd           # GodotSteam UGC wrapper
├── shaders/                  # bundled presets
│   ├── plasma.gdshader
│   ├── nebula.gdshader
└── alien_core.gdshader
├── presets/                  # bundled preset folders (manifest + shader)
├── native/
│   └── iguana_audio/         # Rust GDExtension source
│       ├── Cargo.toml
│       └── src/
├── addons/
│   ├── iguana_audio/         # built GDExtension artifacts
│   │   ├── iguana_audio.gdextension
│   │   └── bin/
│   └── godotsteam/           # third-party Steam GDExtension
├── docs/                     # design documentation
├── export_presets.cfg
└── steam_appid.txt           # git-ignored
```

See `docs/07-project-structure.md` for the full module breakdown.

---

## 9 · Other platforms

The toolbox flow above is Fedora Atomic-specific. Equivalent setups on other systems:

**Fedora Workstation (mutable)**

```sh
sudo dnf install -y gcc gcc-c++ clang alsa-lib-devel pipewire-devel \
  libX11-devel libXcursor-devel libXrandr-devel libXi-devel \
  mesa-libGL-devel mesa-libGLU-devel git
```

**Debian / Ubuntu**

```sh
sudo apt update && sudo apt install -y \
  build-essential clang libasound2-dev libpipewire-0.3-dev \
  libx11-dev libxcursor-dev libxrandr-dev libxi-dev \
  libgl1-mesa-dev libglu1-mesa-dev git
```

**macOS**

```sh
xcode-select --install
brew install rustup-init
rustup-init -y
# Download Godot 4 macOS build from https://godotengine.org/download
# Drop Godot.app into /Applications
```

The macOS audio loopback path uses ScreenCaptureKit (requires macOS 13+) and needs a one-time "Screen Recording" permission grant. See `docs/02-audio-capture.md` § macOS.

**Windows**

- Install [Microsoft C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) (Desktop development with C++ workload)
- `winget install Rustlang.Rustup`
- Download Godot 4 Windows build from <https://godotengine.org/download>

After system deps, jump back to §1's Rust step and continue from §2.

---

## Further reading

| Doc | Topic |
|-----|-------|
| `docs/01-architecture.md` | System overview and design principles |
| `docs/02-audio-capture.md` | cpal loopback per platform, ScreenCaptureKit FFI |
| `docs/03-fft-analysis.md` | rustfft pipeline, beat detection, AudioFrame contract |
| `docs/04-visualization-engine.md` | ColorRect + ShaderMaterial, hot-reload pipeline |
| `docs/05-preset-authoring.md` | `.gdshader` format, standard uniforms, custom params |
| `docs/06-godot-integration.md` | GDExtension API, autoloads, GodotSteam |
| `docs/07-project-structure.md` | Repository layout and module boundaries |
| `docs/08-platform.md` | Config, shortcuts, distribution channels |
| `docs/09-preset-creator.md` | Auto-generated parameter panel and Workshop publishing |
