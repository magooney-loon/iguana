extends PanelContainer

# ── External references ───────────────────────────────────────────────────────
var _player:     AudioStreamPlayer
var _visualizer              # visualizer.gd node (ColorRect inside SubViewport)
var _analyzer:   AudioAnalyzer

# ── Player bar controls ───────────────────────────────────────────────────────
var _play_btn:   Button
var _seek_bar:   HSlider
var _time_label: Label
var _song_label: Label
var _paused  := false
var _seeking := false

# ── Settings window ───────────────────────────────────────────────────────────
var _settings_win:   Window
var _shader_btns:    Array[Button] = []
var _shuffle_check:  CheckBox
var _shuffle_spin:   SpinBox
var _last_shader_idx := -1


# Debug: key → { bar: ProgressBar, val: Label }
var _dbg: Dictionary = {}


func _ready() -> void:
	_player     = owner.get_node("Player") as AudioStreamPlayer
	_visualizer = get_tree().root.get_node("Main/VisualizerContainer/FeedbackViewport/Visualizer")
	_analyzer   = _visualizer._analyzer

	_apply_style()
	_build_bar()
	_build_settings_window()

	_player.finished.connect(_on_song_finished)
	_refresh_play_btn()

	# Show name of the track that's already loaded in the scene
	if _player.stream != null:
		var rpath := _player.stream.resource_path
		if not rpath.is_empty():
			_song_label.text = rpath.get_file().get_basename()


# ─────────────────────────────────────────────────────────────────────────────
#  Aero Glass Theme — helpers
# ─────────────────────────────────────────────────────────────────────────────

const _C_GLASS     := Color(0.08, 0.09, 0.16, 0.68)
const _C_GLASS_LT := Color(0.14, 0.16, 0.26, 0.55)
const _C_BORDER   := Color(0.55, 0.65, 0.85, 0.18)
const _C_HILITE   := Color(0.70, 0.80, 1.00, 0.22)   # top-edge reflection
const _C_SHADOW   := Color(0.0, 0.0, 0.02, 0.45)
const _C_BTN      := Color(0.16, 0.18, 0.28, 0.35)
const _C_BTN_H    := Color(0.30, 0.38, 0.55, 0.45)
const _C_BTN_P    := Color(0.08, 0.09, 0.14, 0.50)
const _C_ACCENT   := Color(0.40, 0.58, 0.92, 0.35)


func _glass_box(bg: Color, radius: float = 10.0, highlight: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color           = bg
	s.border_color       = _C_BORDER
	s.set_border_width_all(1)
	s.corner_radius_top_left     = int(radius)
	s.corner_radius_top_right    = int(radius)
	s.corner_radius_bottom_right = int(radius)
	s.corner_radius_bottom_left  = int(radius)
	s.shadow_color       = _C_SHADOW
	s.shadow_size        = 8
	s.shadow_offset      = Vector2(0, 3)
	if highlight:
		s.border_color = _C_HILITE
	return s


func _apply_glass_btn(btn: Button) -> void:
	var n := _glass_box(_C_BTN, 7.0, true)
	n.content_margin_left   = 10.0
	n.content_margin_right  = 10.0
	n.content_margin_top    = 4.0
	n.content_margin_bottom = 4.0
	var h := _glass_box(_C_BTN_H, 7.0, true)
	h.content_margin_left   = 10.0
	h.content_margin_right  = 10.0
	h.content_margin_top    = 4.0
	h.content_margin_bottom = 4.0
	var p := _glass_box(_C_BTN_P, 7.0, true)
	p.content_margin_left   = 10.0
	p.content_margin_right  = 10.0
	p.content_margin_top    = 4.0
	p.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)


func _apply_style() -> void:
	# Main bar — frosted glass panel
	var style := _glass_box(Color(0.06, 0.07, 0.12, 0.72), 12.0, true)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	style.shadow_size = 14
	add_theme_stylebox_override("panel", style)


# ─────────────────────────────────────────────────────────────────────────────
#  Player bar
# ─────────────────────────────────────────────────────────────────────────────

