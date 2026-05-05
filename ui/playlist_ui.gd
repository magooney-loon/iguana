class_name PlaylistUI
extends Node

var _playlist: Playlist
var _win: Window
var _content: Control
var _tween: Tween
var _scroll: ScrollContainer
var _track_container: VBoxContainer
var _track_rows: Array[Dictionary] = []  # {row, name_clip, name_label, dur_label}
var _duration_cache: Dictionary = {}     # path → float seconds
var _marquee_tweens: Array[Tween] = []

# Footer
var _footer_stats: Label
var _add_btn: Button
var _clear_btn: Button

# Row styles
var _style_normal: StyleBoxFlat
var _style_hover:  StyleBoxFlat
var _style_active: StyleBoxFlat

# Callbacks — set by player_ui
var on_track_selected: Callable


func setup(playlist: Playlist) -> void:
	_playlist = playlist
	_playlist.track_changed.connect(_on_track_changed)
	_playlist.playlist_changed.connect(_rebuild_list)
	_init_styles()
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


# ── Styles ────────────────────────────────────────────────────────────────────

func _init_styles() -> void:
	_style_normal = StylesUI.glass_box(StylesUI.C_BTN, 6.0, true)
	_style_normal.content_margin_left   = 10.0
	_style_normal.content_margin_right  = 10.0
	_style_normal.content_margin_top    = 5.0
	_style_normal.content_margin_bottom = 5.0

	_style_hover = StylesUI.glass_box(StylesUI.C_BTN_H, 6.0, true)
	_style_hover.content_margin_left   = 10.0
	_style_hover.content_margin_right  = 10.0
	_style_hover.content_margin_top    = 5.0
	_style_hover.content_margin_bottom = 5.0

	_style_active = StylesUI.glass_box(Color(0.22, 0.34, 0.56, 0.50), 6.0, true)
	_style_active.content_margin_left   = 10.0
	_style_active.content_margin_right  = 10.0
	_style_active.content_margin_top    = 5.0
	_style_active.content_margin_bottom = 5.0


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

	var close_btn := StylesUI.icon_btn("close", "Close", Vector2(28, 28), close)
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
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_theme_stylebox_override("panel", StylesUI.glass_box(Color(0.04, 0.05, 0.09, 0.60), 10.0, false))
	list_margin.add_child(_scroll)

	_track_container = VBoxContainer.new()
	_track_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_track_container)

	# ── Footer bar ────────────────────────────────────────────────────
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

	_add_btn = StylesUI.icon_btn("add", "Add tracks")
	_add_btn.pressed.connect(_on_add_pressed)
	footer_row.add_child(_add_btn)

	_clear_btn = StylesUI.icon_btn("clear", "Clear playlist")
	_clear_btn.pressed.connect(_on_clear_pressed)
	footer_row.add_child(_clear_btn)

	_rebuild_list()


# ── Track list ────────────────────────────────────────────────────────────────

func _kill_marquees() -> void:
	for tw in _marquee_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_marquee_tweens.clear()


