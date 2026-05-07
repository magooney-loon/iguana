class_name SettingsUI

extends Node

var _visualizer              # visualizer.gd node (ColorRect inside SubViewport)
var _analyzer:   AudioAnalyzer

# Window
var _win:          Window
var _engine_theme: Theme
var _content:      Control
var _tween:        Tween

# Tabs
var _tabs:              TabContainer
var _shader_btn:        Button
var _tab_idx:           int = 0
var _last_shader_idx  := -1

# Shader picker modal
var _picker_win:        Window
var _picker_content:    Control
var _picker_tween:      Tween
var _picker_search:     LineEdit
var _picker_list:        VBoxContainer
var _picker_scroll:     ScrollContainer
var _picker_fav_only:   bool   = false
var _picker_fav_btn:    Button
var _picker_entries:    Array  = []   # [{btn, star_btn, idx, stem}]

# General tab — Appearance dropdowns
var _skin_opt:   OptionButton
var _theme_opt:  OptionButton
var _style_opt:  OptionButton
var _icons_opt:  OptionButton
var _skins: Array[String] = []
var _shuffle_check: CheckBox
var _shuffle_spin:  SpinBox

# Post-process tab
var _pp_sliders:            Dictionary = {}
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
	var st     := StylesUI.style()
	var vp     := get_viewport().get_visible_rect().size
	var target_x := int(vp.x) - _win.size.x - 16
	var target_y := int((vp.y - _win.size.y) / 2.0)
	_win.position = Vector2i(int(vp.x), target_y)
	_win.show()
	_sync()
	_content.modulate.a = 0.0

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", target_x, st.anim_win_open_duration)\
		.set_ease(st.anim_win_open_ease).set_trans(st.anim_win_open_trans)
	_tween.tween_property(_content, "modulate:a", 1.0, st.anim_win_fade_in)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func close() -> void:
	_close_shader_picker()
	if _tween and _tween.is_valid():
		_tween.kill()
	var st := StylesUI.style()
	var vp := get_viewport().get_visible_rect().size

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", int(vp.x), st.anim_win_close_duration)\
		.set_ease(st.anim_win_close_ease).set_trans(st.anim_win_close_trans)
	_tween.tween_property(_content, "modulate:a", 0.0, st.anim_win_fade_out)\
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

	_engine_theme = Theme.new()
	_win.theme = _engine_theme
	_apply_engine_theme()

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
	StylesUI.track_glass_panel(title_bar, func(p: Control) -> void:
		p.add_theme_stylebox_override("panel", StylesUI.glass_box(StylesUI.theme().c_title_bar, 14.0, true))
	)
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
	StylesUI.track_label(title_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
		l.modulate = StylesUI.theme().c_text_hi
	)
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
	StylesUI.track_glass_panel(_tabs, func(p: Control) -> void:
		var t := StylesUI.theme()
		p.add_theme_stylebox_override("tab_fg",    StylesUI.glass_box(t.c_tab_fg,    8.0, true))
		p.add_theme_stylebox_override("tab_bg",    StylesUI.glass_box(t.c_tab_bg,    8.0, true))
		p.add_theme_stylebox_override("tab_hover", StylesUI.glass_box(t.c_tab_hover, 8.0, true))
		p.add_theme_color_override("font_color",          t.c_text_dim)
		p.add_theme_color_override("font_hover_color",     t.c_text_hi)
		p.add_theme_color_override("font_selected_color",  t.c_text_hi)
		p.add_theme_font_size_override("font_size", t.font_title)
		var tab_bar := p.get_tab_bar() as TabBar
		if tab_bar:
			tab_bar.add_theme_color_override("font_color",          t.c_text_dim)
			tab_bar.add_theme_color_override("font_hover_color",     t.c_text_hi)
			tab_bar.add_theme_color_override("font_selected_color",  t.c_text_hi)
			tab_bar.add_theme_font_size_override("font_size", t.font_title)
		var tab_box := StylesUI.glass_box(t.c_panel_bg, 10.0, false)
		tab_box.shadow_size = 0
		tab_box.content_margin_left   = 10.0
		tab_box.content_margin_right  = 10.0
		tab_box.content_margin_top    = 10.0
		tab_box.content_margin_bottom = 10.0
		p.add_theme_stylebox_override("panel", tab_box)
	)
	_tabs.get_tab_bar().tab_alignment = TabBar.ALIGNMENT_CENTER
	StylesUI.apply_aero(_tabs, true)
	content_margin.add_child(_tabs)

	# Smooth eased fade on tab content switch
	_tab_idx = _tabs.current_tab
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

	StylesUI.on_reload(func() -> void:
		if is_instance_valid(_win):
			_apply_engine_theme()
	)


