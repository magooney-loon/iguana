class_name AudioAnalyzer
extends RefCounted

## Audio analysis engine for Iguana.
## Reads the spectrum analyzer each frame and produces normalized, smoothed
## frequency band values, transient envelopes, BPM, and mood metrics.

const MIN_DB := 60.0
const BAND_GATE_MARGIN := 0.025
const BAND_MIN_SPAN := 0.28

var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _player: AudioStreamPlayer
var is_sounding := false

# Audio-driven clock (drives shader time_val). Speeds up with energy.
var _time := 0.0
# Real wall clock (drives BPM intervals and detector cooldowns).
var _wall_time := 0.0

# Adaptive floor/peak trackers make exported bands useful for both quiet and
# aggressively mastered songs without making shader authors tune per track.
var _band_floor: Array[float] = [0.015, 0.015, 0.015, 0.015, 0.015, 0.015]
var _band_peak: Array[float] = [0.35, 0.40, 0.36, 0.34, 0.30, 0.28]

# Smoothed band values (asymmetric: fast attack, slow release)
var _sub_bass := 0.0
var _bass     := 0.0
var _low_mid  := 0.0
var _mid      := 0.0
var _presence := 0.0
var _treble   := 0.0

# Previous raw values for spectral flux
var _prev_bass_raw   := 0.0
var _prev_mid_raw    := 0.0
var _prev_treble_raw := 0.0

# Smoothed spectral flux per band
var _flux_bass   := 0.0
var _flux_mid    := 0.0
var _flux_treble := 0.0

# Overall energy
var _energy   := 0.0
var _activity := 0.0
var _onset    := 0.0
var _loudness := 0.0
var _warmth   := 0.0
var _brightness := 0.0
var _density  := 0.0

# Animation gate: smoothed energy used to slow time when silent
var _anim_energy := 0.0

# Kick detection (sub-bass band)
var _sub_bass_history: Array[float] = []
var _last_kick_time := -1.0
var _kick_envelope  := 0.0

# Beat detection (bass band)
var _bass_history: Array[float] = []
var _last_beat_time := -1.0
var _beat_envelope  := 0.0

# Snare detection (low-mid band)
var _lm_history: Array[float] = []
var _last_snare_time := -1.0
var _snare_envelope  := 0.0

# Hihat detection (presence + treble)
var _hihat_history: Array[float] = []
var _last_hihat_time := -1.0
var _hihat_envelope  := 0.0

# BPM estimation + beat phase
var _beat_intervals: Array[float] = []
var _bpm        := 120.0
var _beat_phase := 0.0
var _beat_confidence := 0.0
var _beat_threshold  := 0.0
var _kick_threshold  := 0.0
var _snare_threshold := 0.0
var _hihat_threshold := 0.0

# Debug peak-hold values
var _row_peaks: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0,
	0.0, 0.0,
]


func setup(spectrum: AudioEffectSpectrumAnalyzerInstance, player: AudioStreamPlayer) -> void:
	_spectrum = spectrum
	_player = player


func process(delta: float) -> void:
	_wall_time += delta
	is_sounding = _player != null and _player.playing and not _player.stream_paused

	if not is_sounding:
		_decay_silence(delta)
		return

	_analyze(delta)


func _decay_silence(delta: float) -> void:
	_beat_envelope  = maxf(0.0, _beat_envelope  - delta * 12.0)
	_kick_envelope  = maxf(0.0, _kick_envelope  - delta * 12.0)
	_snare_envelope = maxf(0.0, _snare_envelope - delta * 12.0)
	_hihat_envelope = maxf(0.0, _hihat_envelope - delta * 12.0)
	_anim_energy    = maxf(0.0, _anim_energy    - delta * 12.0)
	_energy         = maxf(0.0, _energy         - delta * 12.0)
	_activity       = maxf(0.0, _activity       - delta * 12.0)
	_onset          = maxf(0.0, _onset          - delta * 12.0)
	_loudness       = maxf(0.0, _loudness       - delta * 12.0)
	_warmth         = maxf(0.0, _warmth         - delta * 12.0)
	_brightness     = maxf(0.0, _brightness     - delta * 12.0)
	_density        = maxf(0.0, _density        - delta * 12.0)
	_beat_confidence = maxf(0.0, _beat_confidence - delta * 3.0)
	_sub_bass       = maxf(0.0, _sub_bass       - delta * 12.0)
	_bass           = maxf(0.0, _bass           - delta * 12.0)
	_low_mid        = maxf(0.0, _low_mid        - delta * 12.0)
	_mid            = maxf(0.0, _mid            - delta * 12.0)
	_presence       = maxf(0.0, _presence       - delta * 12.0)
	_treble         = maxf(0.0, _treble         - delta * 12.0)
	_flux_bass      = maxf(0.0, _flux_bass      - delta * 12.0)
	_flux_mid       = maxf(0.0, _flux_mid       - delta * 12.0)
	_flux_treble    = maxf(0.0, _flux_treble    - delta * 12.0)
	_decay_row_peaks(delta)