func _build_bar() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# ── Top row: controls ─────────────────────────────────────────────────────
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vbox.add_child(top)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.pressed.connect(_on_load)
	_apply_glass_btn(load_btn)
	top.add_child(load_btn)

	_play_btn = Button.new()
	_play_btn.custom_minimum_size.x = 36
	_play_btn.add_theme_font_size_override("font_size", 18)
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.pressed.connect(_on_play_pause)
	_apply_glass_btn(_play_btn)
	top.add_child(_play_btn)

	var stop_btn := Button.new()
	stop_btn.text = "⏹"
	stop_btn.tooltip_text = "Stop"
	stop_btn.custom_minimum_size.x = 36
	stop_btn.add_theme_font_size_override("font_size", 18)
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.pressed.connect(_on_stop)
	_apply_glass_btn(stop_btn)
	top.add_child(stop_btn)

	top.add_child(_vsep())

	_song_label = Label.new()
	_song_label.text = "No track loaded"
	_song_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_song_label.clip_text = true
	top.add_child(_song_label)

	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.modulate.a = 0.7
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_time_label)

	top.add_child(_vsep())

	var fs_btn := Button.new()
	fs_btn.text = "⛶"
	fs_btn.tooltip_text = "Fullscreen  [F]"
	fs_btn.custom_minimum_size.x = 36
	fs_btn.add_theme_font_size_override("font_size", 18)
	fs_btn.focus_mode = Control.FOCUS_NONE
	fs_btn.pressed.connect(_toggle_fullscreen)
	_apply_glass_btn(fs_btn)
	top.add_child(fs_btn)

	var set_btn := Button.new()
	set_btn.text = "⚙"
	set_btn.tooltip_text = "Settings"
	set_btn.custom_minimum_size.x = 36
	set_btn.add_theme_font_size_override("font_size", 18)
	set_btn.focus_mode = Control.FOCUS_NONE
	set_btn.pressed.connect(_toggle_settings)
	_apply_glass_btn(set_btn)
	top.add_child(set_btn)

	# ── Bottom row: seek bar (glass track + glowing grabber) ───────────
	_seek_bar = HSlider.new()
	_seek_bar.min_value  = 0.0
	_seek_bar.max_value  = 1.0
	_seek_bar.step       = 0.01
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.custom_minimum_size.y = 18
	_seek_bar.focus_mode = Control.FOCUS_NONE
	_seek_bar.value_changed.connect(_on_seek_changed)

	# Slider track (background)
	var sb_bg := _glass_box(Color(0.04, 0.05, 0.10, 0.50), 5.0, false)
	sb_bg.content_margin_top = 6.0
	sb_bg.content_margin_bottom = 6.0
	_seek_bar.add_theme_stylebox_override("slider", sb_bg)

	# Filled portion
	var sb_fill := _glass_box(Color(0.30, 0.45, 0.75, 0.50), 5.0, false)
	sb_fill.content_margin_top = 6.0
	sb_fill.content_margin_bottom = 6.0
	_seek_bar.add_theme_stylebox_override("fill", sb_fill)

	# Grabber
	var sb_grab := _glass_box(Color(0.55, 0.70, 1.0, 0.80), 8.0, true)
	sb_grab.content_margin_left = 4.0
	sb_grab.content_margin_right = 4.0
	sb_grab.content_margin_top = 4.0
	sb_grab.content_margin_bottom = 4.0
	_seek_bar.add_theme_stylebox_override("grabber_area", sb_grab)
	_seek_bar.add_theme_stylebox_override("grabber_area_highlight", sb_grab)

	vbox.add_child(_seek_bar)


func _vsep() -> VSeparator:
	return VSeparator.new()


# ─────────────────────────────────────────────────────────────────────────────
#  Settings window
# ─────────────────────────────────────────────────────────────────────────────

