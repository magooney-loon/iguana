class_name SettingsUI

extends Node

var _visualizer              # visualizer.gd node (ColorRect inside SubViewport)
var _analyzer:   AudioAnalyzer

# Window
var _win:          Window
var _content:      Control
var _tween:        Tween

# Tabs
var _tabs:         TabContainer
var _shader_btns:  Array[Button] = []
var _last_shader_idx := -1

# General tab
var _shuffle_check: CheckBox
var _shuffle_spin:  SpinBox

# Post-process tab
var _pp_sliders:      Dictionary = {}
var _pp_shader_label: Label

# Debug tab
var _dbg: Dictionary = {}


func setup(visualizer, analyzer: AudioAnalyzer) -> void:
	_visualizer = visualizer
	_analyzer   = analyzer
	_build()


func open() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_win.move_to_center()
	_win.show()
	_sync()

	_content.pivot_offset = _content.size / 2.0
	_content.scale = Vector2(0.90, 0.90)
	_content.modulate.a = 0.0

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_content, "scale", Vector2.ONE, 0.32)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_content, "modulate:a", 1.0, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.set_parallel(false)


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_content.pivot_offset = _content.size / 2.0

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_content, "scale", Vector2(0.90, 0.90), 0.18)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_content, "modulate:a", 0.0, 0.18)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.set_parallel(false)
	_tween.tween_callback(_win.hide)


func is_visible() -> bool:
	return _win != null and _win.visible


func toggle() -> void:
	if is_visible():
		close()
	else:
		open()


func sync_frame() -> void:
	if is_visible():
		_sync()
		_update_debug()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_win = Window.new()
	_win.title    = "Settings"
	_win.size     = Vector2i(440, 580)
	_win.min_size = Vector2i(360, 420)
	_win.transparent = true
	_win.borderless = true
	_win.close_requested.connect(close)
	_win.hide()
	add_child(_win)

	# Margin so shadows don't clip against the window edges
	var shadow_pad := MarginContainer.new()
	shadow_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow_pad.add_theme_constant_override("margin_left",   12)
	shadow_pad.add_theme_constant_override("margin_right",  12)
	shadow_pad.add_theme_constant_override("margin_top",    12)
	shadow_pad.add_theme_constant_override("margin_bottom", 12)
	_win.add_child(shadow_pad)
	_content = shadow_pad

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	shadow_pad.add_child(col)

	# ── Custom title bar ──────────────────────────────────────────────
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", StylesUI.glass_box(Color(0.10, 0.11, 0.18, 0.60), 14.0, true))
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

	var close_btn := StylesUI.icon_btn("close", "Close", Vector2(28, 28), close)
	title_row.add_child(close_btn)

	# ── Content area ──────────────────────────────────────────────────
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left",   8)
	content_margin.add_theme_constant_override("margin_right",  8)
	content_margin.add_theme_constant_override("margin_top",    4)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(content_margin)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("tab_fg", StylesUI.glass_box(StylesUI.C_BTN_H, 8.0, true))
	_tabs.add_theme_stylebox_override("tab_bg", StylesUI.glass_box(StylesUI.C_BTN, 8.0, true))
	_tabs.add_theme_stylebox_override("tab_hover", StylesUI.glass_box(StylesUI.C_ACCENT, 8.0, true))
	_tabs.get_tab_bar().tab_alignment = TabBar.ALIGNMENT_CENTER
	var tab_panel := StylesUI.glass_box(Color(0.04, 0.05, 0.09, 0.60), 10.0, false)
	tab_panel.content_margin_left   = 10.0
	tab_panel.content_margin_right  = 10.0
	tab_panel.content_margin_top    = 10.0
	tab_panel.content_margin_bottom = 10.0
	_tabs.add_theme_stylebox_override("panel", tab_panel)
	content_margin.add_child(_tabs)

	_tabs.add_child(_build_general_tab())
	_tabs.add_child(_build_post_tab())
	_tabs.add_child(_build_shaders_tab())
	_tabs.add_child(_build_debug_tab())


# ── General tab ──────────────────────────────────────────────────────────────

