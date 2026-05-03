# Audio Capture

System audio loopback capture lives in the Rust GDExtension. The capture thread is owned by the extension; GDScript only reads the latest frame via the lock-free triple buffer (see `03-fft-analysis.md`).

This doc covers **only PCM acquisition**. The FFT pipeline that runs on top of it is in `03-fft-analysis.md`.

---

## Goals

- Capture **system output** (whatever is playing on the OS), not microphone input.
- One stable code path per OS, picked at compile time.
- Never block the Godot main thread.
- Recover gracefully from device disconnect (USB unplug, default-output change).
- Surface failures to the user with actionable messages, not silent dead screens.

---

## Per-platform strategy

| Platform | API | Crate | Permission |
|---|---|---|---|
| Linux | PipeWire monitor source | `cpal` | none |
| Windows 10+ | WASAPI loopback | `cpal` | none |
| macOS 13+ | ScreenCaptureKit (audio-only) | `coreaudio-sys` + ObjC FFI | Screen Recording (one-time) |
| macOS <13 | not supported | — | error dialog → suggest upgrade |

Linux and Windows share the cpal code path. macOS is the outlier — cpal does not support output loopback there, so Iguana hand-rolls a ScreenCaptureKit recorder that emits audio-only sample buffers.

---

## Linux — PipeWire monitor source

PipeWire (and pulseaudio-as-pipewire) exposes every output device as a paired *monitor source* — capturing from the monitor source gives you the bit-identical audio stream being played out. cpal's ALSA backend transparently sees these as input devices.

```rust
use cpal::traits::{DeviceTrait, HostTrait};

fn pick_loopback_device(host: &cpal::Host, prefer: Option<&str>) -> anyhow::Result<cpal::Device> {
    let inputs = host.input_devices()?;
    let monitors: Vec<_> = inputs
        .filter(|d| d.name().map(|n| n.contains("monitor") || n.contains(".monitor")).unwrap_or(false))
        .collect();

    if let Some(name) = prefer {
        if let Some(d) = monitors.iter().find(|d| d.name().map(|n| n == name).unwrap_or(false)) {
            return Ok(d.clone());
        }
    }

    // Default: monitor of the system default sink.
    let default_sink_name = host.default_output_device()
        .and_then(|d| d.name().ok())
        .unwrap_or_default();

    monitors
        .iter()
        .find(|d| d.name().map(|n| n.contains(&default_sink_name)).unwrap_or(false))
        .or_else(|| monitors.first())
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("no PipeWire monitor source found"))
}
```

**Default-sink change**: when the user switches output devices on the host, the monitor we picked goes silent. Iguana subscribes to `default_output_device()` polling on a 2-second timer (in the audio thread) and re-opens the stream if the default changes.

**Per-application capture** (capturing only Spotify or only the browser) is technically possible via `pw-loopback` but is out of scope for v1. The default behavior is "all system audio".

---

## Windows — WASAPI loopback

cpal's WASAPI backend exposes loopback capture by enumerating output devices as inputs. The default output device is the right pick 99% of the time.

```rust
let host = cpal::host_from_id(cpal::HostId::Wasapi)?;

// On WASAPI, the output device IS the loopback source — cpal handles the flag.
let device = host.default_output_device()
    .ok_or_else(|| anyhow::anyhow!("no default output device"))?;

let config = device.default_output_config()?;   // shared-mode mix format
```

**Format**: shared-mode WASAPI delivers float32 stereo at the system mix rate (typically 48 kHz). Iguana resamples downstream only if the sample rate is < 32 kHz (rare).

**Exclusive-mode streams** (some pro audio apps) bypass the mix and won't appear in the loopback. This is a Windows limitation, not Iguana's. Document it in the FAQ.

**Device disconnect**: cpal's `StreamError::DeviceNotAvailable` fires when the default device changes or is unplugged. The audio thread catches it, emits `capture_failed(reason)`, and attempts reopen on a 1-second backoff.

---

## macOS — ScreenCaptureKit

Apple's ScreenCaptureKit (macOS 13+) is the only sanctioned API for capturing system audio. It requires the user to grant **Screen Recording** permission once — even though Iguana captures audio only.

The flow:

1. App calls into the GDExtension's `request_macos_permission()` method on first launch.
2. Rust → ObjC FFI: `SCShareableContent.getShareableContentExcludingDesktopWindows:onScreenWindowsOnly:completionHandler:` triggers the system prompt.
3. On grant, build an `SCContentFilter` covering the main display, an `SCStreamConfiguration` with `capturesAudio = YES` and `excludesCurrentProcessAudio = YES` (so we don't record ourselves), then start an `SCStream`.
4. `SCStreamOutput` callback fires on every audio sample buffer — extract the `AudioBufferList`, push f32 PCM into the same FFT pipeline as the other platforms.

```rust
// native/iguana_audio/src/macos/screencapturekit.rs
extern "C" {
    fn iguana_scstream_start(
        on_pcm: extern "C" fn(*const f32, usize, u32),  // ptr, frame_count, sample_rate
        out_handle: *mut *mut std::ffi::c_void,
    ) -> i32;
    fn iguana_scstream_stop(handle: *mut std::ffi::c_void);
}
```

The Objective-C side (a thin `.m` file linked into the crate via `cc`) bridges `SCStream` callbacks to the C function pointer. Keep this file under 200 lines — it has no business growing further.

**Permission denied**: emit `capture_failed("macos_screen_recording_denied")`. The UI shows a dialog with a deep link to System Settings → Privacy & Security → Screen Recording.

**macOS < 13**: detect at runtime via `NSProcessInfo.operatingSystemVersion`. Show a one-shot dialog: "Iguana requires macOS 13 (Ventura) or later for system audio capture."

---

## Sample-rate normalization

The FFT pipeline assumes a fixed analysis rate. Whatever the device delivers, the audio thread resamples to **48 kHz mono f32** before windowing. This keeps the band frequency boundaries (`docs/03-fft-analysis.md`) consistent across machines.

- Stereo → mono: simple mean of left and right.
- Resample: `rubato::FftFixedIn` if the device rate ≠ 48 kHz, otherwise no-op. Most devices on Linux/Windows/macOS already mix to 48 kHz, so this branch is rarely taken.

---

## Failure model

`SystemAudioCapture` is a `Node` registered by the extension. It emits a single `capture_failed(reason: String)` signal. Reason codes are stable, machine-readable strings that the UI maps to translatable error messages:

| Reason code | Meaning | UX response |
|---|---|---|
| `no_devices` | No output devices found | "No audio output detected. Check your sound settings." |
| `permission_denied` | macOS Screen Recording denied | Dialog with deep-link to System Settings |
| `unsupported_os` | macOS < 13 | "Iguana needs macOS 13+ for audio capture." |
| `device_disconnected` | Default device went away | Auto-retry up to 5×, then surface error |
| `format_unsupported` | Stream format we can't handle | "Unsupported audio format: {details}" |
| `internal` | Anything else | Generic error + log location |

GDScript subscribes once and routes all of these through a single `error_dialog.show(reason)` helper.

---

## What this layer does **not** do

- **No FFT.** That's `03-fft-analysis.md`.
- **No buffering for playback.** Iguana never plays audio back; capture is one-way into the FFT.
- **No history beyond the latest frame.** The audio thread overwrites; consumers that need history (e.g. BPM smoothing) maintain their own ring buffer.
- **No user-facing config.** Device selection lives in the Settings panel, which calls `SystemAudioCapture.set_device(name)` — but the validation, persistence, and UI are not the capture layer's concern.