func _build_settings_window() -> void:
	_settings_win = Window.new()
	_settings_win.title    = "Settings"
	_settings_win.size     = Vector2i(440, 580)
	_settings_win.min_size = Vector2i(360, 420)
	_settings_win.transparent = true
	_settings_win.borderless = true
	_settings_win.close_requested.connect(func(): _settings_win.hide())
	_settings_win.hide()
	add_child(_settings_win)

	# ── Glass shell ────────────────────────────────────────────────────
	var shell := PanelContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_stylebox_override("panel", _glass_box(Color(0.06, 0.07, 0.12, 0.85), 14.0, true))
	_settings_win.add_child(shell)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	shell.add_child(col)

	# ── Custom title bar ──────────────────────────────────────────────
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", _glass_box(Color(0.10, 0.11, 0.18, 0.60), 14.0, true))
	col.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_right", 8)
	title_margin.add_theme_constant_override("margin_top", 8)
	title_margin.add_theme_constant_override("margin_bottom", 6)
	title_bar.add_child(title_margin)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_margin.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "Settings"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.modulate = Color(0.7, 0.82, 1.0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): _settings_win.hide())
	_apply_glass_btn(close_btn)
	title_row.add_child(close_btn)

	# ── Content area ──────────────────────────────────────────────────
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left",   8)
	content_margin.add_theme_constant_override("margin_right",  8)
	content_margin.add_theme_constant_override("margin_top",    4)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(content_margin)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("tab_fg", _glass_box(_C_BTN_H, 8.0, true))
	tabs.add_theme_stylebox_override("tab_bg", _glass_box(_C_BTN, 8.0, true))
	tabs.add_theme_stylebox_override("tab_hover", _glass_box(_C_ACCENT, 8.0, true))
	var tab_panel := _glass_box(Color(0.04, 0.05, 0.09, 0.60), 10.0, false)
	tab_panel.content_margin_left   = 10.0
	tab_panel.content_margin_right  = 10.0
	tab_panel.content_margin_top    = 10.0
	tab_panel.content_margin_bottom = 10.0
	tabs.add_theme_stylebox_override("panel", tab_panel)
	content_margin.add_child(tabs)

	tabs.add_child(_build_general_tab())
	tabs.add_child(_build_shaders_tab())
	tabs.add_child(_build_debug_tab())


# ── General tab ──────────────────────────────────────────────────────────────

func _build_general_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "General"
	vbox.add_theme_constant_override("separation", 5)

	_win_section(vbox, "AUTO-SHUFFLE")

	_shuffle_check = CheckBox.new()
	_shuffle_check.text = "Auto-shuffle  [S]"
	_shuffle_check.toggled.connect(func(on: bool):
		_visualizer._shuffle_on    = on
		_visualizer._shuffle_timer = 0.0
	)
	vbox.add_child(_shuffle_check)

	var spin_row := HBoxContainer.new()
	spin_row.add_theme_constant_override("separation", 4)
	var spin_pre := Label.new()
	spin_pre.text = "Switch every"
	spin_row.add_child(spin_pre)
	_shuffle_spin = SpinBox.new()
	_shuffle_spin.min_value = 10.0
	_shuffle_spin.max_value = 300.0
	_shuffle_spin.step      = 5.0
	_shuffle_spin.value     = _visualizer.shuffle_interval
	_shuffle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shuffle_spin.value_changed.connect(func(v: float):
		_visualizer.shuffle_interval = v
	)
	spin_row.add_child(_shuffle_spin)
	var spin_sfx := Label.new()
	spin_sfx.text = "seconds"
	spin_row.add_child(spin_sfx)
	vbox.add_child(spin_row)

	_win_sep(vbox)
	_win_section(vbox, "KEYBOARD SHORTCUTS")

	var keys := Label.new()
	keys.text = "Q / E     previous / next shader\nS           toggle auto-shuffle\nF           fullscreen\nSpace    play / pause"
	keys.add_theme_font_size_override("font_size", 12)
	keys.modulate.a = 0.55
	vbox.add_child(keys)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


# ── Shaders tab ───────────────────────────────────────────────────────────────

