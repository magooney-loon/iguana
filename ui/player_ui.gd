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
var _vol_btn:    Button
var _vol_slider: HSlider
var _volume     := 1.0

# ── Crossfade ──────────────────────────────────────────────────────────────
var _fade_player:       AudioStreamPlayer
var _crossfade_tween:   Tween
var _near_end_triggered := false
const CROSSFADE_DURATION := 2.0

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

	# Second player for crossfade transitions
	_fade_player = AudioStreamPlayer.new()
	add_child(_fade_player)

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

	_player.finished.connect(_on_song_finished)
	_fade_player.finished.connect(_on_song_finished)

	# Populate playlist with the default song BEFORE connecting our handler
	# so we don't restart the already-playing autoplay track
	if _player.stream != null:
		var rpath := _player.stream.resource_path
		if not rpath.is_empty():
			_playlist.add(rpath)

	# Now connect — all future track changes auto-play
	_playlist.track_changed.connect(_on_playlist_track_changed)
	_playlist.playlist_changed.connect(_on_playlist_changed)

	# Restore persisted play mode
	_playlist.set_play_mode(Config.play_mode as Playlist.PlayMode)

	# Restore fullscreen state
	if Config.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Build the player bar (creates _vol_btn, _vol_slider, etc.)
	_build_bar()

	# Restore volume (after bar is built so icon/slider update)
	_set_volume(Config.volume)

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

	var prev_btn := StylesUI.icon_btn("prev", "Previous track", Vector2(32, 28), _on_prev)
	top.add_child(prev_btn)

	_play_btn = StylesUI.icon_btn("play", "Play", Vector2(36, 28), _on_play_pause)
	top.add_child(_play_btn)

	var stop_btn := StylesUI.icon_btn("stop", "Stop", Vector2(32, 28), _on_stop)
	top.add_child(stop_btn)

	var next_btn := StylesUI.icon_btn("next", "Next track", Vector2(32, 28), _on_next)
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

	# Volume control
	_vol_btn = StylesUI.icon_btn("volume_high", "Mute / Unmute", Vector2(32, 28), _on_vol_mute_toggle)
	top.add_child(_vol_btn)

	_vol_slider = HSlider.new()
	_vol_slider.min_value  = 0.0
	_vol_slider.max_value  = 1.0
	_vol_slider.step       = 0.01
	_vol_slider.value      = _volume
	_vol_slider.custom_minimum_size = Vector2(80, 0)
	_vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_slider.focus_mode = Control.FOCUS_NONE
	_vol_slider.value_changed.connect(_on_vol_changed)

	var vs_bg := StylesUI.glass_box(Color(0.04, 0.05, 0.10, 0.50), 5.0, false)
	vs_bg.content_margin_top = 6.0
	vs_bg.content_margin_bottom = 6.0
	_vol_slider.add_theme_stylebox_override("slider", vs_bg)

	var vs_fill := StylesUI.glass_box(Color(0.30, 0.45, 0.75, 0.50), 5.0, false)
	vs_fill.content_margin_top = 6.0
	vs_fill.content_margin_bottom = 6.0
	_vol_slider.add_theme_stylebox_override("fill", vs_fill)

	var vs_grab := StylesUI.glass_box(Color(0.55, 0.70, 1.0, 0.80), 8.0, true)
	vs_grab.content_margin_left = 4.0
	vs_grab.content_margin_right = 4.0
	vs_grab.content_margin_top = 4.0
	vs_grab.content_margin_bottom = 4.0
	_vol_slider.add_theme_stylebox_override("grabber_area", vs_grab)
	_vol_slider.add_theme_stylebox_override("grabber_area_highlight", vs_grab)

	top.add_child(_vol_slider)

	top.add_child(StylesUI.make_vsep())

	_loop_btn = StylesUI.icon_btn("loop_all", "Loop mode", Vector2(32, 28), _on_loop_pressed)
	top.add_child(_loop_btn)

	_shuffle_btn = StylesUI.icon_btn("shuffle", "Shuffle", Vector2(32, 28), _on_shuffle_pressed)
	top.add_child(_shuffle_btn)

	var pl_btn := StylesUI.icon_btn("playlist", "Playlist", Vector2(32, 28), _playlist_ui.toggle)
	top.add_child(pl_btn)

	var fs_btn := StylesUI.icon_btn("fullscreen", "Fullscreen", Vector2(32, 28), _toggle_fullscreen)
	top.add_child(fs_btn)

	var set_btn := StylesUI.icon_btn("settings", "Settings", Vector2(32, 28), _settings.toggle)
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
	_check_near_end()


