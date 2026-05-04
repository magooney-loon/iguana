extends ColorRect

const MIN_DB := 60.0
const BAND_GATE_MARGIN := 0.025
const BAND_MIN_SPAN := 0.28

const SHADERS := [
	{ "path": "res://shaders/signal_scope.gdshader", "name": "Signal Scope" },
	{ "path": "res://shaders/mandala.gdshader", "name": "Mandala" },
	{ "path": "res://shaders/starfall.gdshader", "name": "Starfall" },
	{ "path": "res://shaders/flow_state.gdshader", "name": "Flow State" },
	{ "path": "res://shaders/afterimage.gdshader", "name": "Afterimage" },
	{ "path": "res://shaders/overdrive.gdshader", "name": "Overdrive" },
	{ "path": "res://shaders/lattice.gdshader", "name": "Lattice" },
	{ "path": "res://shaders/glitch_garden.gdshader", "name": "Glitch Garden" },
	{ "path": "res://shaders/shadow_fold.gdshader", "name": "Shadow Fold" },
]

var _loaded_shaders: Array[Shader] = []
var _shader_index   := 0

var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _player: AudioStreamPlayer

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
var _prev_bas := 0.0
var _prev_mid_raw := 0.0
var _prev_tr  := 0.0

# Smoothed spectral flux per band
var _flux_bass   := 0.0
var _flux_mid    := 0.0
var _flux_treble := 0.0

# Overall energy
var _energy := 0.0
var _activity := 0.0
var _onset := 0.0
var _loudness := 0.0
var _warmth := 0.0
var _brightness := 0.0
var _density := 0.0

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
var _beat_threshold := 0.0
var _kick_threshold := 0.0
var _snare_threshold := 0.0
var _hihat_threshold := 0.0
var _row_peaks: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0,
	0.0, 0.0,
]

# Animation gate: smoothed energy used to slow time when silent
var _anim_energy := 0.0

# Auto-shuffle
const SHUFFLE_INTERVAL := 45.0
var _shuffle_timer := 0.0
var _shuffle_on    := false

# Shader name overlay
var _label: Label
var _label_timer := 0.0

# Right-click context menu for shader switching
var _context_menu: PopupMenu

# Debug overlay container (shown only for signal scope shader)
var _debug_overlay: Control
var _debug_values: Array[Label] = []
var _debug_top_values: Array[Label] = []
var _debug_flux_values: Array[Label] = []
var _debug_derived_values: Array[Label] = []

# Build a NoiseTexture2D for shaders that sample a noise channel
var _noise_tex: NoiseTexture2D

func _ready() -> void:
	_spectrum = AudioServer.get_bus_effect_instance(0, 0)
	_player = owner.get_node("Player") as AudioStreamPlayer

	for def in SHADERS:
		_loaded_shaders.append(load(def.path))

	# Start with the first shader
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = _loaded_shaders[0]

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(16, 14)
	_label.hide()
	add_child(_label)

	# Build right-click context menu
	_build_context_menu()

	# Build debug overlay
	_build_debug_overlay()

	# Build a NoiseTexture2D for shaders that sample a noise channel
	var fnoise := FastNoiseLite.new()
	fnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnoise.frequency = 0.04
	fnoise.fractal_octaves = 4
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.noise = fnoise
	_noise_tex.seamless = true

# ── Right-click context menu ────────────────────────────────────────

var _player_toggle_idx := 0

func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "ShaderContextMenu"
	for i in SHADERS.size():
		_context_menu.add_radio_check_item(SHADERS[i].name, i)
	_context_menu.set_item_checked(_shader_index, true)
	_context_menu.add_separator()
	_context_menu.add_check_item("Show Player")
	_player_toggle_idx = _context_menu.item_count - 1
	_context_menu.set_item_checked(_player_toggle_idx, true)
	_context_menu.index_pressed.connect(_on_context_menu_index_pressed)
	add_child(_context_menu)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_context_menu.reset_size()
			_context_menu.popup(Rect2i(int(mb.global_position.x), int(mb.global_position.y), 0, 0))
			accept_event()

func _on_context_menu_index_pressed(index: int) -> void:
	if index == _player_toggle_idx:
		var player_bar := owner.get_node("PlayerBar") as Control
		player_bar.visible = !player_bar.visible
		_context_menu.set_item_checked(index, player_bar.visible)
	elif index < SHADERS.size():
		var id := _context_menu.get_item_id(index)
		_switch(id)
		for i in SHADERS.size():
			_context_menu.set_item_checked(i, i == id)

# ── Debug overlay builder ──────────────────────────────────────────
# Creates a tree of Label nodes positioned to match the shader's layout.
# Positions are in ANCHOR/MARGIN coordinates relative to the visualizer rect.

