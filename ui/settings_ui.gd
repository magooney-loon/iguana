class_name SettingsUI

extends Node

var _visualizer              # visualizer.gd node (ColorRect inside SubViewport)
var _analyzer:   AudioAnalyzer

# Window
var _win:          Window
var _content:      Control
var _tween:        Tween

# Tabs
var _tabs:            TabContainer
var _shader_dropdown: OptionButton
var _last_shader_idx := -1

# General tab
var _shuffle_check: CheckBox
var _shuffle_spin:  SpinBox

# Post-process tab
var _pp_sliders:            Dictionary = {}
var _pp_shader_label:       Label
var _shader_author_label:   Label
var _shader_website_label:  Label
var _shader_desc_label:     Label
var _shader_desc_clip:      Control
var _shader_desc_tween:     Tween

# Debug tab
var _dbg: Dictionary = {}

# Keymap tab — read-only shortcut reference


func setup(visualizer, analyzer: AudioAnalyzer) -> void:
	_visualizer = visualizer
	_analyzer   = analyzer
	_build()


func open() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var vp     := get_viewport().get_visible_rect().size
	var margin := 16
	var target_x := int(vp.x) - _win.size.x - margin
	var target_y := int((vp.y - _win.size.y) / 2.0)
	_win.position = Vector2i(int(vp.x), target_y)
	_win.show()
	_sync()
	_content.modulate.a = 0.0

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", target_x, 0.30)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_content, "modulate:a", 1.0, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var vp := get_viewport().get_visible_rect().size

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", int(vp.x), 0.22)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
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
	StylesUI.apply_aero(title_bar, true)
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
	tab_panel.shadow_size = 0
	tab_panel.content_margin_left   = 10.0
	tab_panel.content_margin_right  = 10.0
	tab_panel.content_margin_top    = 10.0
	tab_panel.content_margin_bottom = 10.0
	_tabs.add_theme_stylebox_override("panel", tab_panel)
	StylesUI.apply_aero(_tabs, true)
	content_margin.add_child(_tabs)

	# Smooth eased fade on tab content switch
	var _tab_idx := _tabs.current_tab
	_tabs.tab_changed.connect(func(idx: int):
		if idx == _tab_idx:
			return
		_tab_idx = idx
		var content := _tabs.get_current_tab_control()
		if not content:
			return
		content.modulate.a = 0.0
		create_tween()\
			.tween_property(content, "modulate:a", 1.0, 0.30)\
			.set_ease(Tween.EASE_OUT)\
			.set_trans(Tween.TRANS_QUINT)
	)

	_tabs.add_child(_build_general_tab())
	_tabs.add_child(_build_shaders_tab())
	_tabs.add_child(_build_keymap_tab())
	_tabs.add_child(_build_debug_tab())
	_tabs.add_child(_build_about_tab())


# ── General tab ──────────────────────────────────────────────────────────────

