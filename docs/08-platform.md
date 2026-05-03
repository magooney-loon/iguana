# Platform & Distribution

Per-channel build, packaging, and quirks. The app itself is identical across channels — what differs is whether the GodotSteam addon is bundled and which signing pipeline runs.

---

## Channels at a glance

| Channel | OS | Steam | Signing | Notes |
|---|---|---|---|---|
| Steam | Linux / Win / macOS | on | platform cert | Workshop UI enabled |
| Flathub | Linux | off | GPG (Flathub) | Submit to flathub/iguana repo |
| AUR `iguana-bin` | Linux | off | maintainer key | binary repackage of release tarball |
| winget | Windows | off | EV cert | manifest in microsoft/winget-pkgs |
| Homebrew Cask | macOS | off | Apple notarization | cask in homebrew/cask |

"Steam = off" means the GodotSteam addon is **not bundled** in those builds and `steam_appid.txt` is absent. `Workshop.is_available()` returns `false`, the UI hides the Workshop tab.

---

## Export presets

Godot's exporter is configured via `export_presets.cfg`. Iguana ships five presets, two of which differ only by whether the Steam addon is embedded.

```ini
# export_presets.cfg (excerpt)

[preset.0]
name="Linux/X11"
platform="Linux/X11"
runnable=true
custom_features=""
binary_format/embed_pck=true

[preset.1]
name="Linux/X11 (Steam)"
platform="Linux/X11"
custom_features="steam"
binary_format/embed_pck=true

[preset.2]
name="Windows Desktop"
platform="Windows Desktop"
binary_format/embed_pck=true

[preset.3]
name="Windows Desktop (Steam)"
platform="Windows Desktop"
custom_features="steam"
binary_format/embed_pck=true

[preset.4]
name="macOS"
platform="macOS"
custom_features="steam"
binary_format/embed_pck=true
codesign/identity="Developer ID Application: Your Name (TEAMID)"
notarization/apple_id_name="…"
```

The `steam` custom feature flag is read at runtime: `if OS.has_feature("steam"): …`. Combined with `Steam.isSteamRunning()`, this gates the Workshop UI safely whether the addon is missing or simply not running.

---

## Per-channel notes

### Steam

Single source of truth — the only build that ships with Workshop.

```sh
godot --headless --path . --export-release "Linux/X11 (Steam)" build/steam-linux/iguana.x86_64
godot --headless --path . --export-release "Windows Desktop (Steam)" build/steam-win/iguana.exe
godot --headless --path . --export-release "macOS" build/steam-mac/Iguana.app
```

Each output goes into a Steam depot:

```
depot-linux/
├── iguana.x86_64
├── steam_appid.txt
├── libsteam_api.so
└── addons/iguana_audio/bin/libiguana_audio.linux.x86_64.so

depot-win/
├── iguana.exe
├── steam_appid.txt
├── steam_api64.dll
└── addons/iguana_audio/bin/iguana_audio.windows.x86_64.dll

depot-mac/
└── Iguana.app/
    └── Contents/
        ├── MacOS/Iguana
        ├── Frameworks/libsteam_api.dylib
        └── Resources/...
```

Run `steamcmd run_app_build` against your VDF script (per Steamworks docs).

### Flathub

A flatpak manifest at `packaging/flathub/dev.iguana.app.yml`. Build with `flatpak-builder` against the Freedesktop SDK; bundle the Linux export, do **not** bundle the Steam addon.

Audio capture works out-of-the-box on Flatpak via PipeWire — Iguana doesn't need any portal permission beyond default. The PipeWire socket is exposed by default in modern flatpak runtimes.

```yaml
# packaging/flathub/dev.iguana.app.yml (sketch)
app-id: dev.iguana.app
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: iguana
finish-args:
  - --share=ipc
  - --socket=fallback-x11
  - --socket=wayland
  - --device=dri
  - --socket=pulseaudio          # PipeWire-pulse compat
  - --filesystem=xdg-config/iguana
modules:
  - name: iguana
    buildsystem: simple
    build-commands:
      - install -Dm755 iguana.x86_64 /app/bin/iguana
      - install -d /app/share/iguana/addons/iguana_audio/bin
      - install -m644 libiguana_audio.linux.x86_64.so /app/share/iguana/addons/iguana_audio/bin/
    sources:
      - type: archive
        path: iguana-linux.tar.gz
```

### AUR