func _build_debug_overlay() -> void:
	_debug_overlay = Control.new()
	_debug_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_debug_overlay)

	_debug_values.clear()
	_debug_top_values.clear()
	_debug_flux_values.clear()
	_debug_derived_values.clear()

	_add_debug_label("uniforms", 0.048, 0.090, 18, Color(1, 1, 1, 0.82))
	_add_debug_label("live", 0.129, 0.093, 11, Color(0.55, 0.85, 1.0, 0.76))
	_add_debug_label("snapshot", 0.632, 0.336, 12, Color(1, 1, 1, 0.50))
	_add_debug_label("noise_tex", 0.688, 0.556, 12, Color(1, 1, 1, 0.63))
	_add_debug_label("animated 256^2\nuv = uv + t*0.1", 0.688, 0.584, 10, Color(1, 1, 1, 0.43))

	var top_defs := [
		["bpm", 0.735, 0.126],
		["phase", 0.735, 0.166],
		["beat", 0.735, 0.198],
		["trust", 0.735, 0.230],
	]
	for def in top_defs:
		_add_debug_label(def[0], def[1], def[2], 11, Color(1, 1, 1, 0.48))
		var value := _add_debug_label("0.000", def[1] + 0.055, def[2], 11, Color(1, 1, 1, 0.80))
		_debug_top_values.append(value)

	var rows := [
		["sub_bass", "band"], ["bass", "band"], ["low_mid", "band"],
		["mid", "band"], ["presence", "band"], ["treble", "band"],
		["beat", "env"], ["kick", "env"], ["snare", "env"], ["hihat", "env"],
		["flux_bass", "flux"], ["flux_mid", "flux"], ["flux_treble", "flux"],
		["energy", "glob"], ["activity", "glob"],
	]
	for i in rows.size():
		var y := 0.153 + float(i) * 0.041
		_add_debug_label(rows[i][0], 0.062, y, 11, Color(1, 1, 1, 0.64))
		var value := _add_debug_label("0.000", 0.185, y, 11, Color(1, 1, 1, 0.82))
		_debug_values.append(value)
		_add_debug_label(rows[i][1], 0.525, y, 10, Color(1, 1, 1, 0.36))

	var spec_labels := ["sub", "bass", "low", "mid", "pres", "trebl"]
	for i in spec_labels.size():
		_add_debug_label(spec_labels[i], 0.615 + float(i) * 0.046, 0.516, 9, Color(1, 1, 1, 0.48))

	var flux_names := ["bass", "mid", "treble"]
	for i in flux_names.size():
		var label := _add_debug_label("%s\n+0.00" % flux_names[i], 0.635 + float(i) * 0.117, 0.858, 10, Color(0.55, 1.0, 0.72, 0.72))
		_debug_flux_values.append(label)

	var derived_defs := [
		["onset", 0.585, 0.705],
		["loud", 0.672, 0.705],
		["warm", 0.759, 0.705],
		["bright", 0.846, 0.705],
		["dense", 0.933, 0.705],
	]
	for def in derived_defs:
		_add_debug_label(def[0], def[1], def[2], 10, Color(1, 1, 1, 0.42))
		var value := _add_debug_label("0.00", def[1], def[2] + 0.024, 10, Color(1, 1, 1, 0.74))
		_debug_derived_values.append(value)

	_update_debug_overlay_visibility()