func _build_general_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "General"
	vbox.add_theme_constant_override("separation", 5)

	StylesUI.win_section(vbox, "AUDIO SOURCE")

	var source_opt := OptionButton.new()
	source_opt.add_item("File Playback", 0)
	source_opt.add_item("Audio Loopback (Coming Soon)", 1)
	source_opt.set_item_disabled(1, true)
	source_opt.tooltip_text = "Audio Loopback will be available in a future update"
	source_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_opt.focus_mode = Control.FOCUS_NONE
	source_opt.item_selected.connect(func(idx: int) -> void:
		if idx == 1:
			source_opt.selected = 0  # Revert — not implemented yet
	)
	vbox.add_child(source_opt)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "AUTO-SHUFFLE")

	_shuffle_check = CheckBox.new()
	_shuffle_check.text = "Auto-shuffle"
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

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "KEYBOARD SHORTCUTS")

	var keys := Label.new()
	keys.text = "Q / E       previous / next shader\nS             toggle auto-shuffle\nP             toggle post-processing\nF             fullscreen\nSpace       play / pause\nEsc          stop\n← / →       prev / next track"
	keys.add_theme_font_size_override("font_size", 12)
	keys.modulate.a = 0.55
	vbox.add_child(keys)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


# ── Post-Process tab ─────────────────────────────────────────────────────────

