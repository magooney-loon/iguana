extends PanelContainer

# ── External references ───────────────────────────────────────────────────────
var _visualizer              # visualizer.gd node (ColorRect inside SubViewport)

# ── Player bar controls ───────────────────────────────────────────────────────
var _play_btn:   Button
var _seek_bar:   HSlider
var _time_label: Label
var _song_label: Label
var _song_tween: Tween
var _time_tween:  Tween
var _vol_btn:    Button
var _vol_slider: HSlider
var _seeking := false

# ── Logo ──────────────────────────────────────────────────────────────────────
var _logo_panel: PanelContainer

# ── Auto-hide ─────────────────────────────────────────────────────────────────
var _hide_timer    := 0.0
var _hidden        := false
var _mouse_inside  := false
var _hide_tween:   Tween
var _origin_y       := 0.0
var _logo_origin_y  := 0.0
var _origin_y_set  := false
const AUTO_HIDE_DELAY := 2.0
const AUTO_HIDE_PEEK  := 6.0

# ── Sub-systems ───────────────────────────────────────────────────────────────
var _settings:    SettingsUI
var _playlist:    Playlist
var _playlist_ui: PlaylistUI

# ── Bar buttons that need live refresh ────────────────────────────────────────
var _loop_btn:    Button
var _shuffle_btn: Button


func _ready() -> void:
	_visualizer = get_tree().root.get_node("Main/VisualizerContainer/FeedbackViewport/Visualizer")

	StylesUI.load_skin(Config.skin_name)
	# Apply individual overrides if the user mixed and matched
	if Config.theme_name != Config.skin_name:
		StylesUI.load_theme(Config.theme_name)
	if Config.style_name != Config.skin_name:
		StylesUI.load_style(Config.style_name)
	if Config.icon_pack_name != Config.skin_name:
		StylesUI.load_icons(Config.icon_pack_name)

	StylesUI.apply_bar_style(self)

	# ── Sub-systems ────────────────────────────────────────────────────
	_playlist = Playlist.new()

	# Give Main node access to the playlist for drag & drop
	var main := get_tree().root.get_node("Main")
	if main and main.has_method("set"):
		main._playlist = _playlist

	_settings = SettingsUI.new()
	_settings.setup(_visualizer, AudioSource.analyzer)
	add_child(_settings)

	_playlist_ui = PlaylistUI.new()
	_playlist_ui.setup(_playlist)
	_playlist_ui.on_track_selected = _on_playlist_jump
	add_child(_playlist_ui)

	# Build the player bar FIRST so UI controls exist before signals fire
	_build_bar()

	# Wire AudioSource signals
	AudioSource.track_finished.connect(_on_track_finished)
	AudioSource.near_end.connect(_on_near_end)

	# Connect playlist signals BEFORE adding the default track so it auto-plays
	_playlist.track_changed.connect(_on_playlist_track_changed)
	_playlist.playlist_changed.connect(_on_playlist_changed)

	# Load all tracks from the playlist directory
	_populate_from_dir("res://playlist/")

	# Restore persisted play mode
	_playlist.set_play_mode(Config.play_mode as Playlist.PlayMode)

	# Restore fullscreen state
	if Config.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Restore display settings
	if Config.vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		Engine.max_fps = 0
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = Config.max_fps

	# Restore volume (bar already built)
	AudioSource.set_volume(Config.volume)
	_refresh_vol_ui()

	_refresh_song_label()
	_refresh_mode_buttons()
	_refresh_play_btn()

	mouse_entered.connect(_on_player_mouse_entered)
	mouse_exited.connect(_on_player_mouse_exited)

	# Apply industrial noise texture to the player bar
	StylesUI.apply_aero(self, false)

	_setup_logo.call_deferred()

	StylesUI.on_reload(func() -> void:
		if not is_instance_valid(_shuffle_btn):
			return
		_shuffle_btn.modulate.a = 1.0 if _playlist.get_play_mode() == Playlist.PlayMode.SHUFFLE else StylesUI.theme().a_dim_icon
	)


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

	var pl_btn := StylesUI.icon_btn("playlist", "Playlist", Vector2(32, 28), _playlist_ui.toggle)
	top.add_child(pl_btn)

	top.add_child(StylesUI.make_vsep())

	var prev_btn := StylesUI.icon_btn("prev", "Previous track", Vector2(36, 28), _on_prev)
	top.add_child(prev_btn)

	_play_btn = StylesUI.icon_btn("play", "Play", Vector2(36, 28), _on_play_pause)
	top.add_child(_play_btn)

	var stop_btn := StylesUI.icon_btn("stop", "Stop", Vector2(36, 28), _on_stop)
	top.add_child(stop_btn)

	var next_btn := StylesUI.icon_btn("next", "Next track", Vector2(36, 28), _on_next)
	top.add_child(next_btn)

	top.add_child(StylesUI.make_vsep())

	_song_label = Label.new()
	_song_label.text = "No track loaded"
	_song_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_song_label.clip_text = true
	top.add_child(_song_label)

	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	StylesUI.track_label(_time_label, func(l: Label) -> void:
		l.modulate.a = StylesUI.theme().a_time_label
	)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_time_label)

	top.add_child(StylesUI.make_vsep())

	# Volume control
	_vol_btn = StylesUI.icon_btn("volume_high", "Mute / Unmute", Vector2(36, 28), _on_vol_mute_toggle)
	top.add_child(_vol_btn)

	_vol_slider = HSlider.new()
	_vol_slider.min_value  = 0.0
	_vol_slider.max_value  = 1.0
	_vol_slider.step       = 0.01
	_vol_slider.value      = AudioSource.get_volume()
	_vol_slider.custom_minimum_size = Vector2(80, 0)
	_vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_slider.focus_mode = Control.FOCUS_NONE
	_vol_slider.value_changed.connect(_on_vol_changed)

	StylesUI.apply_glass_slider(_vol_slider, true)

	top.add_child(_vol_slider)

	top.add_child(StylesUI.make_vsep())

	_loop_btn = StylesUI.icon_btn("loop_all", "Loop mode", Vector2(32, 28), _on_loop_pressed)
	top.add_child(_loop_btn)

	_shuffle_btn = StylesUI.icon_btn("shuffle", "Shuffle", Vector2(32, 28), _on_shuffle_pressed)
	top.add_child(_shuffle_btn)

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

	StylesUI.apply_glass_slider(_seek_bar)

	vbox.add_child(_seek_bar)

	_refresh_mode_buttons()