func _build_shaders_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Shaders"
	vbox.add_theme_constant_override("separation", 5)

	_win_section(vbox, "ACTIVE SHADERS")

	var group := ButtonGroup.new()
	var shaders: Array = _visualizer.SHADERS
	_shader_btns.clear()
	for i in shaders.size():
		var btn := Button.new()
		btn.text         = shaders[i].name
		btn.toggle_mode  = true
		btn.button_group = group
		btn.alignment    = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_shader_btn.bind(i))
		_apply_glass_btn(btn)
		vbox.add_child(btn)
		_shader_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


# ── Debug tab ─────────────────────────────────────────────────────────────────

func _build_debug_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Debug"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 4)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	pad.add_child(vbox)

	_dbg.clear()

	_win_section(vbox, "FREQUENCY BANDS")
	_dbg_row(vbox, "Sub Bass   20–60 Hz",   "sub_bass")
	_dbg_row(vbox, "Bass   60–250 Hz",      "bass")
	_dbg_row(vbox, "Low Mid   250–800 Hz",  "low_mid")
	_dbg_row(vbox, "Mid   800 Hz–4 kHz",    "mid")
	_dbg_row(vbox, "Presence   4–8 kHz",    "presence")
	_dbg_row(vbox, "Treble   8–16 kHz",     "treble")

	_win_sep(vbox)
	_win_section(vbox, "PERCUSSION")
	_dbg_row(vbox, "Kick",   "kick")
	_dbg_row(vbox, "Snare",  "snare")
	_dbg_row(vbox, "Hi-Hat", "hihat")
	_dbg_row(vbox, "Beat",   "beat")

	_win_sep(vbox)
	_win_section(vbox, "SPECTRAL FLUX")
	_dbg_row(vbox, "Flux Bass",   "flux_bass")
	_dbg_row(vbox, "Flux Mid",    "flux_mid")
	_dbg_row(vbox, "Flux Treble", "flux_treble")

	_win_sep(vbox)
	_win_section(vbox, "ENERGY")
	_dbg_row(vbox, "Energy",   "energy")
	_dbg_row(vbox, "Activity", "activity")
	_dbg_row(vbox, "Onset",    "onset")
	_dbg_row(vbox, "Loudness", "loudness")

	_win_sep(vbox)
	_win_section(vbox, "MOOD")
	_dbg_row(vbox, "Warmth",     "warmth")
	_dbg_row(vbox, "Brightness", "brightness")
	_dbg_row(vbox, "Density",    "density")

	_win_sep(vbox)
	_win_section(vbox, "TIMING")
	_dbg_row(vbox, "BPM",             "bpm",             200.0)
	_dbg_row(vbox, "Beat Phase",      "beat_phase")
	_dbg_row(vbox, "Beat Confidence", "beat_confidence")

	return scroll


func _dbg_row(parent: VBoxContainer, display: String, key: String, max_val: float = 1.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = display
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size.x = 170
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value  = 0.0
	bar.max_value  = max_val
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size   = Vector2(80, 14)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _glass_box(Color(0.03, 0.04, 0.08, 0.50), 4.0, false))
	bar.add_theme_stylebox_override("fill", _glass_box(Color(0.35, 0.52, 0.85, 0.55), 4.0, false))
	row.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.custom_minimum_size.x     = 46
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	parent.add_child(row)
	_dbg[key] = { "bar": bar, "val": val_lbl }


# ── Settings window helpers ───────────────────────────────────────────────────

