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

# ── Sub-systems ───────────────────────────────────────────────────────────────
var _settings:    SettingsUI
var _playlist:    Playlist
var _playlist_ui: PlaylistUI

# ── Bar buttons that need live refresh ────────────────────────────────────────
var _loop_btn:    Button
var _shuffle_btn: Button


func _ready() -> void:
	_player     = owner.get_node("Player") as AudioStreamPlayer
	_visualizer = get_tree().root.get_node("Main/VisualizerContainer/FeedbackViewport/Visualizer")
	_analyzer   = _visualizer._analyzer

	StylesUI.apply_bar_style(self)

	# ── Sub-systems ────────────────────────────────────────────────────
	_playlist = Playlist.new()

	_settings = SettingsUI.new()
	_settings.setup(_visualizer, _analyzer)
	add_child(_settings)

	_playlist_ui = PlaylistUI.new()
	_playlist_ui.setup(_playlist)
	_playlist_ui.on_track_selected = _on_playlist_jump
	add_child(_playlist_ui)

	_build_bar()

	_player.finished.connect(_on_song_finished)

	# Populate playlist with the default song BEFORE connecting our handler
	# so we don't restart the already-playing autoplay track
	if _player.stream != null:
		var rpath := _player.stream.resource_path
		if not rpath.is_empty():
			_playlist.add(rpath)

	# Now connect — all future track changes auto-play
	_playlist.track_changed.connect(_on_playlist_track_changed)
	_playlist.playlist_changed.connect(_on_playlist_changed)

	_refresh_song_label()
	_refresh_mode_buttons()
	_refresh_play_btn()


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

	var prev_btn := Button.new()
	prev_btn.text = "⏮"
	prev_btn.tooltip_text = "Previous"
	prev_btn.custom_minimum_size.x = 32
	prev_btn.add_theme_font_size_override("font_size", 16)
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.pressed.connect(_on_prev)
	StylesUI.apply_glass_btn(prev_btn)
	top.add_child(prev_btn)

	_play_btn = Button.new()
	_play_btn.custom_minimum_size.x = 36
	_play_btn.add_theme_font_size_override("font_size", 18)
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.pressed.connect(_on_play_pause)
	StylesUI.apply_glass_btn(_play_btn)
	top.add_child(_play_btn)

	var stop_btn := Button.new()
	stop_btn.text = "⏹"
	stop_btn.tooltip_text = "Stop"
	stop_btn.custom_minimum_size.x = 32
	stop_btn.add_theme_font_size_override("font_size", 16)
	stop_btn.focus_mode = Control.FOCUS_NONE
	stop_btn.pressed.connect(_on_stop)
	StylesUI.apply_glass_btn(stop_btn)
	top.add_child(stop_btn)

	var next_btn := Button.new()
	next_btn.text = "⏭"
	next_btn.tooltip_text = "Next"
	next_btn.custom_minimum_size.x = 32
	next_btn.add_theme_font_size_override("font_size", 16)
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.pressed.connect(_on_next)
	StylesUI.apply_glass_btn(next_btn)
	top.add_child(next_btn)

	top.add_child(StylesUI.make_vsep())

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

	top.add_child(StylesUI.make_vsep())

	_loop_btn = Button.new()
	_loop_btn.text = "🔁"
	_loop_btn.tooltip_text = "Loop mode"
	_loop_btn.custom_minimum_size.x = 32
	_loop_btn.add_theme_font_size_override("font_size", 16)
	_loop_btn.focus_mode = Control.FOCUS_NONE
	_loop_btn.pressed.connect(_on_loop_pressed)
	StylesUI.apply_glass_btn(_loop_btn)
	top.add_child(_loop_btn)

	_shuffle_btn = Button.new()
	_shuffle_btn.text = "Sh"
	_shuffle_btn.tooltip_text = "Shuffle"
	_shuffle_btn.custom_minimum_size.x = 32
	_shuffle_btn.add_theme_font_size_override("font_size", 12)
	_shuffle_btn.focus_mode = Control.FOCUS_NONE
	_shuffle_btn.pressed.connect(_on_shuffle_pressed)
	StylesUI.apply_glass_btn(_shuffle_btn)
	top.add_child(_shuffle_btn)

	var pl_btn := Button.new()
	pl_btn.text = "☰"
	pl_btn.tooltip_text = "Playlist"
	pl_btn.custom_minimum_size.x = 32
	pl_btn.add_theme_font_size_override("font_size", 16)
	pl_btn.focus_mode = Control.FOCUS_NONE
	pl_btn.pressed.connect(_playlist_ui.toggle)
	StylesUI.apply_glass_btn(pl_btn)
	top.add_child(pl_btn)

	var fs_btn := Button.new()
	fs_btn.text = "⛶"
	fs_btn.tooltip_text = "Fullscreen"
	fs_btn.custom_minimum_size.x = 32
	fs_btn.add_theme_font_size_override("font_size", 16)
	fs_btn.focus_mode = Control.FOCUS_NONE
	fs_btn.pressed.connect(_toggle_fullscreen)
	StylesUI.apply_glass_btn(fs_btn)
	top.add_child(fs_btn)

	var set_btn := Button.new()
	set_btn.text = "⚙"
	set_btn.tooltip_text = "Settings"
	set_btn.custom_minimum_size.x = 32
	set_btn.add_theme_font_size_override("font_size", 16)
	set_btn.focus_mode = Control.FOCUS_NONE
	set_btn.pressed.connect(_settings.toggle)
	StylesUI.apply_glass_btn(set_btn)
	top.add_child(set_btn)

	# ── Bottom row: seek bar ───────────────────────────────────────────
	_seek_bar = HSlider.new()
	_seek_bar.min_value  = 0.0
	_seek_bar.max_value  = 1.0
	_seek_bar.step       = 0.01
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.custom_minimum_size.y = 18
	_seek_bar.focus_mode = Control.FOCUS_NONE
	_seek_bar.value_changed.connect(_on_seek_changed)

	var sb_bg := StylesUI.glass_box(Color(0.04, 0.05, 0.10, 0.50), 5.0, false)
	sb_bg.content_margin_top = 6.0
	sb_bg.content_margin_bottom = 6.0
	_seek_bar.add_theme_stylebox_override("slider", sb_bg)

	var sb_fill := StylesUI.glass_box(Color(0.30, 0.45, 0.75, 0.50), 5.0, false)
	sb_fill.content_margin_top = 6.0
	sb_fill.content_margin_bottom = 6.0
	_seek_bar.add_theme_stylebox_override("fill", sb_fill)

	var sb_grab := StylesUI.glass_box(Color(0.55, 0.70, 1.0, 0.80), 8.0, true)
	sb_grab.content_margin_left = 4.0
	sb_grab.content_margin_right = 4.0
	sb_grab.content_margin_top = 4.0
	sb_grab.content_margin_bottom = 4.0
	_seek_bar.add_theme_stylebox_override("grabber_area", sb_grab)
	_seek_bar.add_theme_stylebox_override("grabber_area_highlight", sb_grab)

	vbox.add_child(_seek_bar)

	_refresh_mode_buttons()


