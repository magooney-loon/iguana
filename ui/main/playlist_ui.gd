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

# Animation queue — prevents overlapping mutations
var _animating := false
var _pending_ops: Array[Callable] = []

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
	_playlist.playlist_changed.connect(_on_playlist_changed)
	_init_styles()
	_build()
	StylesUI.on_reload(func() -> void:
		if not is_instance_valid(_win):
			return
		_init_styles()
		_rebuild_list()
	)


func toggle() -> void:
	if is_visible():
		close()
	else:
		open()


func open() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_rebuild_list()
	var st     := StylesUI.style()
	var vp     := get_viewport().get_visible_rect().size
	var target_y := int((vp.y - _win.size.y) / 2.0)
	_win.position = Vector2i(-_win.size.x, target_y)
	_win.show()
	_content.modulate.a = 0.0

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", 16, st.anim_win_open_duration)\
		.set_ease(st.anim_win_open_ease).set_trans(st.anim_win_open_trans)
	_tween.tween_property(_content, "modulate:a", 1.0, st.anim_win_fade_in)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func close() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var st := StylesUI.style()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_win, "position:x", -_win.size.x, st.anim_win_close_duration)\
		.set_ease(st.anim_win_close_ease).set_trans(st.anim_win_close_trans)
	_tween.tween_property(_content, "modulate:a", 0.0, st.anim_win_fade_out)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.set_parallel(false)
	_tween.tween_callback(_win.hide)


func is_visible() -> bool:
	return _win != null and _win.visible


# ── Styles ────────────────────────────────────────────────────────────────────

func _init_styles() -> void:
	var t := StylesUI.theme()

	_style_normal = StylesUI.glass_box(t.c_btn, 6.0, true)
	_style_normal.content_margin_left   = 10.0
	_style_normal.content_margin_right  = 10.0
	_style_normal.content_margin_top    = 5.0
	_style_normal.content_margin_bottom = 5.0

	_style_hover = StylesUI.glass_box(t.c_btn_h, 6.0, true)
	_style_hover.content_margin_left   = 10.0
	_style_hover.content_margin_right  = 10.0
	_style_hover.content_margin_top    = 5.0
	_style_hover.content_margin_bottom = 5.0

	_style_active = StylesUI.glass_box(t.c_active_row, 6.0, true)
	_style_active.content_margin_left   = 10.0
	_style_active.content_margin_right  = 10.0
	_style_active.content_margin_top    = 5.0
	_style_active.content_margin_bottom = 5.0


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	_win = Window.new()
	_win.title    = "Playlist"
	_win.size     = Vector2i(400, 580)
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
	StylesUI.track_glass_panel(title_bar, func(p: Control) -> void:
		p.add_theme_stylebox_override("panel", StylesUI.glass_box(StylesUI.theme().c_title_bar, 14.0, true))
	)
	StylesUI.apply_aero(title_bar, true)
	col.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 8)
	title_margin.add_theme_constant_override("margin_right", 12)
	title_margin.add_theme_constant_override("margin_top", 8)
	title_margin.add_theme_constant_override("margin_bottom", 6)
	title_bar.add_child(title_margin)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_margin.add_child(title_row)

	var close_btn := StylesUI.icon_btn("close", "Close", Vector2(28, 28), close)
	title_row.add_child(close_btn)

	var title_lbl := Label.new()
	title_lbl.text = "Playlist"
	StylesUI.track_label(title_lbl, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_title)
		l.modulate = StylesUI.theme().c_text_hi
	)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(title_lbl)

	# ── Track list ────────────────────────────────────────────────────

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	StylesUI.track_glass_panel(_scroll, func(p: Control) -> void:
		var box := StylesUI.glass_box(StylesUI.theme().c_panel_bg, 10.0, false)
		box.shadow_size = 0
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		p.add_theme_stylebox_override("panel", box)
	)
	StylesUI.apply_aero(_scroll, true)
	col.add_child(_scroll)

	var list_pad := MarginContainer.new()
	list_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_pad.add_theme_constant_override("margin_right", 2)
	list_pad.add_theme_constant_override("margin_bottom", 8)
	_scroll.add_child(list_pad)

	_track_container = VBoxContainer.new()
	_track_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_container.add_theme_constant_override("separation", 2)
	list_pad.add_child(_track_container)

	# ── Footer bar ────────────────────────────────────────────────────
	var footer_bar := PanelContainer.new()
	StylesUI.track_glass_panel(footer_bar, func(p: Control) -> void:
		p.add_theme_stylebox_override("panel", StylesUI.glass_box(StylesUI.theme().c_footer_bar, 8.0, true))
	)
	StylesUI.apply_aero(footer_bar, true)
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
	StylesUI.track_label(_footer_stats, func(l: Label) -> void:
		l.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		l.modulate.a = StylesUI.theme().a_footer_stats
	)
	_footer_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(_footer_stats)

	_add_btn = StylesUI.icon_btn("add", "Add tracks")
	_add_btn.pressed.connect(_on_add_pressed)
	footer_row.add_child(_add_btn)

	_clear_btn = StylesUI.icon_btn("clear", "Clear playlist")
	_clear_btn.pressed.connect(_on_clear_pressed)
	footer_row.add_child(_clear_btn)

	_rebuild_list()


