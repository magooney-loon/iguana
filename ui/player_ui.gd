extends PanelContainer

var _player: AudioStreamPlayer

var _play_btn:   Button
var _song_label: Label
var _time_label: Label
var _seek_bar:   HSlider
var _file_dialog: FileDialog
var _paused  := false
var _seeking := false  # true while code updates the slider to avoid feedback

func _ready() -> void:
	_player = owner.get_node("Player") as AudioStreamPlayer

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 1.0)
	style.content_margin_left   = 12.0
	style.content_margin_right  = 12.0
	style.content_margin_top    = 7.0
	style.content_margin_bottom = 7.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# ── Controls row ──────────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed)
	hbox.add_child(load_btn)

	_play_btn = Button.new()
	_play_btn.custom_minimum_size = Vector2(38, 0)
	_play_btn.pressed.connect(_on_play_pause_pressed)
	hbox.add_child(_play_btn)

	_song_label = Label.new()
	_song_label.text = "Tomcraft - Loneliness"
	_song_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_song_label.clip_text = true
	hbox.add_child(_song_label)

	_time_label = Label.new()
	_time_label.text = "0:00 / 0:00"
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.modulate.a = 0.7
	hbox.add_child(_time_label)

	var hint := Label.new()
	hint.text = "Q/E shader   S shuffle"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.4
	hbox.add_child(hint)

	# ── Seek bar row ──────────────────────────────────────────────
	_seek_bar = HSlider.new()
	_seek_bar.min_value = 0.0
	_seek_bar.max_value = 1.0
	_seek_bar.step      = 0.01
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.focus_mode = Control.FOCUS_NONE  # don't steal keyboard focus
	_seek_bar.value_changed.connect(_on_seek_value_changed)
	vbox.add_child(_seek_bar)

	# ── File dialog ───────────────────────────────────────────────
	_file_dialog = FileDialog.new()
	_file_dialog.access    = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters   = PackedStringArray(["*.mp3,*.ogg ; Audio Files"])
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_player.finished.connect(_on_song_finished)
	_update_play_btn()

func _process(_delta: float) -> void:
	if _player == null or _player.stream == null:
		return
	var pos := _player.get_playback_position()
	var duration := _player.stream.get_length()

	_time_label.text = "%s / %s" % [_fmt(pos), _fmt(duration)]

	if duration > 0.01:
		_seeking = true
		_seek_bar.max_value = duration
		_seek_bar.value     = pos
		_seeking = false

func _on_seek_value_changed(val: float) -> void:
	if not _seeking:
		_player.seek(val)

func _on_load_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.65)

func _on_play_pause_pressed() -> void:
	if not _player.playing:
		_player.play()
		_paused = false
	else:
		_paused = !_paused
		_player.stream_paused = _paused
	_update_play_btn()

func _on_file_selected(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.play()
	_paused = false
	_song_label.text = path.get_file()
	_update_play_btn()

func _on_song_finished() -> void:
	_paused = false
	_update_play_btn()

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
	push_warning("PlayerUI: unsupported format '%s' — only mp3 and ogg supported" % ext)
	return null

func _update_play_btn() -> void:
	_play_btn.text = "⏸" if (_player.playing and not _paused) else "▶"

func _fmt(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [int(s / 60.0), s % 60]
