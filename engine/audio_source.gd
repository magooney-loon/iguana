extends Node

## Centralized audio engine for Iguana.
## Owns playback, crossfade, volume, and analysis.
## Registered as an autoload — accessible from any node via AudioSource.*

signal track_finished
signal near_end

# ── Players ──────────────────────────────────────────────────────────────────
var _player: AudioStreamPlayer
var _fade_player: AudioStreamPlayer
var _crossfade_tween: Tween

# ── Crossfade ────────────────────────────────────────────────────────────────
var _near_end_triggered := false
var crossfade_duration := 2.0

# ── Volume ───────────────────────────────────────────────────────────────────
var _volume := 1.0
var _volume_before_mute := 1.0

# ── Analyzer ─────────────────────────────────────────────────────────────────
var analyzer: AudioAnalyzer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_fade_player = AudioStreamPlayer.new()
	add_child(_player)
	add_child(_fade_player)

	analyzer = AudioAnalyzer.new()
	analyzer.setup(
		AudioServer.get_bus_effect_instance(0, 0),
		_player,
	)

	_player.finished.connect(_on_player_finished)
	_fade_player.finished.connect(_on_player_finished)

	set_volume(Config.volume)
	crossfade_duration = Config.crossfade_duration


# ── Playback ─────────────────────────────────────────────────────────────────

func play(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	_cancel_crossfade()
	_player.stop()
	_player.stream = stream
	_player.volume_db = 0.0
	_player.play()
	_near_end_triggered = false
	analyzer._player = _player


func crossfade_to(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	if not _player.playing:
		play(path)
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
	# Keep _near_end_triggered = true during the fade so _check_near_end doesn't
	# re-fire on the still-playing old track and trigger a second advance().

	# Tween: fade out current player, fade in fade player
	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(_player, "volume_db", -80.0, crossfade_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_crossfade_tween.tween_property(_fade_player, "volume_db", 0.0, crossfade_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_crossfade_tween.set_parallel(false)
	_crossfade_tween.tween_callback(func():
		var old := _player
		_player = _fade_player
		_fade_player = old
		_fade_player.stop()
		_fade_player.volume_db = -80.0
		analyzer._player = _player
		# Reset only now — _player is the new track, safe to watch for its near-end.
		_near_end_triggered = false
	)


func stop() -> void:
	_cancel_crossfade()
	_player.stop()
	_player.stream = null


func seek(pos: float) -> void:
	if _player.stream != null:
		_player.seek(pos)


func set_paused(paused: bool) -> void:
	if _player.stream == null:
		return
	_player.stream_paused = paused


func start_playing() -> void:
	if _player.stream == null:
		return
	if _player.stream_paused:
		_player.stream_paused = false
	else:
		_player.play()


# ── State queries ────────────────────────────────────────────────────────────

func is_playing() -> bool:
	return _player.playing and not _player.stream_paused


func is_paused() -> bool:
	return _player.stream_paused


func is_idle() -> bool:
	return not _player.playing


func get_playback_position() -> float:
	if _player.stream == null:
		return 0.0
	return _player.get_playback_position()


func get_duration() -> float:
	if _player.stream == null:
		return 0.0
	return _player.stream.get_length()


func has_stream() -> bool:
	return _player.stream != null


func stream_was_playing() -> bool:
	# Whether the stream was playing before pause (for play/pause toggle)
	return _player.playing


# ── Volume ───────────────────────────────────────────────────────────────────

func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_volume))
	AudioServer.set_bus_mute(0, _volume < 0.005)


func get_volume() -> float:
	return _volume


func adjust_volume(delta: float) -> void:
	set_volume(_volume + delta)


func toggle_mute() -> void:
	if _volume > 0.005:
		_volume_before_mute = _volume
		set_volume(0.0)
	else:
		set_volume(_volume_before_mute)


func get_volume_icon() -> String:
	if _volume < 0.005:
		return "volume_muted"
	elif _volume < 0.4:
		return "volume_low"
	return "volume_high"


# ── Frame processing (call from visualizer each frame) ───────────────────────

func process_frame(delta: float) -> void:
	analyzer.process(delta)
	_check_near_end()


# ── Internal ─────────────────────────────────────────────────────────────────

func _on_player_finished() -> void:
	# Ignore if crossfade is handling the transition
	if _crossfade_tween and _crossfade_tween.is_valid():
		return
	_near_end_triggered = false
	track_finished.emit()


func _check_near_end() -> void:
	if _near_end_triggered:
		return
	if not _player.playing or _player.stream_paused or _player.stream == null:
		return
	var duration := _player.stream.get_length()
	if duration <= crossfade_duration * 2.0:
		return
	var remaining := duration - _player.get_playback_position()
	if remaining > crossfade_duration:
		return
	_near_end_triggered = true
	near_end.emit()


func _cancel_crossfade() -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()
	_player.volume_db = 0.0
	_fade_player.stop()
	_fade_player.volume_db = -80.0
	_near_end_triggered = false


func _load_stream(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
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
	push_warning("AudioSource: unsupported format '%s'" % ext)
	return null