# ── Mutation routing ──────────────────────────────────────────────────────────
# Instead of _rebuild_list on every playlist_changed, we detect what changed
# and animate surgically. Falls back to full rebuild for bulk/clear operations.

var _last_track_list: Array[String] = []
var _last_current: int = -1

func _on_playlist_changed() -> void:
	var new_list := _playlist.get_tracks()
	var new_current := _playlist.get_current_index()

	# If the list is empty or we don't have rows yet, full rebuild
	if _track_rows.is_empty() or new_list.is_empty():
		_rebuild_list()
		_last_track_list = new_list.duplicate()
		_last_current = new_current
		return

	# Detect what changed
	var diff := _detect_diff(_last_track_list, new_list)

	match diff.type:
		"add_one":
			_animate_add(diff.index)
		"add_many":
			_animate_add_many(diff.indices)
		"remove_one":
			_animate_remove(diff.index)
		"clear":
			_animate_clear()
		"reorder", _:
			# For reorder or unknown, do a full animated rebuild
			_rebuild_list()

	_last_track_list = new_list.duplicate()
	_last_current = new_current


func _detect_diff(old: Array[String], new: Array[String]) -> Dictionary:
	# Clear
	if new.is_empty() and not old.is_empty():
		return {"type": "clear"}

	# Same size — check for reorder
	if old.size() == new.size():
		var diffs := 0
		var diff_idx := -1
		for i in old.size():
			if old[i] != new[i]:
				diffs += 1
				diff_idx = i
		if diffs == 0:
			return {"type": "none"}
		if diffs <= 2:
			return {"type": "reorder"}
		return {"type": "reorder"}

	# One item added
	if new.size() == old.size() + 1:
		# Find where the new item was inserted
		for i in new.size():
			var check_old := new.duplicate()
			check_old.remove_at(i)
			if check_old == old:
				return {"type": "add_one", "index": i}
		return {"type": "add_one", "index": new.size() - 1}

	# Many items added (batch add)
	if new.size() > old.size() + 1:
		# Check if all old items are a prefix of new
		var is_append := true
		for i in old.size():
			if old[i] != new[i]:
				is_append = false
				break
		if is_append:
			var indices: Array[int] = []
			for i in range(old.size(), new.size()):
				indices.append(i)
			return {"type": "add_many", "indices": indices}
		# Otherwise full rebuild
		return {"type": "reorder"}

	# One item removed
	if new.size() == old.size() - 1:
		for i in old.size():
			var check_new := old.duplicate()
			check_new.remove_at(i)
			if check_new == new:
				return {"type": "remove_one", "index": i}
		return {"type": "reorder"}

	return {"type": "reorder"}


# ── Animated mutations ─────────────────────────────────────────────────────────

func _animate_add(idx: int) -> void:
	_cache_durations()
	_insert_row_anim(idx)
	_update_footer()
	_setup_marquees.call_deferred()


func _animate_add_many(indices: Array[int]) -> void:
	_cache_durations()
	# Animate each new row appearing one after another with stagger
	for i in indices.size():
		var row_idx := indices[i]
		# Use call_deferred to stagger
		var delay := i * 0.04
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			_insert_row_anim(row_idx)
		)
	_update_footer()
	_setup_marquees.call_deferred()