# ─────────────────────────────────────────────────────────────────────────────
#  Frame update
# ─────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_player_ui()
	_settings.sync_frame()


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


# ─────────────────────────────────────────────────────────────────────────────
#  Playlist integration
# ─────────────────────────────────────────────────────────────────────────────

func _play_track(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.play()
	_paused = false
	_refresh_song_label()
	_seek_bar.max_value = stream.get_length()
	_refresh_play_btn()


func _refresh_song_label() -> void:
	var track := _playlist.get_current_track()
	if track.is_empty():
		_song_label.text = "No track loaded"
		return
	var track_name := track.get_file().get_basename()
	if _playlist.size() > 1:
		track_name += "  (%d/%d)" % [_playlist.get_current_index() + 1, _playlist.size()]
	_song_label.text = track_name


func _on_playlist_track_changed(index: int) -> void:
	if index < 0:
		# Playlist emptied — stop playback
		_player.stop()
		_player.stream = null
		_paused = false
		_song_label.text = "No track loaded"
		_time_label.text = "0:00 / 0:00"
		_seek_bar.max_value = 1.0
		_seek_bar.value = 0.0
		_refresh_play_btn()
		return
	# Auto-play the new current track (handles remove, jump, prev, next)
	_play_track(_playlist.get_current_track())


func _on_playlist_changed() -> void:
	if _playlist.is_empty():
		_player.stop()
		_player.stream = null
		_paused = false
		_song_label.text = "No track loaded"
		_time_label.text = "0:00 / 0:00"
		_seek_bar.max_value = 1.0
		_seek_bar.value = 0.0
		_refresh_play_btn()


func _on_playlist_jump(index: int) -> void:
	_playlist.jump_to(index)


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
			_loop_btn.text = "→"
			_loop_btn.tooltip_text = "Sequential (click to loop all)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.LOOP_ALL:
			_loop_btn.text = "🔁"
			_loop_btn.tooltip_text = "Loop All (click to loop one)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.LOOP_ONE:
			_loop_btn.text = "🔂"
			_loop_btn.tooltip_text = "Loop One (click to shuffle)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.SHUFFLE:
			_loop_btn.text = "🔁"
			_loop_btn.tooltip_text = "Shuffle (click for sequential)"
			_shuffle_btn.modulate.a = 1.0


# ─────────────────────────────────────────────────────────────────────────────
#  Actions
# ─────────────────────────────────────────────────────────────────────────────

func _on_play_pause() -> void:
	if _player.stream == null:
		# If nothing loaded but playlist has tracks, play current
		if not _playlist.is_empty():
			_play_track(_playlist.get_current_track())
		return
	if _player.stream_paused:
		_player.stream_paused = false
		_paused = false
	elif _player.playing:
		_player.stream_paused = true
		_paused = true
	else:
		_player.play()
		_paused = false
	_refresh_play_btn()


func _on_stop() -> void:
	_player.stop()
	_paused = false
	_refresh_play_btn()


func _on_prev() -> void:
	if _playlist.is_empty():
		return
	# If more than 3 seconds in, restart current track instead
	if _player.stream != null and _player.get_playback_position() > 3.0:
		_player.seek(0.0)
		return
	_playlist.go_prev()


func _on_next() -> void:
	if _playlist.is_empty():
		return
	_playlist.go_next()


func _on_seek_changed(val: float) -> void:
	if not _seeking:
		_player.seek(val)


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_song_finished() -> void:
	_paused = false
	var path := _playlist.advance()
	if path.is_empty():
		_refresh_play_btn()
	elif _playlist.get_play_mode() == Playlist.PlayMode.LOOP_ONE:
		# LOOP_ONE doesn't emit track_changed (same index), play manually
		_play_track(path)
	# else: advance() emitted track_changed → _on_playlist_track_changed auto-plays


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F:      _toggle_fullscreen()
		KEY_SPACE:  _on_play_pause()
		KEY_ESCAPE: _on_stop()
		KEY_LEFT:   _on_prev()
		KEY_RIGHT:  _on_next()


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