func _apply_engine_theme() -> void:
	if _engine_theme == null:
		return
	var t := StylesUI.theme()
	_engine_theme.set_color("font_color", "CheckBox", t.c_text_hi)
	_engine_theme.set_color("font_color", "OptionButton", t.c_text_hi)
	_engine_theme.set_color("font_hover_color", "OptionButton", t.c_text_hi)
	_engine_theme.set_color("font_pressed_color", "OptionButton", t.c_text_hi)
	_engine_theme.set_color("font_color", "PopupMenu", t.c_text_hi)
	_engine_theme.set_color("font_hover_color", "PopupMenu", t.c_text_hi)
	# Apply skin font to all built-in controls, or clear back to default
	if StylesUI.active_font != null:
		_engine_theme.default_font = StylesUI.active_font
	else:
		_engine_theme.default_font = null


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
	StylesUI.apply_dropdown(source_opt)
	audio_row.add_child(source_opt)

	var xf_row := HBoxContainer.new()
	xf_row.add_theme_constant_override("separation", 4)
	var xf_pre := Label.new()
	xf_pre.text = "Crossfade"
	StylesUI.track_label(xf_pre, func(l: Label) -> void:
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
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
	StylesUI.win_section(vbox, "APPEARANCE")

	# ── Skin preset ─────────────────────────────────────────────────
	_skins = StylesUI.discover_skins()

	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 8)
	var skin_pre := Label.new()
	skin_pre.text = "Skin"
	StylesUI.track_label(skin_pre, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
	skin_pre.custom_minimum_size.x = 48
	skin_row.add_child(skin_pre)
	_skin_opt = OptionButton.new()
	_skin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_opt.focus_mode = Control.FOCUS_NONE
	_rebuild_skin_dropdown()
	_skin_opt.item_selected.connect(func(idx: int) -> void:
		# Index 0 is always "Custom" if present, skins start after
		var offset := 1 if _skin_opt.get_item_text(0) == "Custom" else 0
		if offset == 1 and idx == 0:
			return  # "Custom" placeholder — do nothing
		var chosen := _skins[idx - offset]
		Config.skin_name      = chosen
		Config.theme_name     = chosen
		Config.style_name     = chosen
		Config.icon_pack_name = chosen
		Config.save()
		StylesUI.load_skin(chosen)
		StylesUI.reload_all()
		_sync_sub_dropdowns()
	)
	StylesUI.apply_dropdown(_skin_opt)
	skin_row.add_child(_skin_opt)
	vbox.add_child(skin_row)

	# ── Individual overrides ────────────────────────────────────────

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 8)
	var theme_pre := Label.new()
	theme_pre.text = "Theme"
	StylesUI.track_label(theme_pre, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
	theme_pre.custom_minimum_size.x = 48
	theme_row.add_child(theme_pre)
	_theme_opt = OptionButton.new()
	_theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_theme_opt.focus_mode = Control.FOCUS_NONE
	for _sk in _skins:
		_theme_opt.add_item(_sk)
	var _ti := _skins.find(Config.theme_name)
	if _ti >= 0:
		_theme_opt.selected = _ti
	_theme_opt.item_selected.connect(func(idx: int) -> void:
		Config.theme_name = _skins[idx]
		_update_custom_state()
		Config.save()
		StylesUI.load_theme(Config.theme_name)
		StylesUI.reload_all()
	)
	StylesUI.apply_dropdown(_theme_opt)
	theme_row.add_child(_theme_opt)
	vbox.add_child(theme_row)

	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 8)
	var style_pre := Label.new()
	style_pre.text = "Style"
	StylesUI.track_label(style_pre, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
	style_pre.custom_minimum_size.x = 48
	style_row.add_child(style_pre)
	_style_opt = OptionButton.new()
	_style_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_opt.focus_mode = Control.FOCUS_NONE
	for _sk in _skins:
		_style_opt.add_item(_sk)
	var _sti := _skins.find(Config.style_name)
	if _sti >= 0:
		_style_opt.selected = _sti
	_style_opt.item_selected.connect(func(idx: int) -> void:
		Config.style_name = _skins[idx]
		_update_custom_state()
		Config.save()
		StylesUI.load_style(Config.style_name)
		StylesUI.reload_all()
	)
	StylesUI.apply_dropdown(_style_opt)
	style_row.add_child(_style_opt)
	vbox.add_child(style_row)

	var icons_row := HBoxContainer.new()
	icons_row.add_theme_constant_override("separation", 8)
	var icons_pre := Label.new()
	icons_pre.text = "Icons"
	StylesUI.track_label(icons_pre, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
	icons_pre.custom_minimum_size.x = 48
	icons_row.add_child(icons_pre)
	_icons_opt = OptionButton.new()
	_icons_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icons_opt.focus_mode = Control.FOCUS_NONE
	for _sk in _skins:
		_icons_opt.add_item(_sk)
	var _ipi := _skins.find(Config.icon_pack_name)
	if _ipi >= 0:
		_icons_opt.selected = _ipi
	_icons_opt.item_selected.connect(func(idx: int) -> void:
		Config.icon_pack_name = _skins[idx]
		_update_custom_state()
		Config.save()
		StylesUI.load_icons(Config.icon_pack_name)
		StylesUI.reload_all()
	)
	StylesUI.apply_dropdown(_icons_opt)
	icons_row.add_child(_icons_opt)
	vbox.add_child(icons_row)

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
	StylesUI.track_label(fps_cap_pre, func(l: Label) -> void:
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
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
	_shuffle_spin.custom_minimum_size.x = 72.0
	_shuffle_spin.editable  = _visualizer._shuffle_on
	_shuffle_spin.suffix    = " sec"
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

	_shader_btn = Button.new()
	_shader_btn.text = _visualizer.SHADERS[_visualizer._shader_index].name
	_shader_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shader_btn.focus_mode = Control.FOCUS_NONE
	_shader_btn.pressed.connect(_open_shader_picker)
	StylesUI.apply_glass_btn(_shader_btn)
	vbox.add_child(_shader_btn)

	StylesUI.win_sep(vbox)
	StylesUI.win_section(vbox, "SHADER INFO")

	_shader_author_label = Label.new()
	StylesUI.track_label(_shader_author_label, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_info_text
	)
	vbox.add_child(_shader_author_label)

	_shader_website_label = Label.new()
	StylesUI.track_label(_shader_website_label, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate = StylesUI.theme().c_link
	)
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
		_shader_website_label.modulate = StylesUI.theme().c_link_h
	)
	_shader_website_label.mouse_exited.connect(func() -> void:
		_shader_website_label.modulate = StylesUI.theme().c_link
	)
	vbox.add_child(_shader_website_label)

	_shader_desc_clip = Control.new()
	_shader_desc_clip.clip_contents = true
	_shader_desc_clip.custom_minimum_size.y = 18
	_shader_desc_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_shader_desc_clip)

	_shader_desc_label = Label.new()
	StylesUI.track_label(_shader_desc_label, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_info_text
	)
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
	StylesUI.track_label(lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
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
	StylesUI.track_label(val_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	)
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
		if not _shader_desc_clip.resized.is_connected(_setup_desc_marquee):
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


# ── Shader Picker Modal ─────────────────────────────────────────────────────

const PICKER_WIDTH  := 420
const PICKER_HEIGHT := 480
const PICKER_ROW_H  := 38

func _build_shader_picker() -> void:
	_picker_win = Window.new()
	_picker_win.title       = "Select Shader"
	_picker_win.size        = Vector2i(PICKER_WIDTH, PICKER_HEIGHT)
	_picker_win.min_size    = Vector2i(320, 280)
	_picker_win.transparent = true
	_picker_win.borderless  = true
	_picker_win.close_requested.connect(_close_shader_picker)
	_picker_win.hide()
	_win.add_child(_picker_win)

	var shadow_pad := MarginContainer.new()
	shadow_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow_pad.add_theme_constant_override("margin_left",   10)
	shadow_pad.add_theme_constant_override("margin_right",  10)
	shadow_pad.add_theme_constant_override("margin_top",    10)
	shadow_pad.add_theme_constant_override("margin_bottom", 10)
	_picker_win.add_child(shadow_pad)
	_picker_content = shadow_pad

	var bg := PanelContainer.new()
	StylesUI.track_glass_panel(bg, func(p: Control) -> void:
		p.add_theme_stylebox_override("panel", StylesUI.glass_box(StylesUI.theme().c_glass, 14.0, true))
	)
	StylesUI.apply_aero(bg, true)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.pivot_offset = Vector2(PICKER_WIDTH / 2.0, PICKER_HEIGHT / 2.0)
	shadow_pad.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	var col_margin := MarginContainer.new()
	col_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	col_margin.add_theme_constant_override("margin_left",   12)
	col_margin.add_theme_constant_override("margin_right",  12)
	col_margin.add_theme_constant_override("margin_top",    10)
	col_margin.add_theme_constant_override("margin_bottom", 10)
	bg.add_child(col_margin)
	col_margin.add_child(col)

	# ── Header row (title + close) ────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	col.add_child(header)

	var title := Label.new()
	title.text = "Select Shader"
	StylesUI.track_label(title, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
		l.modulate = StylesUI.theme().c_text_hi
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := StylesUI.icon_btn("close", "Close", Vector2(26, 26), _close_shader_picker)
	header.add_child(close_btn)

	StylesUI.win_sep(col)

	# ── Search bar ────────────────────────────────────────────────────
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	col.add_child(search_row)

	_picker_search = LineEdit.new()
	_picker_search.placeholder_text = "Search by name or author..."
	_picker_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_search.focus_mode = Control.FOCUS_CLICK
	_picker_search.clear_button_enabled = true
	StylesUI.track_glass_panel(_picker_search, func(p: Control) -> void:
		var sb := StylesUI.glass_box(StylesUI.theme().c_btn, 6.0, true)
		sb.content_margin_left   = 8.0
		sb.content_margin_right  = 8.0
		sb.content_margin_top    = 5.0
		sb.content_margin_bottom = 5.0
		p.add_theme_stylebox_override("normal", sb)
		var sbf := StylesUI.glass_box(StylesUI.theme().c_btn_h, 6.0, true)
		sbf.content_margin_left   = 8.0
		sbf.content_margin_right  = 8.0
		sbf.content_margin_top    = 5.0
		sbf.content_margin_bottom = 5.0
		p.add_theme_stylebox_override("focus", sbf)
	)
	_picker_search.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	_picker_search.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	_picker_search.add_theme_color_override("font_placeholder_color", StylesUI.theme().c_text_dim)
	_picker_search.add_theme_color_override("caret_color", StylesUI.theme().c_text_hi)
	_picker_search.text_changed.connect(_on_picker_search)
	search_row.add_child(_picker_search)

	# Favorites toggle button
	_picker_fav_btn = Button.new()
	_picker_fav_btn.tooltip_text = "Show favorites only"
	_picker_fav_btn.toggle_mode = true
	_picker_fav_btn.button_pressed = false
	_picker_fav_btn.custom_minimum_size = Vector2(32, 28)
	_picker_fav_btn.focus_mode = Control.FOCUS_NONE
	var star_tex := StylesUI.load_icon("star")
	if star_tex:
		_picker_fav_btn.icon = star_tex
		_picker_fav_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_fav_btn.expand_icon = true
	StylesUI.apply_glass_btn(_picker_fav_btn)
	_picker_fav_btn.toggled.connect(_on_picker_fav_toggle)
	search_row.add_child(_picker_fav_btn)

	StylesUI.win_sep(col)

	# ── Scrollable shader list ────────────────────────────────────────
	_picker_scroll = ScrollContainer.new()
	_picker_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_picker_scroll)

	_picker_list = VBoxContainer.new()
	_picker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_list.add_theme_constant_override("separation", 2)
	_picker_scroll.add_child(_picker_list)

	# Build entries
	_picker_entries.clear()
	var shaders: Array = _visualizer.SHADERS
	for i in shaders.size():
		var meta: Dictionary = shaders[i]
		var stem: String = meta.get("path", "").get_file().get_basename()

		var row := PanelContainer.new()
		StylesUI.track_glass_panel(row, func(p: Control) -> void:
			var sb := StylesUI.glass_box(StylesUI.theme().c_btn, 6.0, true)
			sb.content_margin_left   = 6.0
			sb.content_margin_right  = 6.0
			sb.content_margin_top    = 5.0
			sb.content_margin_bottom = 5.0
			sb.border_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(0)
			p.add_theme_stylebox_override("panel", sb)
		)
		row.custom_minimum_size.y = PICKER_ROW_H
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_picker_list.add_child(row)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		row.add_child(hbox)

		# Star / favorite button
		var star_btn := Button.new()
		star_btn.custom_minimum_size = Vector2(28, 28)
		star_btn.focus_mode = Control.FOCUS_NONE
		star_btn.toggle_mode = false
		star_btn.icon = star_tex
		star_btn.expand_icon = true
		star_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var is_fav := stem in Config.favorite_shaders
		star_btn.modulate.a = 1.0 if is_fav else 0.3
		# Flat icon-only style — no padding that crushes the star
		var star_n := StyleBoxFlat.new()
		star_n.bg_color = Color(0, 0, 0, 0)
		star_n.set_border_width_all(0)
		star_n.set_corner_radius_all(4)
		star_n.content_margin_left   = 2.0
		star_n.content_margin_right  = 2.0
		star_n.content_margin_top    = 2.0
		star_n.content_margin_bottom = 2.0
		var star_h := star_n.duplicate()
		star_h.bg_color = Color(1, 1, 1, 0.06)
		var star_p := star_n.duplicate()
		star_p.bg_color = Color(1, 1, 1, 0.03)
		star_btn.add_theme_stylebox_override("normal",  star_n)
		star_btn.add_theme_stylebox_override("hover",   star_h)
		star_btn.add_theme_stylebox_override("pressed", star_p)
		var captured_idx := i
		var captured_stem := stem
		star_btn.pressed.connect(func() -> void:
			_toggle_favorite(captured_stem)
		)
		hbox.add_child(star_btn)

		# Shader name + author
		var info_col := VBoxContainer.new()
		info_col.add_theme_constant_override("separation", 0)
		info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_col)

		var name_lbl := Label.new()
		name_lbl.text = meta.get("name", stem)
		StylesUI.track_label(name_lbl, func(l: Label) -> void:
			l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
			l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
		)
		info_col.add_child(name_lbl)

		var author_lbl := Label.new()
		author_lbl.text = meta.get("author", "")
		StylesUI.track_label(author_lbl, func(l: Label) -> void:
			l.add_theme_font_size_override("font_size", StylesUI.theme().font_section)
			l.modulate.a = StylesUI.theme().a_info_text
		)
		info_col.add_child(author_lbl)

		var entry := {
			"row":        row,
			"star_btn":   star_btn,
			"name_lbl":   name_lbl,
			"author_lbl": author_lbl,
			"idx":        i,
			"stem":       stem,
		}
		_picker_entries.append(entry)

		# Click on row → select shader
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_select_shader_from_picker(captured_idx)
		)