func _win_section(parent: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = Color(0.55, 0.8, 1.0, 0.75)
	parent.add_child(lbl)


func _win_sep(parent: Control) -> void:
	parent.add_child(HSeparator.new())


# ─────────────────────────────────────────────────────────────────────────────
#  Frame update
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_player_ui()
	if _settings_win and _settings_win.visible:
		_sync_settings()
		_update_debug()


func _update_player_ui() -> void:
	if _player.stream == null:
		_time_label.text = "0:00 / 0:00"
		return
	var pos      := _player.get_playback_position()
	var duration := _player.stream.get_length()
	_time_label.text = "%s / %s" % [_fmt(pos), _fmt(duration)]
	if duration > 0.01:
		_seeking = true
		_seek_bar.max_value = duration
		_seek_bar.value     = pos
		_seeking = false


func _sync_settings() -> void:
	# Keep shader radio buttons in sync when Q/E are pressed outside the window
	var idx: int = _visualizer._shader_index
	if idx != _last_shader_idx:
		_last_shader_idx = idx
		for i in _shader_btns.size():
			_shader_btns[i].set_pressed_no_signal(i == idx)
	# Shuffle state
	_shuffle_check.set_block_signals(true)
	_shuffle_check.button_pressed = _visualizer._shuffle_on
	_shuffle_check.set_block_signals(false)


func _update_debug() -> void:
	if not _analyzer or _dbg.is_empty():
		return
	var a   := _analyzer
	var vals := {
		"sub_bass": a._sub_bass,   "bass":       a._bass,
		"low_mid":  a._low_mid,    "mid":         a._mid,
		"presence": a._presence,   "treble":      a._treble,
		"kick":     a._kick_envelope,  "snare":   a._snare_envelope,
		"hihat":    a._hihat_envelope, "beat":    a._beat_envelope,
		"flux_bass":   a._flux_bass,   "flux_mid": a._flux_mid,
		"flux_treble": a._flux_treble,
		"energy":    a._energy,    "activity":    a._activity,
		"onset":     a._onset,     "loudness":    a._loudness,
		"warmth":    a._warmth,    "brightness":  a._brightness,
		"density":   a._density,
		"bpm":            a._bpm,
		"beat_phase":     a._beat_phase,
		"beat_confidence":a._beat_confidence,
	}
	for key: String in _dbg:
		if key in vals:
			var entry: Dictionary = _dbg[key]
			var v: float = float(vals[key])
			(entry.bar as ProgressBar).value = v
			var fmt := "%.0f" if key == "bpm" else "%.3f"
			(entry.val as Label).text = fmt % v


# ─────────────────────────────────────────────────────────────────────────────
#  Actions
# ─────────────────────────────────────────────────────────────────────────────

func _on_play_pause() -> void:
	if _player.stream == null:
		return
	if _player.stream_paused:
		# Resume from where we paused
		_player.stream_paused = false
		_paused = false
	elif _player.playing:
		# Pause without losing position
		_player.stream_paused = true
		_paused = true
	else:
		# Stopped — start from the beginning
		_player.play()
		_paused = false
	_refresh_play_btn()


func _on_stop() -> void:
	_player.stop()
	_paused = false
	_refresh_play_btn()


func _on_seek_changed(val: float) -> void:
	if not _seeking:
		_player.seek(val)


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_settings() -> void:
	if _settings_win.visible:
		_settings_win.hide()
		return
	_settings_win.move_to_center()
	_settings_win.show()
	_sync_settings()


func _on_shader_btn(idx: int) -> void:
	_visualizer._switch(idx)




func _on_load() -> void:
	var dialog := FileDialog.new()
	dialog.access    = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters   = PackedStringArray(["*.mp3,*.ogg ; Audio Files"])
	dialog.file_selected.connect(_on_file_selected)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.65)


func _on_file_selected(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.play()
	_paused = false
	_song_label.text = path.get_file().get_basename()
	_seek_bar.max_value = stream.get_length()
	_refresh_play_btn()


func _on_song_finished() -> void:
	_paused = false
	_refresh_play_btn()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F:     _toggle_fullscreen()
		KEY_SPACE: _on_play_pause()
		KEY_ESCAPE: _on_stop()


# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _load_stream(path: String) -> AudioStream:
	var ext   := path.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	match ext:
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = bytes
			return s
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
	push_warning("PlayerUI: unsupported format '%s'" % ext)
	return null


func _refresh_play_btn() -> void:
	_play_btn.text = "⏸" if (_player.playing and not _paused) else "▶"


func _fmt(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [int(s / 60.0), s % 60]