func _analyze(delta: float) -> void:
	# Time advances proportionally to overall audio energy.
	# silent = frozen; loud = fast.  Envelope multiplier keeps it beat-weighted.
	var audio_drive := 0.3 + _energy * 0.7 + _activity * 0.5 + _beat_envelope * 0.8 + _kick_envelope * 0.4
	_time += delta * audio_drive

	# --- Raw bands ---
	var raw_sub := _band(20.0,   60.0)
	var raw_bas := _band(60.0,   250.0)
	var raw_lm  := _band(250.0,  800.0)
	var raw_mid := _band(800.0,  4000.0)
	var raw_pre := _band(4000.0, 8000.0)
	var raw_tr  := _band(8000.0, 16000.0)

	var analyzer_loudness := (
		raw_sub * 1.10 + raw_bas * 1.15 + raw_lm * 0.95
		+ raw_mid * 0.90 + raw_pre * 0.85 + raw_tr * 0.80
	) / 5.75
	_loudness = _smooth_ar(_loudness, analyzer_loudness, 10.0, 2.0, delta)

	# --- Adaptive normalization and gating ---
	raw_sub = _normalize_band(raw_sub, 0, delta)
	raw_bas = _normalize_band(raw_bas, 1, delta)
	raw_lm  = _normalize_band(raw_lm,  2, delta)
	raw_mid = _normalize_band(raw_mid, 3, delta)
	raw_pre = _normalize_band(raw_pre, 4, delta)
	raw_tr  = _normalize_band(raw_tr,  5, delta)

	# --- Asymmetric smoothing: fast attack, slow release ---
	_sub_bass = _smooth_ar(_sub_bass, raw_sub, 20.0,  6.0, delta)
	_bass     = _smooth_ar(_bass,     raw_bas, 18.0,  5.0, delta)
	_low_mid  = _smooth_ar(_low_mid,  raw_lm,  12.0,  4.0, delta)
	_mid      = _smooth_ar(_mid,      raw_mid, 12.0,  4.0, delta)
	_presence = _smooth_ar(_presence, raw_pre, 10.0,  3.5, delta)
	_treble   = _smooth_ar(_treble,   raw_tr,   8.0,  3.0, delta)

	# --- Spectral flux: positive onset per band, amplified and smoothed ---
	var rf_bas := maxf(0.0, raw_bas - _prev_bass_raw)   * 4.0
	var rf_mid := maxf(0.0, raw_mid - _prev_mid_raw)    * 4.0
	var rf_tr  := maxf(0.0, raw_tr  - _prev_treble_raw) * 4.0
	_flux_bass   = _smooth_ar(_flux_bass,   rf_bas, 20.0, 8.0, delta)
	_flux_mid    = _smooth_ar(_flux_mid,    rf_mid, 20.0, 8.0, delta)
	_flux_treble = _smooth_ar(_flux_treble, rf_tr,  20.0, 8.0, delta)
	_prev_bass_raw = raw_bas; _prev_mid_raw = raw_mid; _prev_treble_raw = raw_tr
	var raw_onset := maxf(maxf(_flux_bass, _flux_mid), _flux_treble)
	_onset = _smooth_ar(_onset, raw_onset, 24.0, 7.0, delta)

	# --- Overall energy ---
	var raw_energy := (
		raw_sub * 1.10 + raw_bas * 1.15 + raw_lm * 0.95
		+ raw_mid * 0.90 + raw_pre * 0.85 + raw_tr * 0.80
	) / 5.75
	_energy = _smooth_ar(_energy, raw_energy, 8.0, 3.0, delta)
	var raw_activity := clampf(
		raw_energy * 0.72
		+ (_flux_bass + _flux_mid + _flux_treble) * 0.18
		+ maxf(maxf(_beat_envelope, _snare_envelope), _hihat_envelope) * 0.22,
		0.0, 1.0
	)
	_activity = _smooth_ar(_activity, raw_activity, 10.0, 2.5, delta)
	var tonal_total := raw_sub + raw_bas + raw_lm + raw_mid + raw_pre + raw_tr + 0.001
	_warmth = _smooth_ar(_warmth, clampf((raw_bas + raw_lm) / tonal_total * 1.7, 0.0, 1.0), 5.0, 1.5, delta)
	_brightness = _smooth_ar(_brightness, clampf((raw_pre + raw_tr) / tonal_total * 2.2, 0.0, 1.0), 5.0, 1.5, delta)
	_density = _smooth_ar(_density, clampf((raw_lm + raw_mid + raw_pre) / 3.0 + _activity * 0.25, 0.0, 1.0), 6.0, 1.8, delta)
	# Release speed 2.0 → drops below gate threshold ~1.3s after music stops
	_anim_energy = _smooth_ar(_anim_energy, raw_energy, 4.0, 2.0, delta)

	# --- Beat detection (bass band) ---
	# Uses wall clock so BPM intervals reflect real seconds, not audio-driven _time.
	var beat_mean := _arr_mean(_bass_history)
	_bass_history.append(raw_bas)
	if _bass_history.size() > 60:
		_bass_history.pop_front()
	var beat_onset := _flux_bass > 0.16 or raw_bas > beat_mean + 0.16
	_beat_threshold = clampf(maxf(beat_mean * 1.12, beat_mean + 0.16), 0.0, 1.0)
	if raw_bas > beat_mean * 1.12 and raw_bas > 0.28 and beat_onset and _wall_time - _last_beat_time > 0.2:
		if _last_beat_time > 0.0:
			var interval := _wall_time - _last_beat_time
			if interval > 0.3 and interval < 2.0:
				_beat_intervals.append(interval)
				if _beat_intervals.size() > 8:
					_beat_intervals.pop_front()
				if _beat_intervals.size() >= 4:
					var sorted := _beat_intervals.duplicate()
					sorted.sort()
					_bpm = 60.0 / sorted[sorted.size() >> 1]
		_last_beat_time = _wall_time
		_beat_envelope  = 1.0
	else:
		_beat_envelope = maxf(0.0, _beat_envelope - delta * 3.0)

	# --- Snare detection (low-mid band) ---
	var snare_mean := _arr_mean(_lm_history)
	_lm_history.append(raw_lm)
	if _lm_history.size() > 60:
		_lm_history.pop_front()
	var snare_onset := _flux_mid > 0.14 or raw_lm > snare_mean + 0.14
	_snare_threshold = clampf(maxf(snare_mean * 1.12, snare_mean + 0.14), 0.0, 1.0)
	if raw_lm > snare_mean * 1.12 and raw_lm > 0.22 and snare_onset and _wall_time - _last_snare_time > 0.15:
		_last_snare_time = _wall_time
		_snare_envelope  = 1.0
	else:
		_snare_envelope = maxf(0.0, _snare_envelope - delta * 4.0)

	# --- Hihat detection (presence + treble) ---
	var raw_hihat := (raw_pre + raw_tr) * 0.5
	var hihat_mean := _arr_mean(_hihat_history)
	_hihat_history.append(raw_hihat)
	if _hihat_history.size() > 30:
		_hihat_history.pop_front()
	var hihat_onset := _flux_treble > 0.12 or raw_hihat > hihat_mean + 0.12
	_hihat_threshold = clampf(maxf(hihat_mean * 1.10, hihat_mean + 0.12), 0.0, 1.0)
	if raw_hihat > hihat_mean * 1.10 and raw_hihat > 0.18 and hihat_onset and _wall_time - _last_hihat_time > 0.08:
		_last_hihat_time = _wall_time
		_hihat_envelope  = 1.0
	else:
		_hihat_envelope = maxf(0.0, _hihat_envelope - delta * 6.0)

	# --- Kick detection (sub-bass band, 20-60Hz) ---
	var kick_mean := _arr_mean(_sub_bass_history)
	_sub_bass_history.append(raw_sub)
	if _sub_bass_history.size() > 30:
		_sub_bass_history.pop_front()
	var kick_onset := raw_sub > kick_mean + 0.15 or (raw_sub > kick_mean * 1.18 and _flux_bass > 0.10)
	_kick_threshold = clampf(maxf(kick_mean * 1.10, kick_mean + 0.15), 0.0, 1.0)
	if raw_sub > kick_mean * 1.10 and raw_sub > 0.24 and kick_onset and _wall_time - _last_kick_time > 0.15:
		_last_kick_time = _wall_time
		_kick_envelope  = 1.0
	else:
		_kick_envelope = maxf(0.0, _kick_envelope - delta * 5.0)

	# --- Beat phase: only advances when music is present ---
	_onset = maxf(_onset, maxf(maxf(_beat_envelope, _kick_envelope), maxf(_snare_envelope, _hihat_envelope)))
	_update_beat_confidence(delta)
	_update_row_peaks([
		_sub_bass, _bass, _low_mid, _mid, _presence, _treble,
		_beat_envelope, _kick_envelope, _snare_envelope, _hihat_envelope,
		_flux_bass, _flux_mid, _flux_treble,
		_energy, _activity,
	], delta)
	_beat_phase = fmod(_beat_phase + delta * (_bpm / 60.0) * smoothstep(0.04, 0.14, _activity), 1.0)