func _build_general_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "General"
	vbox.add_theme_constant_override("separation", 5)

	# ── Audio settings ─────────────────────────────────────────────────
	StylesUI.win_section(vbox, "AUDIO SETTINGS")

	var audio_row := HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 8)

	var source_opt := OptionButton.new()
	source_opt.add_item("File Playback", 0)
	source_opt.add_item("Audio Loopback", 1)
	source_opt.set_item_disabled(1, true)
	source_opt.tooltip_text = "Audio Loopback will be available in a future update"
	source_opt.custom_minimum_size.x = 130.0
	source_opt.focus_mode = Control.FOCUS_NONE
	source_opt.item_selected.connect(func(idx: int) -> void:
		if idx == 1:
			source_opt.selected = 0  # Revert — not implemented yet
	)
	audio_row.add_child(source_opt)

	var xf_row := HBoxContainer.new()
	xf_row.add_theme_constant_override("separation", 4)
	var xf_pre := Label.new()
	xf_pre.text = "Crossfade"
	xf_row.add_child(xf_pre)
	var xf_spin := SpinBox.new()
	xf_spin.min_value = 0.5
	xf_spin.max_value = 10.0
	xf_spin.step      = 0.5
	xf_spin.value     = AudioSource.crossfade_duration
	xf_spin.custom_minimum_size.x = 60.0
	xf_spin.suffix    = " sec"
	xf_spin.value_changed.connect(func(v: float):
		AudioSource.crossfade_duration = v
		Config.crossfade_duration = v
		Config.save()
	)
	xf_row.add_child(xf_spin)
	audio_row.add_child(xf_row)

	vbox.add_child(audio_row)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "PLAYER UI")

	var auto_hide_check := CheckBox.new()
	auto_hide_check.text = "Auto-hide player after 2 seconds"
	auto_hide_check.button_pressed = Config.auto_hide_player
	auto_hide_check.toggled.connect(func(on: bool):
		Config.auto_hide_player = on
		Config.save()
	)
	vbox.add_child(auto_hide_check)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "DISPLAY")

	var disp_row := HBoxContainer.new()
	disp_row.add_theme_constant_override("separation", 8)

	var vsync_check := CheckBox.new()
	vsync_check.text = "VSync"
	vsync_check.button_pressed = Config.vsync_enabled
	disp_row.add_child(vsync_check)

	var fps_cap_row := HBoxContainer.new()
	fps_cap_row.add_theme_constant_override("separation", 4)
	var fps_cap_pre := Label.new()
	fps_cap_pre.text = "Max FPS"
	fps_cap_row.add_child(fps_cap_pre)
	var fps_cap_spin := SpinBox.new()
	fps_cap_spin.min_value = 15.0
	fps_cap_spin.max_value = 960.0
	fps_cap_spin.step = 1.0
	fps_cap_spin.value = Config.max_fps
	fps_cap_spin.custom_minimum_size.x = 60.0
	fps_cap_spin.focus_mode = Control.FOCUS_NONE
	fps_cap_spin.editable = not Config.vsync_enabled
	fps_cap_spin.value_changed.connect(func(v: float) -> void:
		Config.max_fps = int(v)
		Engine.max_fps = Config.max_fps
		Config.save()
	)
	fps_cap_row.add_child(fps_cap_spin)
	disp_row.add_child(fps_cap_row)

	vbox.add_child(disp_row)

	vsync_check.toggled.connect(func(on: bool) -> void:
		Config.vsync_enabled = on
		if on:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = Config.max_fps
		fps_cap_spin.editable = not on
		Config.save()
	)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "SHADER SHUFFLE")

	var shuffle_row := HBoxContainer.new()
	shuffle_row.add_theme_constant_override("separation", 8)

	_shuffle_check = CheckBox.new()
	_shuffle_check.text = "Shader shuffle"
	shuffle_row.add_child(_shuffle_check)

	_shuffle_spin = SpinBox.new()
	_shuffle_spin.min_value = 10.0
	_shuffle_spin.max_value = 300.0
	_shuffle_spin.step      = 5.0
	_shuffle_spin.value     = _visualizer.shuffle_interval
	_shuffle_spin.custom_minimum_size.x = 60.0
	_shuffle_spin.editable  = _visualizer._shuffle_on
	_shuffle_spin.suffix    = " seconds"
	_shuffle_spin.value_changed.connect(func(v: float):
		_visualizer.shuffle_interval = v
	)
	shuffle_row.add_child(_shuffle_spin)

	vbox.add_child(shuffle_row)

	_shuffle_check.toggled.connect(func(on: bool):
		_visualizer._shuffle_on    = on
		_visualizer._shuffle_timer = 0.0
		_shuffle_spin.editable = on
	)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	return vbox


# ── Shaders tab ───────────────────────────────────────────────────────────────

func _build_shaders_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Shaders"
	vbox.add_theme_constant_override("separation", 6)

	StylesUI.win_section(vbox, "ACTIVE SHADER")

	_shader_dropdown = OptionButton.new()
	var shaders: Array = _visualizer.SHADERS
	for i in shaders.size():
		_shader_dropdown.add_item(shaders[i].name, i)
	_shader_dropdown.selected = _visualizer._shader_index
	_shader_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shader_dropdown.focus_mode = Control.FOCUS_NONE
	_shader_dropdown.item_selected.connect(func(idx: int):
		_visualizer._switch(idx)
		_update_pp_sliders()
		_update_shader_info()
	)
	vbox.add_child(_shader_dropdown)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "SHADER INFO")

	_shader_author_label = Label.new()
	_shader_author_label.add_theme_font_size_override("font_size", 12)
	_shader_author_label.modulate.a = 0.75
	vbox.add_child(_shader_author_label)

	_shader_website_label = Label.new()
	_shader_website_label.add_theme_font_size_override("font_size", 12)
	_shader_website_label.modulate = Color(0.55, 0.75, 1.0)
	_shader_website_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_shader_website_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_shader_website_label.gui_input.connect(func(event: InputEvent) -> void:
		var url: String = _shader_website_label.get_meta("link_url", "")
		if url.is_empty():
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url)
	)
	_shader_website_label.mouse_entered.connect(func() -> void:
		_shader_website_label.modulate = Color(0.70, 0.88, 1.0)
	)
	_shader_website_label.mouse_exited.connect(func() -> void:
		_shader_website_label.modulate = Color(0.55, 0.75, 1.0)
	)
	vbox.add_child(_shader_website_label)

	_shader_desc_clip = Control.new()
	_shader_desc_clip.clip_contents = true
	_shader_desc_clip.custom_minimum_size.y = 18
	_shader_desc_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_shader_desc_clip)

	_shader_desc_label = Label.new()
	_shader_desc_label.add_theme_font_size_override("font_size", 12)
	_shader_desc_label.modulate.a = 0.75
	_shader_desc_clip.add_child(_shader_desc_label)

	_update_shader_info()

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "POST-PROCESSING")

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

	var btn_spacer := Control.new()
	btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_spacer)

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
	StylesUI.apply_glass_slider(slider, true)

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