Two packages: `iguana` (build from source) and `iguana-bin` (repackage release tarball). `iguana-bin` is what most users install.

```sh
# PKGBUILD (iguana-bin)
pkgname=iguana-bin
pkgver=1.0.0
arch=('x86_64')
depends=('pipewire' 'libxcursor' 'libxrandr' 'libxi' 'mesa')
source=("https://github.com/.../iguana-${pkgver}-linux.tar.gz")
package() {
  install -Dm755 "$srcdir/iguana.x86_64" "$pkgdir/usr/bin/iguana"
  install -d "$pkgdir/usr/share/iguana/addons/iguana_audio/bin"
  install -m644 "$srcdir/libiguana_audio.linux.x86_64.so" \
                "$pkgdir/usr/share/iguana/addons/iguana_audio/bin/"
}
```

### winget

Submit a manifest to `microsoft/winget-pkgs`. The artifact is the `.exe` produced by `Windows Desktop` (non-Steam). Sign with the EV cert before publishing — winget validation rejects unsigned binaries.

```yaml
PackageIdentifier: Iguana.Iguana
PackageVersion: 1.0.0
Installers:
  - Architecture: x64
    InstallerType: portable
    InstallerUrl: https://github.com/.../iguana-1.0.0-win.zip
    InstallerSha256: …
```

### Homebrew Cask

Cask in `homebrew/cask`. The artifact is the `.app` produced by `macOS` (non-Steam — but you still need notarization).

```ruby
# Casks/iguana.rb
cask "iguana" do
  version "1.0.0"
  sha256 "…"
  url "https://github.com/.../Iguana-#{version}.dmg"
  name "Iguana"
  desc "Audio-reactive GDShader visualizer"
  homepage "https://iguana.app"
  app "Iguana.app"
end
```

---

## Settings persistence

`Settings.gd` writes to `user://settings.cfg`, which resolves per OS:

| OS | Path |
|---|---|
| Linux | `~/.local/share/godot/app_userdata/Iguana/settings.cfg` |
| Linux (Flatpak) | `~/.var/app/dev.iguana.app/data/godot/app_userdata/Iguana/settings.cfg` |
| Windows | `%APPDATA%\Godot\app_userdata\Iguana\settings.cfg` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Iguana/settings.cfg` |

Schema (sections `[audio]`, `[ui]`, `[beat]`):

```ini
[audio]
device="alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"

[beat]
sensitivity=1.3
cooldown_ms=200

[ui]
show_fps=false
auto_hide_ms=3000
last_preset="nebula"
```

`Settings` is permissive — missing keys return defaults. A corrupt file is renamed to `settings.cfg.bak` and a fresh one is created.

---

## Keyboard shortcuts

Defined in `project.godot` `[input]` section. Defaults:

| Action | Default | Customisable |
|---|---|---|
| Toggle UI | `H` | yes |
| Next preset | `→` / `Space` | yes |
| Previous preset | `←` | yes |
| Open settings | `S` | yes |
| Open preset picker | `P` | yes |
| Open Workshop panel | `W` | yes (Steam builds only) |
| Toggle fullscreen | `F11` | yes |
| Toggle FPS overlay | `F3` | yes |
| Quit | `Esc` (with confirmation) | no |

---

## Idle / no-audio state

When `volume < 0.001` for more than 2 seconds, `VisualEngine` sets a `silent` boolean uniform to `true`. Presets can ignore it (default) or use it to fade to a still pose. The shader keeps animating from `time_val`; nothing freezes.

This is documented in `05-preset-authoring.md` § Standard uniforms (additions on the next minor revision — keep `silent` opt-in until a few presets adopt it).

---

## Performance overlay

`F3` toggles a small `Label` showing FPS, frame time (ms), and CPU side spent in `_process` (us). Independently of the overlay, Godot's `--debug-collisions` style flags work normally.

---

## CI / release builds

GitHub Actions runs three jobs per release tag:

1. **build-linux**: builds the GDExtension + exports Linux/X11 (and Linux/X11 Steam). Produces `iguana-linux.tar.gz` and `iguana-steam-linux.tar.gz`.
2. **build-windows**: same on Windows runner. Produces `.zip`s.
3. **build-macos**: same on macOS runner, signs and notarizes. Produces `.dmg`s.

A fourth job runs `cargo test` and `godot --check-only` against the project for PRs and main pushes.