func _rebuild_list() -> void:
	_kill_marquees()
	for child in _track_container.get_children():
		child.queue_free()
	_track_rows.clear()

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

	var current_idx := _playlist.get_current_index()

	for i in _playlist.size():
		var track_path: String = _playlist.get_track(i)
		var track_name := track_path.get_file().get_basename()
		var dur: float = _duration_cache.get(track_path, 0.0)
		var is_active := (i == current_idx)

		# Row container (PanelContainer for background styling)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _style_active.duplicate() if is_active else _style_normal.duplicate())
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i

		# Inner HBox for layout
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 2)
		row.add_child(hbox)

		# ── Remove button ─────────────────────────────────────────────
		var remove_btn := Button.new()
		var remove_tex := StylesUI.load_icon("close")
		if remove_tex:
			remove_btn.icon = remove_tex
			remove_btn.expand_icon = true
		remove_btn.custom_minimum_size = Vector2(24, 24)
		remove_btn.focus_mode = Control.FOCUS_NONE
		remove_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		remove_btn.modulate.a = 0.5
		remove_btn.tooltip_text = "Remove from playlist"
		# Slim style — default glass_btn margins (10px) would crush the icon to a dot
		var _rs := func(bg: Color) -> StyleBoxFlat:
			var s := StylesUI.glass_box(bg, 5.0, false)
			s.content_margin_left = 4.0
			s.content_margin_right = 4.0
			s.content_margin_top = 3.0
			s.content_margin_bottom = 3.0
			return s
		remove_btn.add_theme_stylebox_override("normal", _rs.call(StylesUI.C_BTN))
		remove_btn.add_theme_stylebox_override("hover", _rs.call(StylesUI.C_BTN_H))
		remove_btn.add_theme_stylebox_override("pressed", _rs.call(StylesUI.C_BTN_P))
		remove_btn.pressed.connect(func() -> void:
			_playlist.remove(idx)
		)
		hbox.add_child(remove_btn)

		# ── Number ────────────────────────────────────────────────────
		var num_lbl := Label.new()
		num_lbl.text = "%d." % [i + 1]
		num_lbl.add_theme_font_size_override("font_size", 12)
		num_lbl.modulate.a = 0.40
		num_lbl.custom_minimum_size.x = 20
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(num_lbl)

		# ── Name (clipped, with marquee if needed) ────────────────────
		var name_clip := Control.new()
		name_clip.clip_contents = true
		name_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(name_clip)

		var name_label := Label.new()
		name_label.text = track_name
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.anchor_top = 0.0
		name_label.anchor_bottom = 1.0
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if is_active:
			name_label.modulate = Color(0.75, 0.88, 1.0)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_clip.add_child(name_label)

		# ── Duration ──────────────────────────────────────────────────
		var dur_lbl := Label.new()
		dur_lbl.text = _fmt_duration(dur)
		dur_lbl.add_theme_font_size_override("font_size", 12)
		dur_lbl.modulate.a = 0.50
		dur_lbl.custom_minimum_size.x = 44
		dur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dur_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(dur_lbl)

		# Click handling
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if on_track_selected.is_valid():
					on_track_selected.call(idx)
		)

		# Hover effects
		if not is_active:
			row.mouse_entered.connect(func() -> void:
				if not _is_active_row(idx):
					row.add_theme_stylebox_override("panel", _style_hover.duplicate())
			)
			row.mouse_exited.connect(func() -> void:
				if not _is_active_row(idx):
					row.add_theme_stylebox_override("panel", _style_normal.duplicate())
			)

		_track_container.add_child(row)
		_track_rows.append({
			"row": row,
			"name_clip": name_clip,
			"name_label": name_label,
			"dur_label": dur_lbl,
			"index": i,
		})

	_update_footer()
	# Wait for layout then set up marquees
	_setup_marquees.call_deferred()


func _is_active_row(idx: int) -> bool:
	return idx == _playlist.get_current_index()


func _setup_marquees() -> void:
	_kill_marquees()
	await get_tree().process_frame

	for entry in _track_rows:
		var label: Label = entry["name_label"]
		var clip: Control = entry["name_clip"]

		var natural_w := label.get_combined_minimum_size().x
		var clip_w := clip.size.x

		# Size the label width to natural width (anchors handle height)
		label.size.x = max(natural_w, clip_w)
		label.position = Vector2(0, 0)

		if natural_w > clip_w + 2.0:
			var overflow := natural_w - clip_w
			var speed := 28.0
			var scroll_time := overflow / speed
			var tw := create_tween().set_loops().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw.tween_interval(2.0)
			tw.tween_property(label, "position:x", -overflow, scroll_time)\
				.set_ease(Tween.EASE_IN_OUT)
			tw.tween_interval(1.5)
			tw.tween_property(label, "position:x", 0.0, scroll_time)\
				.set_ease(Tween.EASE_IN_OUT)
			tw.tween_interval(2.0)
			_marquee_tweens.append(tw)


func _highlight_current() -> void:
	var idx := _playlist.get_current_index()
	for entry in _track_rows:
		var i: int = entry["index"]
		var row: PanelContainer = entry["row"]
		var name_label: Label = entry["name_label"]
		if i == idx:
			row.add_theme_stylebox_override("panel", _style_active.duplicate())
			name_label.modulate = Color(0.75, 0.88, 1.0)
		else:
			row.add_theme_stylebox_override("panel", _style_normal.duplicate())
			name_label.modulate = Color.WHITE
	_setup_marquees.call_deferred()


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
	if index >= 0 and index < _track_rows.size():
		await get_tree().process_frame
		_scroll.ensure_control_visible(_track_rows[index]["row"])


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
	var h := int(total / 3600.0)
	var m := int((total % 3600) / 60.0)
	var s := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]
