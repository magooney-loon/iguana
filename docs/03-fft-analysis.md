# FFT Analysis & AudioFrame Contract

The FFT pipeline runs on the audio thread inside the Rust GDExtension, downstream of the loopback capture (`02-audio-capture.md`). Its output is a single immutable struct — the `AudioFrame` — published into a `triple_buffer` slot that the GDScript main thread reads each `_process` tick.

This is the **contract layer** between native and scripting. Every consumer of audio data — `VisualEngine`, `BeatDetector`, `ParameterPanel` meters, `Settings` overlay — talks to this struct, not to the capture or FFT internals.

---

## Pipeline

```
PCM chunk (f32 mono, 48 kHz, ~512 samples)
    │
    ▼
Hann window  (precomputed [f32; 1024])
    │
    ▼
realfft 1024-point FFT  →  Vec<Complex<f32>> [513]
    │
    ▼
Magnitude  →  [f32; 512]   (drop DC bin, take |X[k]|)
    │
    ▼
Log-scale normalize  →  [f32; 512] in 0.0..=1.0
    │
    ▼
Band extraction
    bass    = mean(bins covering 60–250 Hz)
    mid     = mean(bins covering 250–4000 Hz)
    treble  = mean(bins covering 4000–20000 Hz)
    │
    ▼
Beat detection
    rolling-window threshold on bass (1.0s history)
    cooldown 200 ms minimum between beats
    BPM estimate from inter-beat intervals
    │
    ▼
AudioFrame struct  →  triple_buffer.write(frame)
```

The audio thread runs at the device's callback rate (typically ~93 Hz at 48 kHz / 512-sample buffers). The main thread reads at Godot's frame rate (60 Hz / 144 Hz / etc.). Triple buffering means the reader always gets the most recent fully-published frame without stalling the producer.

---

## Window size and FFT length

| Parameter | Value | Why |
|---|---|---|
| Sample rate | 48 000 Hz | Normalised in capture layer (`02-audio-capture.md`) |
| FFT length | 1024 | 21.3 ms window — good balance of time/freq resolution for music |
| Hop | ~512 samples (one capture buffer) | Matches typical device callback size |
| Bin count | 512 (positive frequencies, DC dropped) | `length/2`, minus DC |
| Bin width | ~46.9 Hz | `48000 / 1024` |

Larger FFTs (2048, 4096) buy more frequency resolution at the cost of latency. 1024 is the sweet spot for responsive visuals — anything bigger makes the bass response feel sluggish on snappy beats.

---

## Band boundaries

```rust
const BIN_WIDTH_HZ: f32 = 48_000.0 / 1024.0;   // ~46.875

fn hz_to_bin(hz: f32) -> usize {
    (hz / BIN_WIDTH_HZ).round() as usize
}

let bass_range   = hz_to_bin(60.0)    ..= hz_to_bin(250.0);    //  ~1..=5
let mid_range    = hz_to_bin(250.0)   ..  hz_to_bin(4000.0);   //  ~5..85
let treble_range = hz_to_bin(4000.0)  ..  hz_to_bin(20000.0);  // ~85..427
```

Each band's scalar is the **mean magnitude** within its bin range, post-normalization. Mean (rather than sum or max) keeps the scalars roughly comparable in 0..=1 across bands of very different widths.

---

## Normalization

Raw magnitudes from rustfft span an enormous dynamic range and depend on input level. Iguana applies log-scale normalization with a slow-decaying ceiling so the visual response stays within a useful range regardless of source loudness:

```rust
struct Normalizer {
    ceiling: f32,        // slow-falling running max
    floor:   f32,        // slow-rising noise floor
}

impl Normalizer {
    fn step(&mut self, mag: f32) -> f32 {
        let log_mag = (1.0 + mag).ln();
        // Ceiling rises instantly to new peaks, decays at -0.5/sec
        self.ceiling = self.ceiling.max(log_mag) - 0.0083;
        self.ceiling = self.ceiling.max(0.1);   // never collapse to zero
        ((log_mag - self.floor) / (self.ceiling - self.floor)).clamp(0.0, 1.0)
    }
}
```

One normalizer per band scalar. A separate normalizer applies element-wise to the FFT bin array exposed to shaders.

---

## Beat detection

The simplest approach that consistently feels good: per-band rolling threshold on bass with a cooldown.

```rust
struct BeatDetector {
    history: VecDeque<f32>,   // last ~1.0s of bass values (~93 samples)
    last_beat_ms: u64,
    cooldown_ms: u64,         // 200 ms — no double-fire on a single hit
    sensitivity: f32,         // 1.3 — current must exceed 1.3× rolling mean
}

impl BeatDetector {
    fn step(&mut self, bass: f32, now_ms: u64) -> bool {
        self.history.push_back(bass);
        if self.history.len() > 93 { self.history.pop_front(); }
        let mean = self.history.iter().sum::<f32>() / self.history.len() as f32;

        if bass > mean * self.sensitivity
            && bass > 0.4
            && now_ms - self.last_beat_ms > self.cooldown_ms
        {
            self.last_beat_ms = now_ms;
            return true;
        }
        false
    }
}
```