# ── Utility methods ────────────────────────────────────────────────

func _smooth_ar(cur: float, tgt: float, attack: float, release: float, dt: float) -> float:
	var speed := attack if tgt > cur else release
	return lerpf(cur, tgt, 1.0 - exp(-speed * dt))


func _update_row_peaks(values: Array, dt: float) -> void:
	var count := mini(_row_peaks.size(), values.size())
	for i in range(count):
		var value := float(values[i])
		if value > _row_peaks[i]:
			_row_peaks[i] = value
		else:
			_row_peaks[i] = maxf(0.0, _row_peaks[i] - dt * 0.22)


func _decay_row_peaks(dt: float) -> void:
	for i in range(_row_peaks.size()):
		_row_peaks[i] = maxf(0.0, _row_peaks[i] - dt * 1.5)


func _update_beat_confidence(dt: float) -> void:
	var target := 0.0
	if _beat_intervals.size() >= 4:
		var sorted: Array[float] = _beat_intervals.duplicate()
		sorted.sort()
		var median: float = sorted[sorted.size() >> 1]
		var dev := 0.0
		for interval: float in _beat_intervals:
			dev += absf(interval - median)
		dev /= float(_beat_intervals.size())
		var stability := 1.0 - clampf(dev / maxf(median, 0.001) * 4.0, 0.0, 1.0)
		var sample_quality := clampf(float(_beat_intervals.size()) / 8.0, 0.0, 1.0)
		target = stability * sample_quality * smoothstep(0.12, 0.35, _activity)
	_beat_confidence = _smooth_ar(_beat_confidence, target, 3.0, 1.2, dt)