func _open_shader_picker() -> void:
	if _picker_win == null:
		_build_shader_picker()

	if _picker_tween and _picker_tween.is_valid():
		_picker_tween.kill()

	# Center on main viewport
	var vp := get_viewport().get_visible_rect()
	var win_size := Vector2(PICKER_WIDTH, PICKER_HEIGHT)
	_picker_win.position = Vector2i(
		int(vp.position.x + (vp.size.x - win_size.x) / 2.0),
		int(vp.position.y + (vp.size.y - win_size.y) / 2.0)
	)
	_picker_win.size = Vector2i(int(win_size.x), int(win_size.y))

	# Reset search
	_picker_search.text = ""
	_picker_fav_only = false
	_picker_fav_btn.button_pressed = false
	_refresh_picker_list()

	# Animate in — scale up + fade
	var st := StylesUI.style()
	_picker_content.modulate.a = 0.0
	_picker_content.scale = Vector2(0.92, 0.92)
	_picker_win.show()

	_picker_tween = create_tween().set_parallel(true)
	_picker_tween.tween_property(_picker_content, "scale", Vector2.ONE, st.anim_win_open_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_picker_tween.tween_property(_picker_content, "modulate:a", 1.0, st.anim_win_fade_in)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_picker_search.grab_focus()


func _close_shader_picker() -> void:
	if not _picker_win or not _picker_win.visible:
		return

	if _picker_tween and _picker_tween.is_valid():
		_picker_tween.kill()

	var st := StylesUI.style()
	_picker_tween = create_tween().set_parallel(true)
	_picker_tween.tween_property(_picker_content, "scale", Vector2(0.92, 0.92), st.anim_win_close_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_picker_tween.tween_property(_picker_content, "modulate:a", 0.0, st.anim_win_fade_out)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_picker_tween.set_parallel(false)
	_picker_tween.tween_callback(_picker_win.hide)


func _select_shader_from_picker(idx: int) -> void:
	_visualizer._switch(idx)
	_shader_btn.text = _visualizer.SHADERS[idx].name
	_update_pp_sliders()
	_update_shader_info()
	_close_shader_picker()


func _toggle_favorite(stem: String) -> void:
	if stem in Config.favorite_shaders:
		Config.favorite_shaders.erase(stem)
	else:
		Config.favorite_shaders.append(stem)
	Config.save()
	_refresh_picker_star_states()
	if _picker_fav_only:
		_refresh_picker_list()


func _refresh_picker_star_states() -> void:
	for entry in _picker_entries:
		var is_fav: bool = entry.stem in Config.favorite_shaders
		entry.star_btn.modulate.a = 1.0 if is_fav else 0.3


func _on_picker_search(_text: String) -> void:
	_refresh_picker_list()


func _on_picker_fav_toggle(on: bool) -> void:
	_picker_fav_only = on
	_refresh_picker_list()


func _refresh_picker_list() -> void:
	var query := _picker_search.text.strip_edges().to_lower() if _picker_search else ""
	var shaders: Array = _visualizer.SHADERS

	for entry in _picker_entries:
		var meta: Dictionary = shaders[entry.idx]
		var sname:  String = meta.get("name", "").to_lower()
		var author: String = meta.get("author", "").to_lower()
		var stem:  String = (entry.stem as String).to_lower()

		var matches_search := query.is_empty() or sname.find(query) >= 0 or author.find(query) >= 0 or stem.find(query) >= 0
		var matches_fav: bool = (not _picker_fav_only) or (entry.stem in Config.favorite_shaders)

		entry.row.visible = matches_search and matches_fav

		# Highlight active shader row
		var is_active: bool = entry.idx == _visualizer._shader_index
		var active_sb := StylesUI.glass_box(StylesUI.theme().c_active_row, 6.0, false)
		active_sb.content_margin_left   = 6.0
		active_sb.content_margin_right  = 6.0
		active_sb.content_margin_top    = 5.0
		active_sb.content_margin_bottom = 5.0
		active_sb.border_color = Color(0, 0, 0, 0)
		active_sb.set_border_width_all(0)
		if is_active and entry.row.visible:
			entry.row.add_theme_stylebox_override("panel", active_sb)
		else:
			var idle_sb := StylesUI.glass_box(StylesUI.theme().c_btn, 6.0, true)
			idle_sb.content_margin_left   = 6.0
			idle_sb.content_margin_right  = 6.0
			idle_sb.content_margin_top    = 5.0
			idle_sb.content_margin_bottom = 5.0
			idle_sb.border_color = Color(0, 0, 0, 0)
			idle_sb.set_border_width_all(0)
			entry.row.add_theme_stylebox_override("panel", idle_sb)


# ── Keymap tab ────────────────────────────────────────────────────────────────

func _build_keymap_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Keymap"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_right", 2)
	pad.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	pad.add_child(vbox)

	StylesUI.win_section(vbox, "KEYBOARD SHORTCUTS")

	var actions: Array[String] = Keymap.get_all_actions()
	for i in actions.size():
		var action_id := actions[i]
		var is_zebra := i % 2 == 1

		var row := PanelContainer.new()
		if is_zebra:
			StylesUI.track_glass_panel(row, func(p: Control) -> void:
				var zebra := StylesUI.glass_box(StylesUI.theme().c_zebra, 5.0, false)
				zebra.shadow_size  = 0
				zebra.border_color = Color(0, 0, 0, 0)
				zebra.set_border_width_all(0)
				zebra.content_margin_left   = 6.0
				zebra.content_margin_right  = 6.0
				zebra.content_margin_top    = 3.0
				zebra.content_margin_bottom = 3.0
				p.add_theme_stylebox_override("panel", zebra)
			)
		else:
			var m := StyleBoxFlat.new()
			m.bg_color = Color(0, 0, 0, 0)
			m.content_margin_left   = 6.0
			m.content_margin_right  = 6.0
			m.content_margin_top    = 3.0
			m.content_margin_bottom = 3.0
			row.add_theme_stylebox_override("panel", m)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = Keymap.get_action_name(action_id)
		StylesUI.track_label(label, func(l: Label) -> void:
			l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
			l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
		)
		label.custom_minimum_size.x = 185
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(label)

		var key_label := Label.new()
		key_label.text = Keymap.key_to_label(Keymap.get_key(action_id))
		StylesUI.track_label(key_label, func(l: Label) -> void:
			l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
			l.modulate = StylesUI.theme().c_text_hi
		)
		key_label.custom_minimum_size.x = 80
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(key_label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)

		row.add_child(hbox)
		vbox.add_child(row)

	# End for loop

	return scroll


# ── Debug tab ─────────────────────────────────────────────────────────────────

func _build_debug_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Debug"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 2)
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
	StylesUI.track_label(lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.add_theme_color_override("font_color", StylesUI.theme().c_text_hi)
	)
	lbl.custom_minimum_size.x = 170
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value  = 0.0
	bar.max_value  = max_val
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size   = Vector2(80, 14)
	bar.show_percentage = false
	StylesUI.track_glass_panel(bar, func(p: Control) -> void:
		p.add_theme_stylebox_override("background", StylesUI.glass_box(StylesUI.theme().c_dbg_bg, 4.0, false))
		p.add_theme_stylebox_override("fill", StylesUI.glass_box(StylesUI.theme().c_dbg_fill, 4.0, false))
	)
	row.add_child(bar)

	var val_lbl := Label.new()
	StylesUI.track_label(val_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	)
	val_lbl.custom_minimum_size.x     = 46
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	parent.add_child(row)
	_dbg[key] = { "bar": bar, "val": val_lbl }


# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync() -> void:
	# Keep shader button in sync when Q/E are pressed outside the window
	var idx: int = _visualizer._shader_index
	if idx != _last_shader_idx:
		_last_shader_idx = idx
		if _shader_btn:
			_shader_btn.text = _visualizer.SHADERS[idx].name
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
	StylesUI.track_label(name_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_notification)
		l.modulate = StylesUI.theme().c_text_hi
	)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_lbl)

	# Tagline
	var tag_lbl := Label.new()
	tag_lbl.text = "It really licks the eyeball, yeah..."
	StylesUI.track_label(tag_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_tagline
	)
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
	StylesUI.track_label(gh_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_label_text
	)
	gh_lbl.custom_minimum_size.x = 80
	gh_row.add_child(gh_lbl)
	gh_row.add_child(StylesUI.make_link_label("magooney-loon/iguana", "https://github.com/magooney-loon/iguana"))
	vbox.add_child(gh_row)

	var x_row := HBoxContainer.new()
	x_row.add_theme_constant_override("separation", 8)
	var x_lbl := Label.new()
	x_lbl.text = "X / Twitter"
	StylesUI.track_label(x_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_label_text
	)
	x_lbl.custom_minimum_size.x = 80
	x_row.add_child(x_lbl)
	x_row.add_child(StylesUI.make_link_label("@MyMoonEnt", "https://x.com/MyMoonEnt"))
	vbox.add_child(x_row)

	var rd_row := HBoxContainer.new()
	rd_row.add_theme_constant_override("separation", 8)
	var rd_lbl := Label.new()
	rd_lbl.text = "Reddit"
	StylesUI.track_label(rd_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_label_text
	)
	rd_lbl.custom_minimum_size.x = 80
	rd_row.add_child(rd_lbl)
	rd_row.add_child(StylesUI.make_link_label("u/SubjectHealthy2409", "https://www.reddit.com/user/SubjectHealthy2409/"))
	vbox.add_child(rd_row)

	var em_row := HBoxContainer.new()
	em_row.add_theme_constant_override("separation", 8)
	var em_lbl := Label.new()
	em_lbl.text = "Contact"
	StylesUI.track_label(em_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_label_text
	)
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
	StylesUI.track_label(ver_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_version)
		l.modulate.a = StylesUI.theme().a_version
	)
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(ver_lbl)

	return vbox