func _insert_row_anim(idx: int) -> void:
	# Build the row (same as _create_row but returns it)
	var row_data := _create_row(idx)
	var row: PanelContainer = row_data["row"]

	# Insert at the right position in the container
	if idx >= _track_container.get_child_count():
		_track_container.add_child(row)
	else:
		_track_container.add_child(row)
		_track_container.move_child(row, idx)

	# Insert into _track_rows at the right position
	_track_rows.insert(idx, row_data)
	# Re-index all rows after this point
	_reindex_rows()

	# Start collapsed + invisible, then animate open
	row.custom_minimum_size.y = 0.0
	row.modulate.a = 0.0
	# Force a layout update to get the natural size
	await get_tree().process_frame

	var target_y := row.get_combined_minimum_size().y
	if target_y < 10.0:
		target_y = 36.0  # fallback height

	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tw.set_parallel(true)
	tw.tween_property(row, "custom_minimum_size:y", target_y, 0.25)
	tw.tween_property(row, "modulate:a", 1.0, 0.20)
	# Also animate a subtle slide-in from the right
	row.position.x = 20.0
	tw.tween_property(row, "position:x", 0.0, 0.25)


func _animate_remove(idx: int) -> void:
	if idx < 0 or idx >= _track_rows.size():
		return
	var entry: Dictionary = _track_rows[idx]
	var row: PanelContainer = entry["row"]

	if not is_instance_valid(row):
		_track_rows.remove_at(idx)
		_rebuild_list()
		return

	# Phase 1: fade out + slide right (row is still visible)
	var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	tw.set_parallel(true)
	tw.tween_property(row, "modulate:a", 0.0, 0.15)
	tw.tween_property(row, "position:x", 30.0, 0.15)

	# Phase 2: row is now invisible — collapse height smoothly
	tw.set_parallel(false)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
	tw.tween_property(row, "custom_minimum_size:y", 0.0, 0.12)

	# Phase 3: free, reindex, and re-highlight the now-current track
	tw.tween_callback(func() -> void:
		if is_instance_valid(row):
			row.queue_free()
		_track_rows.remove_at(idx)
		_reindex_rows()
		_update_footer()
		_highlight_current()
		_setup_marquees.call_deferred()
	)


func _animate_clear() -> void:
	if _track_rows.is_empty():
		_rebuild_list()
		return

	_kill_marquees()
	var row_count := _track_rows.size()
	var delay_per := 0.03
	var total_delay := row_count * delay_per

	# Stagger collapse from top to bottom
	for i in row_count:
		var entry: Dictionary = _track_rows[i]
		var row: PanelContainer = entry["row"]
		if not is_instance_valid(row):
			continue
		var tw := create_tween()
		tw.tween_interval(i * delay_per)
		tw.set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUART)
		tw.tween_property(row, "modulate:a", 0.0, 0.15)
		tw.tween_property(row, "custom_minimum_size:y", 0.0, 0.15)

	# After all animations complete, do the actual rebuild (shows empty state)
	get_tree().create_timer(total_delay + 0.20).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_rebuild_list()
	)


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
		empty_lbl.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
		empty_lbl.modulate.a = StylesUI.theme().a_empty_msg
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_track_container.add_child(empty_lbl)
		_update_footer()
		return

	_cache_durations()

	var current_idx := _playlist.get_current_index()

	for i in _playlist.size():
		var row_data := _create_row(i, current_idx)
		_track_container.add_child(row_data["row"])
		_track_rows.append(row_data)

	_update_footer()
	_last_track_list = _playlist.get_tracks().duplicate()
	_last_current = current_idx
	# Wait for layout then set up marquees
	_setup_marquees.call_deferred()


