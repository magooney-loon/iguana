# Iguana - Audio-Reactive Shader Visualizer

Iguana is a Godot 4 audio-reactive shader visualizer. It analyzes the playing audio in real time, extracts broad frequency bands, detects transient hits, estimates beat timing, derives mood-style controls, and pushes everything into the active shader as uniforms.

Language: GDScript
Renderer: Compatibility
Target Godot: 4.6

## How It Works

The engine lives in `engine/visualizer.gd` and runs from `_process()`.

Each frame it:

1. Reads Godot's `AudioEffectSpectrumAnalyzerInstance`
2. Samples six broad frequency bands
3. Tracks adaptive per-band floor and peak values
4. Normalizes and smooths the shader-facing band uniforms
5. Computes spectral flux for bass, mid, and treble onsets
6. Detects beat, kick, snare, and hihat envelopes
7. Estimates BPM, beat phase, and beat confidence
8. Derives `onset`, `loudness`, `warmth`, `brightness`, and `density`
9. Pushes all uniforms into the active `ShaderMaterial`

The shader never needs to read audio directly. It only consumes uniforms.

## Shader Uniforms

### Frequency Bands

These are adaptive normalized values, smoothed with fast attack and slower release.

| Uniform | Range | Frequency | Use |
| --- | --- | --- | --- |
| `sub_bass` | 0-1 | 20-60 Hz | Deep sub, kick thump, 808s |
| `bass` | 0-1 | 60-250 Hz | Bass body, low rhythm |
| `low_mid` | 0-1 | 250-800 Hz | Snare body, low vocals, guitar fundamentals |
| `mid` | 0-1 | 800-4000 Hz | Vocals, leads, snare crack |
| `presence` | 0-1 | 4-8 kHz | Attack, consonants, cymbal presence |
| `treble` | 0-1 | 8-16 kHz | Air, shimmer, hihat sizzle |

The analyzer values are first dB-normalized, then passed through adaptive floor/peak tracking. This keeps quiet and loud songs usable without per-track shader tuning.

### Transients

| Uniform | Range | Source | Use |
| --- | --- | --- | --- |
| `beat` | 0-1 | Bass onset and running bass history | General rhythmic pulse |
| `kick` | 0-1 | Sub-bass onset and sub history | Deep kick-style hits |
| `snare` | 0-1 | Low-mid onset and low-mid history | Snares, claps, mid hits |
| `hihat` | 0-1 | Presence/treble onset and high history | Hats, cymbals, high ticks |

Detectors compare the current normalized band against the previous history window and an onset/flux requirement. When a detector fires, its envelope jumps to `1.0` and decays over time.

### Spectral Flux

Flux is positive change: how much a range just increased.

| Uniform | Range | Description |
| --- | --- | --- |
| `flux_bass` | 0-1 | Bass-range onset amount |
| `flux_mid` | 0-1 | Mid-range onset amount |
| `flux_treble` | 0-1 | Treble-range onset amount |
| `onset` | 0-1 | Combined global onset/transient strength |

Use flux/onset for flashes, cuts, ripples, shockwaves, and one-frame accents.

### Global/Mood Metrics

| Uniform | Range | Description |
| --- | --- | --- |
| `energy` | 0-1 | Adaptive normalized overall energy |
| `activity` | 0-1 | Energy plus flux/transient contribution, useful for gating motion |
| `loudness` | 0-1 | Raw analyzer loudness before adaptive normalization |
| `warmth` | 0-1 | Bass/low-mid weighted tonal balance |
| `brightness` | 0-1 | Presence/treble weighted tonal balance |
| `density` | 0-1 | Mid-band density plus activity |

`energy` is good for visual size/intensity. `loudness` is useful when the shader needs to know whether the source audio is actually quiet or loud. `warmth`, `brightness`, and `density` are useful for color palettes and long-form morphing.

### Timing

| Uniform | Range | Description |
| --- | --- | --- |
| `bpm` | float | Estimated tempo from recent beat intervals |
| `beat_phase` | 0-1 | Phase through the current beat, wrapping once per beat |
| `beat_confidence` | 0-1 | Confidence based on beat interval stability and activity |
| `time_val` | 0+ | Audio-driven clock, faster when the music is active |

`beat_phase` advances only when activity is present. Use `beat_confidence` to avoid strict beat-sync behavior while BPM is still settling.

