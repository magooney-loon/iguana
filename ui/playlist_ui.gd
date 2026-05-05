class_name PlaylistUI
extends Node

var _playlist: Playlist
var _win: Window
var _content: Control
var _tween: Tween
var _scroll: ScrollContainer
var _track_container: VBoxContainer
var _track_buttons: Array[Button] = []
var _duration_cache: Dictionary = {}   # path → float seconds
var _footer_stats: Label
var _add_btn: Button
var _clear_btn: Button

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
	_win.size     = Vector2i(400, 520)
	_win.min_size = Vector2i(320, 300)
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

	# ── Track list ────────────────────────────────────────────────────
	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left",   8)
	list_margin.add_theme_constant_override("margin_right",  8)
	list_margin.add_theme_constant_override("margin_top",    4)
	list_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(list_margin)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_theme_stylebox_override("panel", StylesUI.glass_box(Color(0.04, 0.05, 0.09, 0.60), 10.0, false))
	list_margin.add_child(_scroll)

	_track_container = VBoxContainer.new()
	_track_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_track_container)

	# ── Footer bar: stats + actions ───────────────────────────────────
	var footer_bar := PanelContainer.new()
	footer_bar.add_theme_stylebox_override("panel", StylesUI.glass_box(Color(0.08, 0.09, 0.15, 0.55), 8.0, true))
	col.add_child(footer_bar)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left",   10)
	footer_margin.add_theme_constant_override("margin_right",  10)
	footer_margin.add_theme_constant_override("margin_top",    6)
	footer_margin.add_theme_constant_override("margin_bottom", 6)
	footer_bar.add_child(footer_margin)

	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 8)
	footer_margin.add_child(footer_row)

	_footer_stats = Label.new()
	_footer_stats.add_theme_font_size_override("font_size", 12)
	_footer_stats.modulate.a = 0.6
	_footer_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(_footer_stats)

	_add_btn = Button.new()
	_add_btn.text = "+ Add"
	_add_btn.focus_mode = Control.FOCUS_NONE
	_add_btn.pressed.connect(_on_add_pressed)
	StylesUI.apply_glass_btn(_add_btn)
	footer_row.add_child(_add_btn)

	_clear_btn = Button.new()
	_clear_btn.text = "Clear"
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.pressed.connect(_on_clear_pressed)
	StylesUI.apply_glass_btn(_clear_btn)
	footer_row.add_child(_clear_btn)

	_rebuild_list()


# ── Track list ────────────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	for child in _track_container.get_children():
		child.queue_free()
	_track_buttons.clear()

	if _playlist.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No tracks loaded"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.modulate.a = 0.45
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_track_container.add_child(empty_lbl)
		_update_footer()
		return

	_cache_durations()

	for i in _playlist.size():
		var btn := Button.new()
		var track_path: String = _playlist.get_track(i)
		var track_name := track_path.get_file().get_basename()
		var dur: float = _duration_cache.get(track_path, 0.0)
		btn.text = "%d.   %s   %s" % [i + 1, track_name, _fmt_duration(dur)]
		btn.toggle_mode  = true
		btn.button_group = ButtonGroup.new()
		btn.alignment    = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.focus_mode   = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func() -> void:
			if on_track_selected.is_valid():
				on_track_selected.call(idx)
		)
		StylesUI.apply_glass_btn(btn)
		_track_container.add_child(btn)
		_track_buttons.append(btn)

	_highlight_current()
	_update_footer()


func _highlight_current() -> void:
	var idx := _playlist.get_current_index()
	for i in _track_buttons.size():
		var btn: Button = _track_buttons[i]
		btn.set_pressed_no_signal(i == idx)
		if i == idx:
			btn.modulate = Color(0.7, 0.85, 1.0)
		else:
			btn.modulate = Color.WHITE


func _update_footer() -> void:
	if _playlist.is_empty():
		_footer_stats.text = "Empty"
		_clear_btn.visible = false
		return
	_clear_btn.visible = true
	var total_secs: float = 0.0
	for i in _playlist.size():
		total_secs += _duration_cache.get(_playlist.get_track(i), 0.0)
	var count := _playlist.size()
	_footer_stats.text = "%d track%s  ·  %s total" % [count, "s" if count != 1 else "", _fmt_duration(total_secs)]


func _on_track_changed(index: int) -> void:
	_highlight_current()
	if index >= 0 and index < _track_buttons.size():
		await get_tree().process_frame
		_scroll.ensure_control_visible(_track_buttons[index])


# ── Duration caching ──────────────────────────────────────────────────────────

func _cache_durations() -> void:
	for i in _playlist.size():
		var path: String = _playlist.get_track(i)
		if path in _duration_cache:
			continue
		var dur := _read_duration(path)
		if dur > 0.0:
			_duration_cache[path] = dur


func _read_duration(path: String) -> float:
	var ext := path.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return 0.0
	match ext:
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = bytes
			return s.get_length()
		"ogg":
			var s: AudioStream = AudioStreamOggVorbis.load_from_buffer(bytes)
			if s:
				return s.get_length()
	return 0.0


# ── Footer actions ────────────────────────────────────────────────────────────

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
	_duration_cache.clear()


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _fmt_duration(secs: float) -> String:
	if secs <= 0.0:
		return "0:00"
	var total := int(secs)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]