func _update_shader_info() -> void:
	var meta: Dictionary = _visualizer.SHADERS[_visualizer._shader_index]
	if _shader_author_label:
		_shader_author_label.text  = "Author:   " + meta.get("author",  "N/A")
	if _shader_website_label:
		var website: String = meta.get("website", "N/A")
		_shader_website_label.text = "Website:  " + website
		if website != "N/A" and not website.is_empty():
			var url := website
			if not url.begins_with("http://") and not url.begins_with("https://"):
				url = "https://" + url
			_shader_website_label.set_meta("link_url", url)
			_shader_website_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			_shader_website_label.set_meta("link_url", "")
			_shader_website_label.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _shader_desc_label:
		_shader_desc_label.text = meta.get("description", "")
		_shader_desc_label.position.x = 0.0
		_restart_desc_marquee()


func _restart_desc_marquee() -> void:
	if _shader_desc_tween and _shader_desc_tween.is_valid():
		_shader_desc_tween.kill()
	if not _shader_desc_label or not _shader_desc_clip:
		return
	if _shader_desc_clip.size.x > 0.0:
		_setup_desc_marquee()
	else:
		_shader_desc_clip.resized.connect(_setup_desc_marquee, CONNECT_ONE_SHOT)


func _setup_desc_marquee() -> void:
	if not _shader_desc_label or not _shader_desc_clip:
		return

	var natural_w := _shader_desc_label.get_combined_minimum_size().x
	var clip_w    := _shader_desc_clip.size.x
	if clip_w <= 0.0:
		return

	_shader_desc_label.size.x = max(natural_w, clip_w)
	_shader_desc_label.position = Vector2.ZERO

	if natural_w > clip_w + 2.0:
		var overflow    := natural_w - clip_w
		var scroll_time := overflow / 28.0
		_shader_desc_tween = create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_shader_desc_tween.tween_interval(2.0)
		_shader_desc_tween.tween_property(_shader_desc_label, "position:x", -overflow, scroll_time)\
			.set_ease(Tween.EASE_IN_OUT)
		_shader_desc_tween.tween_interval(1.5)
		_shader_desc_tween.tween_property(_shader_desc_label, "position:x", 0.0, scroll_time)\
			.set_ease(Tween.EASE_IN_OUT)
		_shader_desc_tween.tween_interval(2.0)


func _update_pp_sliders() -> void:
	_update_shader_info()
	for param in _pp_sliders:
		var entry: Dictionary = _pp_sliders[param]
		var value: float = _get_pp_value(param)
		(entry["slider"] as HSlider).set_value_no_signal(value)
		(entry["val_lbl"] as Label).text = "%.2f" % value


func _reset_post_defaults() -> void:
	var idx: int = _visualizer._shader_index
	var shader_meta: Dictionary = _visualizer.SHADERS[idx]
	var global: Dictionary = _visualizer.PP_DEFAULTS
	_visualizer.pp_exposure       = shader_meta.get("exposure",       global["exposure"])
	_visualizer.pp_tonemap_knee   = shader_meta.get("tonemap_knee",   global["tonemap_knee"])
	_visualizer.pp_gamma          = shader_meta.get("gamma",          global["gamma"])
	_visualizer.pp_vignette_dark  = shader_meta.get("vignette_dark",  global["vignette_dark"])
	_visualizer.pp_grain_strength = shader_meta.get("grain_strength", global["grain_strength"])
	_visualizer.pp_loop_reinhard  = shader_meta.get("loop_reinhard",  global["loop_reinhard"])
	_visualizer._save_current_pp_config()
	_update_pp_sliders()


# ── Keymap tab ────────────────────────────────────────────────────────────────