func _normalize_band(raw: float, idx: int, dt: float) -> float:
	var peak_target := maxf(raw, BAND_MIN_SPAN)
	_band_peak[idx] = _smooth_ar(_band_peak[idx], peak_target, 3.8, 0.32, dt)
	if raw < _band_floor[idx] + 0.08:
		_band_floor[idx] = lerpf(_band_floor[idx], raw, 1.0 - exp(-0.75 * dt))
	else:
		_band_floor[idx] = lerpf(_band_floor[idx], minf(raw, 0.12), 1.0 - exp(-0.04 * dt))

	var gate := _band_floor[idx] + BAND_GATE_MARGIN
	var span := maxf(_band_peak[idx] - gate, BAND_MIN_SPAN)
	var normalized := clampf((raw - gate) / span, 0.0, 1.0)
	return pow(normalized, 1.15)


func _arr_mean(arr: Array[float]) -> float:
	var sum := 0.0
	for v: float in arr:
		sum += v
	return sum / arr.size() if arr.size() > 0 else 0.0


func _band(from_hz: float, to_hz: float) -> float:
	var mag := _spectrum.get_magnitude_for_frequency_range(from_hz, to_hz).length()
	return clampf((MIN_DB + linear_to_db(mag)) / MIN_DB, 0.0, 1.0)
