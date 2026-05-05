class_name PlaylistUI
extends Node

var _playlist: Playlist
var _win: Window
var _content: Control
var _tween: Tween
var _track_list: VBoxContainer
var _track_buttons: Array[Button] = []
var _loop_btn: Button
var _shuffle_btn: Button
var _scroll: ScrollContainer

# Callbacks — set by player_ui
var on_track_selected: Callable   # (index: int) -> void


func setup(playlist: Playlist) -> void:
	_playlist = playlist
	_playlist.track_changed.connect(_on_track_changed)
	_playlist.playlist_changed.connect(_rebuild_list)
	_build()


func toggle() -> void:
	if is_visible():
		close()
	else:
		open()


func open() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rebuild_list()
	_win.move_to_center()
	_win.show()

	_content.pivot_offset = _content.size / 2.0
	_content.scale = Vector2(0.90, 0.90)
	_content.modulate.a = 0.0

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_content, "scale", Vector2.ONE, 0.28)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(_content, "modulate:a", 1.0, 0.20)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.set_parallel(false)


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_content.pivot_offset = _content.size / 2.0

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_content, "scale", Vector2(0.90, 0.90), 0.16)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_content, "modulate:a", 0.0, 0.16)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.set_parallel(false)
	_tween.tween_callback(_win.hide)


func is_visible() -> bool:
	return _win != null and _win.visible


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_win = Window.new()
	_win.title    = "Playlist"
	_win.size     = Vector2i(380, 520)
	_win.min_size = Vector2i(300, 300)
	_win.transparent = true
	_win.borderless = true
	_win.close_requested.connect(close)
	_win.hide()
	add_child(_win)

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

	# ── Title bar ─────────────────────────────────────────────────────
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
	title_lbl.text = "Playlist"
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.modulate = Color(0.7, 0.82, 1.0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	StylesUI.apply_glass_btn(close_btn)
	title_row.add_child(close_btn)

	# ── Toolbar ───────────────────────────────────────────────────────
	var toolbar_margin := MarginContainer.new()
	toolbar_margin.add_theme_constant_override("margin_left",  8)
	toolbar_margin.add_theme_constant_override("margin_right", 8)
	col.add_child(toolbar_margin)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	toolbar_margin.add_child(toolbar)

	_loop_btn = Button.new()
	_loop_btn.focus_mode = Control.FOCUS_NONE
	_loop_btn.pressed.connect(_on_loop_pressed)
	StylesUI.apply_glass_btn(_loop_btn)
	toolbar.add_child(_loop_btn)

	_shuffle_btn = Button.new()
	_shuffle_btn.text = "Shuffle: Off"
	_shuffle_btn.focus_mode = Control.FOCUS_NONE
	_shuffle_btn.pressed.connect(_on_shuffle_pressed)
	StylesUI.apply_glass_btn(_shuffle_btn)
	toolbar.add_child(_shuffle_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var add_btn := Button.new()
	add_btn.text = "+ Add"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(_on_add_pressed)
	StylesUI.apply_glass_btn(add_btn)
	toolbar.add_child(add_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_clear_pressed)
	StylesUI.apply_glass_btn(clear_btn)
	toolbar.add_child(clear_btn)

	_refresh_mode_buttons()

	# ── Track list ────────────────────────────────────────────────────
	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left",   8)
	list_margin.add_theme_constant_override("margin_right",  8)
	list_margin.add_theme_constant_override("margin_bottom", 8)
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(list_margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_theme_stylebox_override("panel", StylesUI.glass_box(Color(0.04, 0.05, 0.09, 0.60), 10.0, false))
	list_margin.add_child(_scroll)

	_track_list = VBoxContainer.new()
	_track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_track_list)

	_rebuild_list()


# ── Track list ────────────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	for child in _track_list.get_children():
		child.queue_free()
	_track_buttons.clear()

	if _playlist.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No tracks loaded"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.modulate.a = 0.5
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_track_list.add_child(empty_lbl)
		return

	var group := ButtonGroup.new()
	for i in _playlist.size():
		var btn := Button.new()
		var track_path := _playlist.get_track(i)
		btn.text = "%d. %s" % [i + 1, track_path.get_file().get_basename()]
		btn.toggle_mode  = true
		btn.button_group = group
		btn.alignment    = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.focus_mode   = Control.FOCUS_NONE
		var idx := i
		btn.pressed.connect(func() -> void:
			if on_track_selected.is_valid():
				on_track_selected.call(idx)
		)
		StylesUI.apply_glass_btn(btn)
		_track_list.add_child(btn)
		_track_buttons.append(btn)

	_highlight_current()


func _highlight_current() -> void:
	var idx := _playlist.get_current_index()
	for i in _track_buttons.size():
		var btn: Button = _track_buttons[i]
		btn.set_pressed_no_signal(i == idx)
		if i == idx:
			btn.modulate = Color(0.7, 0.85, 1.0)
		else:
			btn.modulate = Color.WHITE


func _on_track_changed(index: int) -> void:
	_highlight_current()
	# Auto-scroll to current track
	if index >= 0 and index < _track_buttons.size():
		await get_tree().process_frame
		_scroll.ensure_control_visible(_track_buttons[index])


# ── Toolbar actions ───────────────────────────────────────────────────────────

func _on_loop_pressed() -> void:
	_playlist.cycle_play_mode()
	_refresh_mode_buttons()


func _on_shuffle_pressed() -> void:
	if _playlist.get_play_mode() == Playlist.PlayMode.SHUFFLE:
		_playlist.set_play_mode(Playlist.PlayMode.LOOP_ALL)
	else:
		_playlist.set_play_mode(Playlist.PlayMode.SHUFFLE)
	_refresh_mode_buttons()


func _refresh_mode_buttons() -> void:
	match _playlist.get_play_mode():
		Playlist.PlayMode.SEQUENTIAL:
			_loop_btn.text = "Loop: Off"
		Playlist.PlayMode.LOOP_ALL:
			_loop_btn.text = "Loop: All"
		Playlist.PlayMode.LOOP_ONE:
			_loop_btn.text = "Loop: One"
		Playlist.PlayMode.SHUFFLE:
			_loop_btn.text = "Loop: All"
	_shuffle_btn.text = "Shuffle: On" if _playlist.get_play_mode() == Playlist.PlayMode.SHUFFLE else "Shuffle: Off"


func _on_add_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.access     = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode  = FileDialog.FILE_MODE_OPEN_FILES
	dialog.filters    = PackedStringArray(["*.mp3,*.ogg ; Audio Files"])
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		_playlist.add_many(paths)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	_win.add_child(dialog)
	dialog.popup_centered_ratio(0.65)


func _on_clear_pressed() -> void:
	_playlist.clear()