## Show a short-lived overlay notification on the visualizer.
func _notify(text: String) -> void:
	if is_instance_valid(_visualizer) and is_instance_valid(_visualizer._ui):
		_visualizer._ui.show_label(text)


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
	_player.volume_db = 0.0
	_player.play()
	_paused = false
	_near_end_triggered = false
	_refresh_song_label()
	_seek_bar.max_value = stream.get_length()
	_refresh_play_btn()


func _crossfade_to(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return

	# Kill any in-progress crossfade and reset state
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
		_player.volume_db = 0.0
		_fade_player.stop()
		_fade_player.volume_db = -80.0

	# Start the new track on the fade player at silence
	_fade_player.stream = stream
	_fade_player.volume_db = -80.0
	_fade_player.play()

	_near_end_triggered = false
	_refresh_song_label()
	_seek_bar.max_value = stream.get_length()
	_refresh_play_btn()

	# Tween: fade out current player, fade in fade player
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(_player, "volume_db", -80.0, CROSSFADE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_crossfade_tween.tween_property(_fade_player, "volume_db", 0.0, CROSSFADE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_crossfade_tween.set_parallel(false)
	_crossfade_tween.tween_callback(func():
		# Swap players: the fade player becomes the main player
		var old_player := _player
		_player = _fade_player
		_fade_player = old_player
		_fade_player.stop()
		_fade_player.volume_db = -80.0
		# Keep analyzer pointing at the active player so is_sounding stays correct
		_analyzer._player = _player
	)


func _cancel_crossfade() -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_player.volume_db = 0.0
	_fade_player.stop()
	_fade_player.volume_db = -80.0
	_near_end_triggered = false


func _check_near_end() -> void:
	if _near_end_triggered:
		return
	if not _player.playing or _player.stream_paused or _player.stream == null:
		return
	var duration := _player.stream.get_length()
	if duration <= CROSSFADE_DURATION * 2.0:
		return  # Too short for crossfade
	var remaining := duration - _player.get_playback_position()
	if remaining > CROSSFADE_DURATION:
		return
	_near_end_triggered = true
	# LOOP_ONE: advance() won't emit track_changed (same index)
	if _playlist.get_play_mode() == Playlist.PlayMode.LOOP_ONE:
		_crossfade_to(_playlist.get_current_track())
		return
	var path := _playlist.advance()
	if path.is_empty():
		_near_end_triggered = false
	# else: advance() emitted track_changed → _on_playlist_track_changed → _crossfade_to


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
		_cancel_crossfade()
		_player.stop()
		_player.stream = null
		_paused = false
		_song_label.text = "No track loaded"
		_time_label.text = "0:00 / 0:00"
		_seek_bar.max_value = 1.0
		_seek_bar.value = 0.0
		_refresh_play_btn()
		return
	# Crossfade if audio is playing, immediate play otherwise
	if _player.playing and not _paused:
		_crossfade_to(_playlist.get_current_track())
	else:
		_cancel_crossfade()
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
	Config.play_mode = _playlist.get_play_mode() as int
	Config.save()
	_refresh_mode_buttons()
	_notify(_mode_label())


func _on_shuffle_pressed() -> void:
	if _playlist.get_play_mode() == Playlist.PlayMode.SHUFFLE:
		_playlist.set_play_mode(Playlist.PlayMode.LOOP_ALL)
	else:
		_playlist.set_play_mode(Playlist.PlayMode.SHUFFLE)
	Config.play_mode = _playlist.get_play_mode() as int
	Config.save()
	_refresh_mode_buttons()
	_notify(_mode_label())


func _refresh_mode_buttons() -> void:
	match _playlist.get_play_mode():
		Playlist.PlayMode.SEQUENTIAL:
			StylesUI.set_icon(_loop_btn, "loop_none")
			_loop_btn.tooltip_text = "Sequential (click to loop all)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.LOOP_ALL:
			StylesUI.set_icon(_loop_btn, "loop_all")
			_loop_btn.tooltip_text = "Loop All (click to loop one)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.LOOP_ONE:
			StylesUI.set_icon(_loop_btn, "loop_one")
			_loop_btn.tooltip_text = "Loop One (click to shuffle)"
			_shuffle_btn.modulate.a = 0.5
		Playlist.PlayMode.SHUFFLE:
			StylesUI.set_icon(_loop_btn, "loop_all")
			_loop_btn.tooltip_text = "Shuffle active (click for sequential)"
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
		_notify("Play")
	elif _player.playing:
		_player.stream_paused = true
		_paused = true
		_notify("Pause")
	else:
		_player.play()
		_paused = false
		_notify("Play")
	_refresh_play_btn()


func _on_stop() -> void:
	_cancel_crossfade()
	_player.stop()
	_paused = false
	_refresh_play_btn()
	_notify("Stopped")


func _on_prev() -> void:
	if _playlist.is_empty():
		return
	# If more than 3 seconds in, restart current track instead
	if _player.stream != null and _player.get_playback_position() > 3.0:
		_player.seek(0.0)
		_notify("Restart")
		return
	_playlist.go_prev()
	_notify("Previous")


func _on_next() -> void:
	if _playlist.is_empty():
		return
	_playlist.go_next()
	_notify("Next")


func _on_seek_changed(val: float) -> void:
	if not _seeking:
		_player.seek(val)


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		Config.fullscreen = false
		_notify("Windowed")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		Config.fullscreen = true
		_notify("Fullscreen")
	Config.save()


func _set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_volume))
	AudioServer.set_bus_mute(0, _volume < 0.005)
	_refresh_vol_icon()
	if _vol_slider:
		_vol_slider.set_value_no_signal(_volume)


func _on_vol_changed(v: float) -> void:
	_set_volume(v)
	Config.volume = _volume
	Config.save()


var _volume_before_mute := 1.0


func _on_vol_mute_toggle() -> void:
	if _volume > 0.005:
		_volume_before_mute = _volume
		_set_volume(0.0)
	else:
		_set_volume(_volume_before_mute)
	Config.volume = _volume
	Config.save()


func _refresh_vol_icon() -> void:
	if _vol_btn == null:
		return
	if _volume < 0.005:
		StylesUI.set_icon(_vol_btn, "volume_muted")
	elif _volume < 0.4:
		StylesUI.set_icon(_vol_btn, "volume_low")
	else:
		StylesUI.set_icon(_vol_btn, "volume_high")


func _on_song_finished() -> void:
	_paused = false
	if _near_end_triggered:
		# Near-end crossfade already started the next track — nothing to do.
		# The crossfade completion callback will swap players.
		_near_end_triggered = false
		return
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
	var kc: int = (event as InputEventKey).keycode
	if kc == Keymap.get_key("play_pause"):
		_on_play_pause()
	elif kc == Keymap.get_key("stop"):
		_on_stop()
	elif kc == Keymap.get_key("prev_track"):
		_on_prev()
	elif kc == Keymap.get_key("next_track"):
		_on_next()
	elif kc == Keymap.get_key("fullscreen"):
		_toggle_fullscreen()
	elif kc == Keymap.get_key("toggle_playlist"):
		_playlist_ui.toggle()
	elif kc == Keymap.get_key("toggle_settings"):
		_settings.toggle()
	elif kc == Keymap.get_key("volume_up"):
		_set_volume(_volume + 0.05)
		Config.volume = _volume
		Config.save()
		_notify("Volume %d%%" % int(_volume * 100))
	elif kc == Keymap.get_key("volume_down"):
		_set_volume(_volume - 0.05)
		Config.volume = _volume
		Config.save()
		_notify("Volume %d%%" % int(_volume * 100))


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
	if _player.playing and not _paused:
		StylesUI.set_icon(_play_btn, "pause")
		_play_btn.tooltip_text = "Pause"
	else:
		StylesUI.set_icon(_play_btn, "play")
		_play_btn.tooltip_text = "Play"


func _fmt(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _mode_label() -> String:
	match _playlist.get_play_mode():
		Playlist.PlayMode.SEQUENTIAL: return "Sequential"
		Playlist.PlayMode.LOOP_ALL:  return "Loop All"
		Playlist.PlayMode.LOOP_ONE:  return "Loop One"
		Playlist.PlayMode.SHUFFLE:   return "Shuffle"
	return ""