## Create a single track row Dictionary. Separated from _rebuild_list so
## both the bulk rebuild and animated insert can use it.
func _create_row(idx: int, force_active: int = -2) -> Dictionary:
	var current_idx := force_active if force_active >= -1 else _playlist.get_current_index()
	var is_active := (idx == current_idx)
	var track_path: String = _playlist.get_track(idx)
	var track_name := track_path.get_file().get_basename()
	var dur: float = _duration_cache.get(track_path, 0.0)

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _style_active.duplicate() if is_active else _style_normal.duplicate())
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	StylesUI.apply_aero(row, true)

	# Inner HBox for layout
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	row.add_child(hbox)

	# ── Number ────────────────────────────────────────────────────
	var num_lbl := Label.new()
	num_lbl.text = "%d." % [idx + 1]
	num_lbl.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	num_lbl.modulate.a = StylesUI.theme().a_track_num
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	num_lbl.custom_minimum_size.x = 28
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
	name_label.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	name_label.anchor_top = 0.0
	name_label.anchor_bottom = 1.0
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.modulate = StylesUI.theme().c_text_hi if is_active else StylesUI.theme().c_text_dim
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_clip.add_child(name_label)

	# ── Duration ──────────────────────────────────────────────────
	var dur_lbl := Label.new()
	dur_lbl.text = _fmt_duration(dur)
	dur_lbl.add_theme_font_size_override("font_size", StylesUI.theme().font_body)
	dur_lbl.modulate.a = StylesUI.theme().a_duration
	dur_lbl.custom_minimum_size.x = 44
	dur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dur_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dur_lbl)

	# ── Spacer ─────────────────────────────────────────────────────
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 6
	hbox.add_child(spacer)

	# ── Remove button ─────────────────────────────────────────────
	var remove_btn := Button.new()
	var remove_tex := StylesUI.load_icon("close")
	if remove_tex:
		remove_btn.icon = remove_tex
		remove_btn.expand_icon = true
	remove_btn.custom_minimum_size = Vector2(20, 20)
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	remove_btn.modulate.a = StylesUI.theme().a_dim_icon
	remove_btn.tooltip_text = "Remove from playlist"
	var _rs := func(bg: Color) -> StyleBoxFlat:
		var s := StylesUI.glass_box(bg, 5.0, false)
		s.content_margin_left   = 4.0
		s.content_margin_right  = 4.0
		s.content_margin_top    = 3.0
		s.content_margin_bottom = 3.0
		return s
	remove_btn.add_theme_stylebox_override("normal", _rs.call(StylesUI.theme().c_btn))
	remove_btn.add_theme_stylebox_override("hover", _rs.call(StylesUI.theme().c_btn_h))
	remove_btn.add_theme_stylebox_override("pressed", _rs.call(StylesUI.theme().c_btn_p))
	remove_btn.pressed.connect(func() -> void:
		var entry_idx: int = row.get_meta("list_index")
		_playlist.remove(entry_idx)
	)
	hbox.add_child(remove_btn)

	# Click handling
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if on_track_selected.is_valid():
				var entry_idx: int = row.get_meta("list_index")
				on_track_selected.call(entry_idx)
	)

	# Hover effects
	row.mouse_entered.connect(func() -> void:
		var entry_idx: int = row.get_meta("list_index")
		if not _is_active_row(entry_idx):
			row.add_theme_stylebox_override("panel", _style_hover.duplicate())
	)
	row.mouse_exited.connect(func() -> void:
		var entry_idx: int = row.get_meta("list_index")
		if not _is_active_row(entry_idx):
			row.add_theme_stylebox_override("panel", _style_normal.duplicate())
	)

	var result := {
		"row": row,
		"name_clip": name_clip,
		"name_label": name_label,
		"dur_label": dur_lbl,
		"index": idx,
	}
	# Store index as metadata so closures can look it up dynamically
	row.set_meta("list_index", idx)
	row.set_meta("entry", result)
	return result


## Re-assign index numbers and update row_idx captures after insert/remove.
func _reindex_rows() -> void:
	for i in _track_rows.size():
		var entry: Dictionary = _track_rows[i]
		entry["index"] = i
		var row: PanelContainer = entry["row"]
		if row == null:
			continue
		# Update the metadata so closures resolve the correct index
		row.set_meta("list_index", i)
		# Update the num label text
		var hbox: HBoxContainer = row.get_child(0) as HBoxContainer
		if hbox and hbox.get_child_count() > 0:
			var num_lbl: Label = hbox.get_child(0) as Label
			if num_lbl:
				num_lbl.text = "%d." % [i + 1]


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
			name_label.modulate = StylesUI.theme().c_text_hi
		else:
			row.add_theme_stylebox_override("panel", _style_normal.duplicate())
			name_label.modulate = StylesUI.theme().c_text_dim
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