func _build_keymap_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Keymap"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_right", 4)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	pad.add_child(vbox)

	StylesUI.win_section(vbox, "KEYBOARD SHORTCUTS")

	var actions: Array[String] = Keymap.get_all_actions()
	for action_id in actions:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = Keymap.get_action_name(action_id)
		label.add_theme_font_size_override("font_size", 12)
		label.custom_minimum_size.x = 185
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)

		var key_label := Label.new()
		key_label.text = Keymap.key_to_label(Keymap.get_key(action_id))
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.custom_minimum_size.x = 80
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.modulate = Color(0.7, 0.82, 1.0)
		row.add_child(key_label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		vbox.add_child(row)

	return scroll


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

	StylesUI.win_section(vbox, "PERFORMANCE")
	_dbg_row(vbox, "FPS", "fps", 360.0)

	StylesUI.win_sep(vbox)
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
	# Keep shader dropdown in sync when Q/E are pressed outside the window
	var idx: int = _visualizer._shader_index
	if idx != _last_shader_idx:
		_last_shader_idx = idx
		if _shader_dropdown:
			_shader_dropdown.selected = idx
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
		"fps": float(Engine.get_frames_per_second()),
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
			var fmt := "%.0f" if key in ["bpm", "fps"] else "%.3f"
			(entry.val as Label).text = fmt % v


# ── About tab ─────────────────────────────────────────────────────────────────

func _build_about_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "About"
	vbox.add_theme_constant_override("separation", 6)

	# Logo
	var logo_tex := load("res://icon.webp") as Texture2D
	if logo_tex:
		var logo := TextureRect.new()
		logo.texture      = logo_tex
		logo.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(80, 80)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(logo)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = "Iguana"
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.modulate = Color(0.75, 0.88, 1.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_lbl)

	# Tagline
	var tag_lbl := Label.new()
	tag_lbl.text = "It really licks the eyeball, yeah..."
	tag_lbl.add_theme_font_size_override("font_size", 12)
	tag_lbl.modulate.a = 0.65
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tag_lbl)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "DEVELOPER")

	_about_row(vbox, "Developer", "Magooney")
	_about_row(vbox, "Team", "MyMoonEnt")
	_about_row(vbox, "Engine",    "Godot 4")
	_about_row(vbox, "License",   "AGPL-v3")

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "LINKS")

	var gh_row := HBoxContainer.new()
	gh_row.add_theme_constant_override("separation", 8)
	var gh_lbl := Label.new()
	gh_lbl.text = "GitHub"
	gh_lbl.add_theme_font_size_override("font_size", 12)
	gh_lbl.modulate.a = 0.55
	gh_lbl.custom_minimum_size.x = 80
	gh_row.add_child(gh_lbl)
	gh_row.add_child(StylesUI.make_link_label("magooney-loon/iguana", "https://github.com/magooney-loon/iguana"))
	vbox.add_child(gh_row)

	var x_row := HBoxContainer.new()
	x_row.add_theme_constant_override("separation", 8)
	var x_lbl := Label.new()
	x_lbl.text = "X / Twitter"
	x_lbl.add_theme_font_size_override("font_size", 12)
	x_lbl.modulate.a = 0.55
	x_lbl.custom_minimum_size.x = 80
	x_row.add_child(x_lbl)
	x_row.add_child(StylesUI.make_link_label("@MyMoonEnt", "https://x.com/MyMoonEnt"))
	vbox.add_child(x_row)

	var rd_row := HBoxContainer.new()
	rd_row.add_theme_constant_override("separation", 8)
	var rd_lbl := Label.new()
	rd_lbl.text = "Reddit"
	rd_lbl.add_theme_font_size_override("font_size", 12)
	rd_lbl.modulate.a = 0.55
	rd_lbl.custom_minimum_size.x = 80
	rd_row.add_child(rd_lbl)
	rd_row.add_child(StylesUI.make_link_label("u/SubjectHealthy2409", "https://www.reddit.com/user/SubjectHealthy2409/"))
	vbox.add_child(rd_row)

	var em_row := HBoxContainer.new()
	em_row.add_theme_constant_override("separation", 8)
	var em_lbl := Label.new()
	em_lbl.text = "Contact"
	em_lbl.add_theme_font_size_override("font_size", 12)
	em_lbl.modulate.a = 0.55
	em_lbl.custom_minimum_size.x = 80
	em_row.add_child(em_lbl)
	em_row.add_child(StylesUI.make_link_label("contact@magooney.org", "mailto:contact@magooney.org"))
	vbox.add_child(em_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Version stamp
	var ver_lbl := Label.new()
	ver_lbl.text = "v0.1.0"
	ver_lbl.add_theme_font_size_override("font_size", 11)
	ver_lbl.modulate.a = 0.35
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(ver_lbl)

	return vbox


func _about_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate.a = 0.55
	lbl.custom_minimum_size.x = 80
	row.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 12)
	val.modulate = Color(0.75, 0.88, 1.0)
	row.add_child(val)

	parent.add_child(row)