# ─────────────────────────────────────────────────────────────────────────────
#  Frame update
# ─────────────────────────────────────────────────────────────────────────────

func _update_logo_position() -> void:
	if not is_instance_valid(_logo_panel):
		return
	var st := StylesUI.style()
	_logo_panel.visible = st.logo_visible
	if not st.logo_visible:
		return
	var lx: float
	match st.logo_anchor:
		1: lx = 16.0
		2: lx = get_parent().size.x - _logo_panel.size.x - 16.0
		_: lx = (get_parent().size.x - _logo_panel.size.x) * 0.5
	_logo_panel.position = Vector2(lx, position.y - _logo_panel.size.y)


func _setup_logo() -> void:
	var tex := load("res://icon.webp") as Texture2D
	if tex == null:
		return

	var panel := PanelContainer.new()
	StylesUI.track_glass_panel(panel, func(p: Control) -> void:
		var s := StylesUI.glass_box(StylesUI.theme().c_logo, 18.0, true)
		s.corner_radius_bottom_left  = 0
		s.corner_radius_bottom_right = 0
		s.set_border_width_all(1)
		s.border_width_bottom   = 0
		s.shadow_size           = 0
		s.content_margin_left   = 8.0
		s.content_margin_right  = 8.0
		s.content_margin_top    = 5.0
		s.content_margin_bottom = 2.0
		p.add_theme_stylebox_override("panel", s)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 99

	var img := TextureRect.new()
	img.texture      = tex
	img.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(40.0, 40.0)
	img.size         = Vector2(40.0, 40.0)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(img)

	_logo_panel = panel
	StylesUI.apply_aero(panel, true)
	get_parent().add_child(_logo_panel)

	await get_tree().process_frame
	_update_logo_position()

	_logo_panel.mouse_entered.connect(func():
		_mouse_inside = true
		_hide_timer = 0.0
		if _hidden:
			_show_player()
	)
	_logo_panel.mouse_exited.connect(func():
		_mouse_inside = false
		_hide_timer = 0.0
	)

	get_parent().resized.connect(func():
		if is_instance_valid(_logo_panel):
			_origin_y_set = false
			_update_logo_position()
	)

	StylesUI.on_reload(func() -> void:
		if is_instance_valid(_logo_panel):
			_origin_y_set = false
			_update_logo_position()
	)


func _on_player_mouse_entered() -> void:
	_mouse_inside = true
	_hide_timer = 0.0
	if _hidden:
		_show_player()


func _on_player_mouse_exited() -> void:
	_mouse_inside = false
	_hide_timer = 0.0


func _tick_auto_hide(delta: float) -> void:
	if not Config.auto_hide_player:
		if _hidden:
			_show_player()
		return
	if _mouse_inside:
		_hide_timer = 0.0
		return
	if not _hidden:
		_hide_timer += delta
		if _hide_timer >= AUTO_HIDE_DELAY:
			_hide_player()


func _hide_player() -> void:
	if not _origin_y_set:
		_origin_y = position.y
		_logo_origin_y = _logo_panel.position.y if is_instance_valid(_logo_panel) else 0.0
		_origin_y_set = true
	_hidden = true
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	var st    := StylesUI.style()
	var slide := size.y - AUTO_HIDE_PEEK
	_hide_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(st.anim_autohide_trans)
	_hide_tween.set_parallel(true)
	_hide_tween.tween_property(self, "position:y", _origin_y + slide, st.anim_autohide_duration)
	if is_instance_valid(_logo_panel):
		_hide_tween.tween_property(_logo_panel, "position:y", _logo_origin_y + slide, st.anim_autohide_duration)


func _show_player() -> void:
	_hidden = false
	_hide_timer = 0.0
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	var st := StylesUI.style()
	_hide_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(st.anim_autohide_trans)
	_hide_tween.set_parallel(true)
	_hide_tween.tween_property(self, "position:y", _origin_y, st.anim_autohide_duration)
	if is_instance_valid(_logo_panel):
		_hide_tween.tween_property(_logo_panel, "position:y", _logo_origin_y, st.anim_autohide_duration)


func _process(delta: float) -> void:
	_update_player_ui()
	_settings.sync_frame()
	_tick_auto_hide(delta)


## Show a short-lived overlay notification on the visualizer.
func _notify(text: String) -> void:
	if is_instance_valid(_visualizer) and is_instance_valid(_visualizer._ui):
		_visualizer._ui.show_label(text)


func _update_player_ui() -> void:
	if not AudioSource.has_stream():
		_time_label.text = "0:00 / 0:00"
		return
	var duration := AudioSource.get_duration()
	var xfade_pos := AudioSource.get_crossfade_position()
	var pos := xfade_pos if xfade_pos >= 0.0 else AudioSource.get_playback_position()
	var bar_max := maxf(duration - AudioSource.crossfade_duration, 0.01)
	_time_label.text = "%s / %s" % [_fmt(pos), _fmt(duration)]
	if duration > 0.01:
		_seeking = true
		_seek_bar.max_value = bar_max
		_seek_bar.value     = minf(pos, bar_max)
		_seeking = false


# ─────────────────────────────────────────────────────────────────────────────
#  Playlist integration
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_song_label(crossfade: bool = false) -> void:
	var track := _playlist.get_current_track()
	var track_name: String
	if track.is_empty():
		track_name = "No track loaded"
	else:
		track_name = track.get_file().get_basename()
		if _playlist.size() > 1:
			track_name += "  (%d/%d)" % [_playlist.get_current_index() + 1, _playlist.size()]

	if not crossfade or _song_label.text == track_name:
		_song_label.text = track_name
		_song_label.modulate.a = 1.0
		_time_label.modulate.a = StylesUI.theme().a_time_label
		return

	if _song_tween and _song_tween.is_valid():
		_song_tween.kill()
	if _time_tween and _time_tween.is_valid():
		_time_tween.kill()
	var st := StylesUI.style()
	_song_tween = create_tween()
	_song_tween.tween_property(_song_label, "modulate:a", 0.0, st.anim_crossfade_out)
	_song_tween.tween_callback(func(): _song_label.text = track_name)
	_song_tween.tween_property(_song_label, "modulate:a", 1.0, st.anim_crossfade_in)
	_time_tween = create_tween()
	_time_tween.tween_property(_time_label, "modulate:a", 0.0, st.anim_crossfade_out)
	_time_tween.tween_callback(func(): _time_label.text = "0:00 / 0:00")
	_time_tween.tween_property(_time_label, "modulate:a", StylesUI.theme().a_time_label, st.anim_crossfade_in)


func _on_playlist_track_changed(index: int) -> void:
	if index < 0:
		# Playlist emptied — stop playback
		AudioSource.stop()
		_song_label.text = "No track loaded"
		_time_label.text = "0:00 / 0:00"
		_seek_bar.max_value = 1.0
		_seek_bar.value = 0.0
		_refresh_play_btn()
		return
	# Crossfade if audio is playing, immediate play otherwise
	var was_playing := AudioSource.is_playing()
	if was_playing:
		AudioSource.crossfade_to(_playlist.get_current_track())
	else:
		AudioSource.play(_playlist.get_current_track())
	_refresh_song_label(was_playing)
	_refresh_play_btn()


func _on_playlist_changed() -> void:
	if _playlist.is_empty():
		AudioSource.stop()
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
			_shuffle_btn.modulate.a = StylesUI.theme().a_dim_icon
		Playlist.PlayMode.LOOP_ALL:
			StylesUI.set_icon(_loop_btn, "loop_all")
			_loop_btn.tooltip_text = "Loop All (click to loop one)"
			_shuffle_btn.modulate.a = StylesUI.theme().a_dim_icon
		Playlist.PlayMode.LOOP_ONE:
			StylesUI.set_icon(_loop_btn, "loop_one")
			_loop_btn.tooltip_text = "Loop One (click to shuffle)"
			_shuffle_btn.modulate.a = StylesUI.theme().a_dim_icon
		Playlist.PlayMode.SHUFFLE:
			StylesUI.set_icon(_loop_btn, "loop_all")
			_loop_btn.tooltip_text = "Shuffle active (click for sequential)"
			_shuffle_btn.modulate.a = 1.0


# ─────────────────────────────────────────────────────────────────────────────
#  AudioSource signal handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_near_end() -> void:
	# LOOP_ONE: advance() won't emit track_changed (same index)
	if _playlist.get_play_mode() == Playlist.PlayMode.LOOP_ONE:
		AudioSource.crossfade_to(_playlist.get_current_track())
		return
	var path := _playlist.advance()
	if path.is_empty():
		return
	# advance() emitted track_changed → _on_playlist_track_changed handles crossfade


func _on_track_finished() -> void:
	var path := _playlist.advance()
	if path.is_empty():
		_refresh_play_btn()
	elif _playlist.get_play_mode() == Playlist.PlayMode.LOOP_ONE:
		# LOOP_ONE doesn't emit track_changed (same index), play manually
		AudioSource.play(path)
		_refresh_play_btn()


# ─────────────────────────────────────────────────────────────────────────────
#  Actions
# ─────────────────────────────────────────────────────────────────────────────

func _on_play_pause() -> void:
	if not AudioSource.has_stream():
		# If nothing loaded but playlist has tracks, play current
		if not _playlist.is_empty():
			AudioSource.play(_playlist.get_current_track())
			_refresh_song_label()
		return
	if AudioSource.is_paused():
		AudioSource.set_paused(false)
		_notify("Play")
	elif AudioSource.is_playing():
		AudioSource.set_paused(true)
		_notify("Pause")
	else:
		AudioSource.start_playing()
		_notify("Play")
	_refresh_play_btn()


func _on_stop() -> void:
	AudioSource.stop()
	_refresh_play_btn()
	_notify("Stopped")


func _on_prev() -> void:
	if _playlist.is_empty():
		return
	# If more than 3 seconds in, restart current track instead
	if AudioSource.has_stream() and AudioSource.get_playback_position() > 3.0:
		AudioSource.seek(0.0)
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
		AudioSource.seek(val)


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


func _on_vol_changed(v: float) -> void:
	AudioSource.set_volume(v)
	Config.volume = AudioSource.get_volume()
	Config.save()
	_refresh_vol_ui()


func _on_vol_mute_toggle() -> void:
	AudioSource.toggle_mute()
	Config.volume = AudioSource.get_volume()
	Config.save()
	_refresh_vol_ui()


func _refresh_vol_ui() -> void:
	if _vol_btn:
		StylesUI.set_icon(_vol_btn, AudioSource.get_volume_icon())
	if _vol_slider:
		_vol_slider.set_value_no_signal(AudioSource.get_volume())


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
		AudioSource.adjust_volume(0.05)
		Config.volume = AudioSource.get_volume()
		Config.save()
		_refresh_vol_ui()
		_notify("Volume %d%%" % int(AudioSource.get_volume() * 100))
	elif kc == Keymap.get_key("volume_down"):
		AudioSource.adjust_volume(-0.05)
		Config.volume = AudioSource.get_volume()
		Config.save()
		_refresh_vol_ui()
		_notify("Volume %d%%" % int(AudioSource.get_volume() * 100))
	elif kc == Keymap.get_key("mute"):
		AudioSource.toggle_mute()
		Config.volume = AudioSource.get_volume()
		Config.save()
		_refresh_vol_ui()
		_notify("Muted" if AudioSource.get_volume() < 0.005 else "Unmuted")


# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_play_btn() -> void:
	if AudioSource.is_playing():
		StylesUI.set_icon(_play_btn, "pause")
		_play_btn.tooltip_text = "Pause"
	else:
		StylesUI.set_icon(_play_btn, "play")
		_play_btn.tooltip_text = "Play"


func _populate_from_dir(dir_path: String) -> void:
	var extensions := ["mp3", "ogg", "wav"]
	var paths: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.get_extension().to_lower() in extensions:
			paths.append(dir_path + file)
		file = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	for p in paths:
		_playlist.add(p)


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