### Utility

| Uniform | Type | Description |
| --- | --- | --- |
| `noise_tex` | sampler2D | 512x512 seamless noise texture |
| `rect_size` | vec2 | Current visualizer rect size in pixels |

### Debug-Only Uniforms

The debug shader also receives:

| Uniform | Range | Description |
| --- | --- | --- |
| `beat_threshold` | 0-1 | Current beat detector threshold |
| `kick_threshold` | 0-1 | Current kick detector threshold |
| `snare_threshold` | 0-1 | Current snare detector threshold |
| `hihat_threshold` | 0-1 | Current hihat detector threshold |
| `peak_00` ... `peak_14` | 0-1 | Peak-hold values for the debug meter rows |

Preset shaders can ignore these unless they want diagnostic visuals.

## Uniform Template

```glsl
shader_type canvas_item;

uniform float sub_bass    : hint_range(0.0, 1.0) = 0.0;
uniform float bass        : hint_range(0.0, 1.0) = 0.0;
uniform float low_mid     : hint_range(0.0, 1.0) = 0.0;
uniform float mid         : hint_range(0.0, 1.0) = 0.0;
uniform float presence    : hint_range(0.0, 1.0) = 0.0;
uniform float treble      : hint_range(0.0, 1.0) = 0.0;

uniform float beat        : hint_range(0.0, 1.0) = 0.0;
uniform float kick        : hint_range(0.0, 1.0) = 0.0;
uniform float snare       : hint_range(0.0, 1.0) = 0.0;
uniform float hihat       : hint_range(0.0, 1.0) = 0.0;

uniform float flux_bass   : hint_range(0.0, 1.0) = 0.0;
uniform float flux_mid    : hint_range(0.0, 1.0) = 0.0;
uniform float flux_treble : hint_range(0.0, 1.0) = 0.0;
uniform float onset       : hint_range(0.0, 1.0) = 0.0;

uniform float energy      : hint_range(0.0, 1.0) = 0.0;
uniform float activity    : hint_range(0.0, 1.0) = 0.0;
uniform float loudness    : hint_range(0.0, 1.0) = 0.0;
uniform float warmth      : hint_range(0.0, 1.0) = 0.0;
uniform float brightness  : hint_range(0.0, 1.0) = 0.0;
uniform float density     : hint_range(0.0, 1.0) = 0.0;

uniform float beat_phase  : hint_range(0.0, 1.0) = 0.0;
uniform float beat_confidence : hint_range(0.0, 1.0) = 0.0;
uniform float bpm = 120.0;
uniform float time_val = 0.0;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1600.0, 900.0);
```

Use `UV` for normalized rect coordinates and `UV * rect_size` for pixel-precise drawing.

## Spectrum Debug

`shaders/spectrum_debug.gdshader` is the diagnostic shader. It is designed for people making their own shaders, so they can see what the engine is extracting from a song.

It shows:

- Live values for all main uniform rows
- Peak-hold ticks for each row
- Detector threshold markers for beat/kick/snare/hihat
- BPM, beat phase, and beat confidence
- Spectrum snapshot
- Noise texture preview
- Flux/onset indicators
- Derived mood values: onset, loudness, warmth, brightness, density

## Controls

| Key | Action |
| --- | --- |
| `E` | Next shader |
| `Q` | Previous shader |
| `S` | Toggle auto-shuffle |

The bottom player bar provides load, play/pause, seek, and song info.

## Adding A Shader

1. Create a `.gdshader` in `shaders/`
2. Add it to `SHADERS` in `engine/visualizer.gd`
3. Cycle to it with `E`/`Q`

```gdscript
const SHADERS := [
	{ "path": "res://shaders/spectrum_debug.gdshader", "name": "Spectrum Debug" },
	{ "path": "res://shaders/your_shader.gdshader", "name": "Your Shader" },
]
```

## Project Structure

```text
├── engine/
│   └── visualizer.gd              # Audio analysis engine + shader switching
├── shaders/
│   └── spectrum_debug.gdshader    # Debug HUD showing engine output
├── ui/
│   └── player_ui.gd               # Player bar
├── main.tscn
├── project.godot
└── default.ogg
```

## License

Based on the Godot audio spectrum demo. MIT License.