func _build_post_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Post-Process"
	vbox.add_theme_constant_override("separation", 6)

	StylesUI.win_section(vbox, "PER-SHADER POST-PROCESSING")

	_pp_shader_label = Label.new()
	_pp_shader_label.text = "Editing: %s" % _visualizer.SHADERS[_visualizer._shader_index].name
	_pp_shader_label.add_theme_font_size_override("font_size", 13)
	_pp_shader_label.modulate.a = 0.80
	vbox.add_child(_pp_shader_label)

	var note := Label.new()
	note.text = "Each shader stores its own post-processing preset.\nSettings are per-shader and saved to disk."
	note.add_theme_font_size_override("font_size", 11)
	note.modulate.a = 0.50
	vbox.add_child(note)

	var pp_toggle := CheckBox.new()
	pp_toggle.text = "Post-process enabled"
	pp_toggle.button_pressed = _visualizer._post_display.visible
	pp_toggle.toggled.connect(func(on: bool):
		_visualizer._post_display.visible = on
	)
	vbox.add_child(pp_toggle)

	StylesUI.win_sep(vbox)

	_pp_sliders.clear()
	_pp_slider(vbox, "Exposure",         "exposure",       0.1,  3.0,  0.01)
	_pp_slider(vbox, "Tone compression", "tonemap_knee",   0.0,  2.0,  0.01)
	_pp_slider(vbox, "Gamma",            "gamma",          0.5,  3.0,  0.01)
	_pp_slider(vbox, "Vignette shadow",  "vignette_dark",  0.0,  1.0,  0.01)
	_pp_slider(vbox, "Film grain",       "grain_strength", 0.0,  0.08, 0.002)
	_pp_slider(vbox, "Loop Reinhard",    "loop_reinhard",  0.0,  3.0,  0.01)

	StylesUI.win_sep(vbox)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var reset_btn := StylesUI.icon_btn("reset", "Reset to defaults", Vector2(32, 28), _reset_post_defaults)
	btn_row.add_child(reset_btn)

	var save_btn := StylesUI.icon_btn("save", "Save settings", Vector2(32, 28), func(): _visualizer.save_settings())
	btn_row.add_child(save_btn)

	vbox.add_child(btn_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


func _pp_slider(parent: VBoxContainer, label: String, param: String,
		lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size.x = 145
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step      = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE

	var val_lbl := Label.new()
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.custom_minimum_size.x = 40
	val_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT

	var initial: float = _get_pp_value(param)
	slider.value   = initial
	val_lbl.text   = "%.2f" % initial

	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v
		_visualizer.update_pp_param(param, v)
	)
	row.add_child(slider)
	row.add_child(val_lbl)
	parent.add_child(row)

	_pp_sliders[param] = { "slider": slider, "val_lbl": val_lbl }


func _get_pp_value(param: String) -> float:
	match param:
		"exposure":       return _visualizer.pp_exposure
		"tonemap_knee":   return _visualizer.pp_tonemap_knee
		"gamma":          return _visualizer.pp_gamma
		"vignette_dark":  return _visualizer.pp_vignette_dark
		"grain_strength": return _visualizer.pp_grain_strength
		"loop_reinhard":  return _visualizer.pp_loop_reinhard
	return 0.0


func _update_pp_sliders() -> void:
	if _pp_shader_label:
		_pp_shader_label.text = "Editing: %s" % _visualizer.SHADERS[_visualizer._shader_index].name
	for param in _pp_sliders:
		var entry: Dictionary = _pp_sliders[param]
		var value: float = _get_pp_value(param)
		(entry["slider"] as HSlider).set_value_no_signal(value)
		(entry["val_lbl"] as Label).text = "%.2f" % value


func _reset_post_defaults() -> void:
	var defaults: Dictionary = _visualizer.PP_DEFAULTS
	_visualizer.pp_exposure       = defaults["exposure"]
	_visualizer.pp_tonemap_knee   = defaults["tonemap_knee"]
	_visualizer.pp_gamma          = defaults["gamma"]
	_visualizer.pp_vignette_dark  = defaults["vignette_dark"]
	_visualizer.pp_grain_strength = defaults["grain_strength"]
	_visualizer.pp_loop_reinhard  = _visualizer._SHADER_REINHARD_DEFAULTS[_visualizer._shader_index]
	_visualizer._save_current_pp_config()
	_update_pp_sliders()


# ── Shaders tab ───────────────────────────────────────────────────────────────

func _build_shaders_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Shaders"
	vbox.add_theme_constant_override("separation", 5)

	StylesUI.win_section(vbox, "ACTIVE SHADERS")

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
		StylesUI.apply_glass_btn(btn)
		vbox.add_child(btn)
		_shader_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


func _on_shader_btn(idx: int) -> void:
	_visualizer._switch(idx)


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

	StylesUI.win_section(vbox, "FREQUENCY BANDS")
	_dbg_row(vbox, "Sub Bass   20–60 Hz",   "sub_bass")
	_dbg_row(vbox, "Bass   60–250 Hz",      "bass")
	_dbg_row(vbox, "Low Mid   250–800 Hz",  "low_mid")
	_dbg_row(vbox, "Mid   800 Hz–4 kHz",    "mid")
	_dbg_row(vbox, "Presence   4–8 kHz",    "presence")
	_dbg_row(vbox, "Treble   8–16 kHz",     "treble")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "PERCUSSION")
	_dbg_row(vbox, "Kick",   "kick")
	_dbg_row(vbox, "Snare",  "snare")
	_dbg_row(vbox, "Hi-Hat", "hihat")
	_dbg_row(vbox, "Beat",   "beat")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "SPECTRAL FLUX")
	_dbg_row(vbox, "Flux Bass",   "flux_bass")
	_dbg_row(vbox, "Flux Mid",    "flux_mid")
	_dbg_row(vbox, "Flux Treble", "flux_treble")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "ENERGY")
	_dbg_row(vbox, "Energy",   "energy")
	_dbg_row(vbox, "Activity", "activity")
	_dbg_row(vbox, "Onset",    "onset")
	_dbg_row(vbox, "Loudness", "loudness")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "MOOD")
	_dbg_row(vbox, "Warmth",     "warmth")
	_dbg_row(vbox, "Brightness", "brightness")
	_dbg_row(vbox, "Density",    "density")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "TIMING")
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
	bar.add_theme_stylebox_override("background", StylesUI.glass_box(Color(0.03, 0.04, 0.08, 0.50), 4.0, false))
	bar.add_theme_stylebox_override("fill", StylesUI.glass_box(Color(0.35, 0.52, 0.85, 0.55), 4.0, false))
	row.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.custom_minimum_size.x     = 46
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	parent.add_child(row)
	_dbg[key] = { "bar": bar, "val": val_lbl }


# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync() -> void:
	# Keep shader radio buttons in sync when Q/E are pressed outside the window
	var idx: int = _visualizer._shader_index
	if idx != _last_shader_idx:
		_last_shader_idx = idx
		for i in _shader_btns.size():
			_shader_btns[i].set_pressed_no_signal(i == idx)
		_update_pp_sliders()
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