func _add_debug_label(text: String, ax: float, ay: float, font_size: int, label_color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.modulate = label_color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_left = ax; l.anchor_right = ax
	l.anchor_top = ay; l.anchor_bottom = ay
	l.offset_left = 0; l.offset_top = -12
	_debug_overlay.add_child(l)
	return l

func _update_debug_overlay_values() -> void:
	if _debug_overlay == null or not _debug_overlay.visible:
		return
	var values := [
		_sub_bass, _bass, _low_mid, _mid, _presence, _treble,
		_beat_envelope, _kick_envelope, _snare_envelope, _hihat_envelope,
		_flux_bass, _flux_mid, _flux_treble, _energy, _activity,
	]
	var count := mini(_debug_values.size(), values.size())
	for i in range(count):
		_debug_values[i].text = "%.3f" % values[i]
	if _debug_top_values.size() >= 4:
		_debug_top_values[0].text = "%.1f" % _bpm
		_debug_top_values[1].text = "%.2f" % _beat_phase
		_debug_top_values[2].text = "%.2f" % _beat_envelope
		_debug_top_values[3].text = "%.2f" % _beat_confidence
	var flux_values := [_flux_bass, _flux_mid, _flux_treble]
	var flux_names := ["bass", "mid", "treble"]
	count = mini(_debug_flux_values.size(), flux_values.size())
	for i in range(count):
		_debug_flux_values[i].text = "%s\n+%.2f" % [flux_names[i], flux_values[i]]
	var derived_values := [_onset, _loudness, _warmth, _brightness, _density]
	count = mini(_debug_derived_values.size(), derived_values.size())
	for i in range(count):
		_debug_derived_values[i].text = "%.2f" % derived_values[i]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_E: _switch((_shader_index + 1) % _loaded_shaders.size())
		KEY_Q: _switch((_shader_index - 1 + _loaded_shaders.size()) % _loaded_shaders.size())
		KEY_S: _toggle_shuffle()

func _switch(idx: int) -> void:
	_shader_index  = idx
	_shuffle_timer = 0.0
	(material as ShaderMaterial).shader = _loaded_shaders[idx]
	_update_debug_overlay_visibility()
	# Sync context menu radio checkmarks
	if _context_menu:
		for i in SHADERS.size():
			_context_menu.set_item_checked(i, i == idx)
	_label.text       = "< %s >" % SHADERS[idx].name
	_label.modulate.a = 1.0
	_label.show()
	_label_timer = 2.0

func _update_debug_overlay_visibility() -> void:
	if _debug_overlay == null:
		return
	# Show debug labels only when the spectrum_debug shader is active
	_debug_overlay.visible = (SHADERS[_shader_index].name == "Signal Scope")

func _toggle_shuffle() -> void:
	_shuffle_on    = !_shuffle_on
	_shuffle_timer = 0.0
	_label.text    = "Shuffle %s" % ("ON" if _shuffle_on else "OFF")
	_label.modulate.a = 1.0
	_label.show()
	_label_timer   = 2.0

func _shuffle() -> void:
	var next := _shader_index
	while next == _shader_index:
		next = randi() % _loaded_shaders.size()
	_switch(next)

func _process(delta: float) -> void:
	# Wall clock advances every frame so cooldowns and BPM intervals are real-time.
	_wall_time += delta

	# If audio is not actually playing, force-decay everything to zero fast
	var is_sounding := _player != null and _player.playing and not _player.stream_paused

	if not is_sounding:
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
		_push_uniforms(material as ShaderMaterial)
		_update_debug_overlay_values()
		return

	# Time advances proportionally to overall audio energy.
	# silent = frozen; loud = fast.  Envelope multiplier keeps it beat-weighted.
	var audio_drive := 0.3 + _energy * 0.7 + _activity * 0.5 + _beat_envelope * 0.8 + _kick_envelope * 0.4
	_time += delta * audio_drive
	_shuffle_timer += delta
	if _shuffle_on and _shuffle_timer >= SHUFFLE_INTERVAL:
		_shuffle()

	# Fade label
	if _label_timer > 0.0:
		_label_timer -= delta
		_label.modulate.a = clampf(_label_timer, 0.0, 1.0)
		if _label_timer <= 0.0:
			_label.hide()

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
	var rf_bas := maxf(0.0, raw_bas - _prev_bas) * 4.0
	var rf_mid := maxf(0.0, raw_mid - _prev_mid_raw) * 4.0
	var rf_tr  := maxf(0.0, raw_tr  - _prev_tr)  * 4.0
	_flux_bass   = _smooth_ar(_flux_bass,   rf_bas, 20.0, 8.0, delta)
	_flux_mid    = _smooth_ar(_flux_mid,    rf_mid, 20.0, 8.0, delta)
	_flux_treble = _smooth_ar(_flux_treble, rf_tr,  20.0, 8.0, delta)
	_prev_bas = raw_bas; _prev_mid_raw = raw_mid; _prev_tr = raw_tr
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

	_push_uniforms(material as ShaderMaterial)
	_update_debug_overlay_values()

func _push_uniforms(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rect_size", get_rect().size)
	mat.set_shader_parameter("sub_bass",    _sub_bass)
	mat.set_shader_parameter("bass",        _bass)
	mat.set_shader_parameter("low_mid",     _low_mid)
	mat.set_shader_parameter("mid",         _mid)
	mat.set_shader_parameter("presence",    _presence)
	mat.set_shader_parameter("treble",      _treble)
	mat.set_shader_parameter("beat",        _beat_envelope)
	mat.set_shader_parameter("kick",        _kick_envelope)
	mat.set_shader_parameter("snare",       _snare_envelope)
	mat.set_shader_parameter("hihat",       _hihat_envelope)
	mat.set_shader_parameter("flux_bass",   _flux_bass)
	mat.set_shader_parameter("flux_mid",    _flux_mid)
	mat.set_shader_parameter("flux_treble", _flux_treble)
	mat.set_shader_parameter("energy",      _energy)
	mat.set_shader_parameter("activity",    _activity)
	mat.set_shader_parameter("onset",       _onset)
	mat.set_shader_parameter("loudness",    _loudness)
	mat.set_shader_parameter("warmth",      _warmth)
	mat.set_shader_parameter("brightness",  _brightness)
	mat.set_shader_parameter("density",     _density)
	mat.set_shader_parameter("beat_phase",  _beat_phase)
	mat.set_shader_parameter("bpm",         _bpm)
	mat.set_shader_parameter("beat_confidence", _beat_confidence)
	mat.set_shader_parameter("beat_threshold",  _beat_threshold)
	mat.set_shader_parameter("kick_threshold",  _kick_threshold)
	mat.set_shader_parameter("snare_threshold", _snare_threshold)
	mat.set_shader_parameter("hihat_threshold", _hihat_threshold)
	mat.set_shader_parameter("time_val",    _time)
	mat.set_shader_parameter("noise_tex",   _noise_tex)
	for i in range(_row_peaks.size()):
		mat.set_shader_parameter("peak_%02d" % i, _row_peaks[i])

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