func _about_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label
	StylesUI.track_label(lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_label_text
	)
	lbl.custom_minimum_size.x = 80
	row.add_child(lbl)

	var val := Label.new()
	val.text = value
	StylesUI.track_label(val, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate = StylesUI.theme().c_text_hi
	)
	row.add_child(val)

	parent.add_child(row)


func _discover_tres(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			names.append(f.get_basename())
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func _discover_dirs(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir() and not f.begins_with("."):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## Check if individual settings differ from the skin preset.
## Updates Config.skin_name and rebuilds the skin dropdown to show Custom or the skin.
func _update_custom_state() -> void:
	if Config.theme_name == Config.style_name and Config.style_name == Config.icon_pack_name:
		Config.skin_name = Config.theme_name
	else:
		Config.skin_name = "custom"
	_rebuild_skin_dropdown()


## Rebuild the skin dropdown to reflect the current Config.skin_name.
func _rebuild_skin_dropdown() -> void:
	if _skin_opt == null:
		return
	_skin_opt.clear()
	var is_custom := Config.skin_name == "custom" or not (Config.skin_name in _skins)
	if is_custom:
		_skin_opt.add_item("Custom")
	for sk in _skins:
		_skin_opt.add_item(sk)
	if is_custom:
		_skin_opt.selected = 0
	else:
		var idx := _skins.find(Config.skin_name)
		if idx >= 0:
			_skin_opt.selected = idx + (1 if is_custom else 0)


## Sync the individual theme/style/icons dropdowns to the current skin.
func _sync_sub_dropdowns() -> void:
	if _theme_opt != null:
		var ti := _skins.find(Config.theme_name)
		if ti >= 0:
			_theme_opt.selected = ti
	if _style_opt != null:
		var si := _skins.find(Config.style_name)
		if si >= 0:
			_style_opt.selected = si
	if _icons_opt != null:
		var ii := _skins.find(Config.icon_pack_name)
		if ii >= 0:
			_icons_opt.selected = ii