The `BeatDetector` Rust struct only emits the **boolean event**. The GDScript-side `BeatDetector.gd` (`docs/04-visualization-engine.md`) holds the decay envelope that turns that event into the `0..=1` shader uniform — keeping the envelope parameter (cooldown_ms decay) cheaply tunable from the Settings panel without rebuilding the extension.

**BPM estimate**: keep the last 16 inter-beat intervals; report the median converted to BPM. Below 60 BPM or above 200 BPM, mark the estimate as unreliable (`bpm_confidence < 0.5`).

The `sensitivity` and `cooldown_ms` knobs are exposed via `SystemAudioCapture.set_beat_sensitivity(f: f32)` and `set_beat_cooldown_ms(ms: u32)` so the Settings panel can tune them at runtime.

---

## AudioFrame contract

The struct published into the triple buffer:

```rust
#[derive(Clone, Default)]
pub struct AudioFrame {
    pub bins:       [f32; 512],   // normalized magnitude spectrum
    pub bass:       f32,          // 0..=1
    pub mid:        f32,          // 0..=1
    pub treble:     f32,          // 0..=1
    pub presence:   f32,          // 0..=1, 4–8 kHz sub-band, useful for vocals/cymbals
    pub volume:     f32,          // 0..=1, RMS of input chunk
    pub beat:       bool,         // edge-triggered: true on the frame a beat fires
    pub bpm:        f32,          // last estimate (60..=200), 0 if unknown
    pub bpm_confidence: f32,      // 0..=1
    pub timestamp_us: u64,        // monotonic time the frame was produced
}
```

GDScript reads this via `SystemAudioCapture.get_frame()`, which returns a `Dictionary` for ergonomic access:

```gdscript
# AudioBridge.gd
var frame := capture.get_frame()
# frame = {
#   "bins": PackedFloat32Array (512),
#   "bass": 0.42, "mid": 0.18, "treble": 0.07, "presence": 0.11,
#   "volume": 0.31, "beat": false, "bpm": 124.0, "bpm_confidence": 0.86,
#   "timestamp_us": 17283849172
# }
```

`bins` is exposed as `PackedFloat32Array` (zero-copy from the Rust `[f32; 512]`). Shaders that want the full spectrum receive it as a 1D `sampler2D` of width 512, height 1 — `VisualEngine` builds that texture each frame from the array (`docs/04-visualization-engine.md`).

### Versioning

The frame schema is part of the GDExtension ABI. **Adding** fields is fine (older shaders ignore them). **Renaming** or **removing** is a breaking change — bump the extension version in `iguana_audio.gdextension`'s `compatibility_minimum` and document the migration in the changelog.

---

## Lock-free handoff

```rust
use triple_buffer::TripleBuffer;

let buffer = TripleBuffer::new(&AudioFrame::default());
let (mut producer, mut consumer) = buffer.split();

// Audio thread
producer.write(frame);      // O(1), no allocation, never blocks

// Main thread (Godot)
let frame = consumer.read().clone();   // O(1), reads latest fully-published frame
```

The contract: the producer never blocks the audio callback (a lock here would underrun the audio device). The consumer never sees a half-written frame (the triple buffer atomically swaps slots).

`AudioFrame` must remain `Clone + Default + Send`. Avoid putting `Vec` or `String` in it — those would allocate on every audio callback. The `[f32; 512]` array is stack-allocated and copies cheaply.

---

## Performance budget

| Stage | Target time | Notes |
|---|---|---|
| Window + FFT (1024 pt) | < 0.5 ms | rustfft on a single core, well under budget |
| Magnitude + normalize | < 0.1 ms | 512 floats, vectorizable |
| Band + beat | < 0.05 ms | trivial |
| Triple-buffer write | ~50 ns | atomic pointer swap |
| **Total per audio callback** | **< 1 ms** | versus ~10 ms callback period at 512 samples / 48 kHz |

If the audio thread ever blows this budget, the symptom is an audio glitch on the **playing application**, not on Iguana — because we hold the loopback callback. That's why the FFT is small and allocation-free.

---

## What this layer does **not** do

- **No persistence.** Frames are produced and consumed in real time; nothing is logged.
- **No mixing or playback.** One-way in.
- **No per-shader transformation.** Bands and bins are produced once; each shader interprets them as it likes.
- **No envelope / smoothing on band scalars.** Smoothing is per-consumer (e.g. `BeatDetector.gd` smooths bass for the beat envelope; some shaders prefer the raw response).
