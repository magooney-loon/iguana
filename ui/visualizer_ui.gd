class_name VisualizerUI
extends Control

## Handles the visualizer overlay UI: shader name label, right-click context
## menu, and the debug overlay (live values shown for the Signal Scope shader).

var _analyzer: AudioAnalyzer
var _shaders: Array
var _shader_index := 0

# Shader name overlay
var _label: Label
var _label_timer := 0.0

# Right-click context menu
var _context_menu: PopupMenu
var _player_toggle_idx := 0
var _fullscreen_idx := 0

# Debug overlay (shown only for signal scope shader)
var _debug_overlay: Control
var _debug_values: Array[Label] = []
var _debug_top_values: Array[Label] = []
var _debug_flux_values: Array[Label] = []
var _debug_derived_values: Array[Label] = []


func setup(analyzer: AudioAnalyzer, shaders: Array) -> void:
	_analyzer = analyzer
	_shaders = shaders


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_label()
	_build_context_menu()
	_build_debug_overlay()


# ── Label overlay ──────────────────────────────────────────────────

func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(16, 14)
	_label.hide()
	add_child(_label)


func show_label(text: String) -> void:
	_label.text = text
	_label.modulate.a = 1.0
	_label.show()
	_label_timer = 2.0


# ── Right-click context menu ────────────────────────────────────────

func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "ShaderContextMenu"
	for i in _shaders.size():
		_context_menu.add_radio_check_item(_shaders[i].name, i)
	_context_menu.set_item_checked(_shader_index, true)
	_context_menu.add_separator()
	_context_menu.add_check_item("Show Player")
	_player_toggle_idx = _context_menu.item_count - 1
	_context_menu.set_item_checked(_player_toggle_idx, true)
	_context_menu.add_separator()
	_context_menu.add_check_item("Fullscreen")
	_fullscreen_idx = _context_menu.item_count - 1
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
		var player_bar := get_parent().owner.get_node("PlayerBar") as Control
		player_bar.visible = !player_bar.visible
		_context_menu.set_item_checked(index, player_bar.visible)
	elif index == _fullscreen_idx:
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			_context_menu.set_item_checked(index, false)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			_context_menu.set_item_checked(index, true)
	elif index < _shaders.size():
		var id := _context_menu.get_item_id(index)
		get_parent()._switch(id)


# ── Shader change notification ─────────────────────────────────────

func on_shader_changed(index: int) -> void:
	_shader_index = index
	# Sync context menu radio checkmarks
	for i in _shaders.size():
		_context_menu.set_item_checked(i, i == index)
	_update_debug_overlay_visibility()


# ── Frame update ───────────────────────────────────────────────────

func process_ui(delta: float) -> void:
	# Fade label
	if _label_timer > 0.0:
		_label_timer -= delta
		_label.modulate.a = clampf(_label_timer, 0.0, 1.0)
		if _label_timer <= 0.0:
			_label.hide()
	_update_debug_overlay_values()


# ── Debug overlay ──────────────────────────────────────────────────

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
	var a := _analyzer
	var values := [
		a._sub_bass, a._bass, a._low_mid, a._mid, a._presence, a._treble,
		a._beat_envelope, a._kick_envelope, a._snare_envelope, a._hihat_envelope,
		a._flux_bass, a._flux_mid, a._flux_treble, a._energy, a._activity,
	]
	var count := mini(_debug_values.size(), values.size())
	for i in range(count):
		_debug_values[i].text = "%.3f" % values[i]
	if _debug_top_values.size() >= 4:
		_debug_top_values[0].text = "%.1f" % a._bpm
		_debug_top_values[1].text = "%.2f" % a._beat_phase
		_debug_top_values[2].text = "%.2f" % a._beat_envelope
		_debug_top_values[3].text = "%.2f" % a._beat_confidence
	var flux_values := [a._flux_bass, a._flux_mid, a._flux_treble]
	var flux_names := ["bass", "mid", "treble"]
	count = mini(_debug_flux_values.size(), flux_values.size())
	for i in range(count):
		_debug_flux_values[i].text = "%s\n+%.2f" % [flux_names[i], flux_values[i]]
	var derived_values := [a._onset, a._loudness, a._warmth, a._brightness, a._density]
	count = mini(_debug_derived_values.size(), derived_values.size())
	for i in range(count):
		_debug_derived_values[i].text = "%.2f" % derived_values[i]


func _update_debug_overlay_visibility() -> void:
	if _debug_overlay == null:
		return
	# Show debug labels only when the signal scope shader is active
	_debug_overlay.visible = (_shaders[_shader_index].name == "Signal Scope")
