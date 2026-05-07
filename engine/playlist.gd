class_name Playlist
extends RefCounted

enum PlayMode { SEQUENTIAL, LOOP_ALL, LOOP_ONE, SHUFFLE }

signal track_changed(index: int)
signal playlist_changed()

var _tracks: Array[String] = []
var _current_index: int = -1
var _play_mode: PlayMode = PlayMode.LOOP_ALL

# Shuffle state
var _shuffled_order: Array[int] = []
var _shuffle_pos: int = -1


func size() -> int:
	return _tracks.size()


func is_empty() -> bool:
	return _tracks.is_empty()


func get_current_index() -> int:
	return _current_index


func get_track(idx: int) -> String:
	if idx < 0 or idx >= _tracks.size():
		return ""
	return _tracks[idx]


func get_current_track() -> String:
	return get_track(_current_index)


func get_tracks() -> Array[String]:
	return _tracks


func get_play_mode() -> PlayMode:
	return _play_mode


func set_play_mode(mode: PlayMode) -> void:
	_play_mode = mode
	if mode == PlayMode.SHUFFLE:
		_rebuild_shuffle()


func cycle_play_mode() -> PlayMode:
	match _play_mode:
		PlayMode.SEQUENTIAL:
			set_play_mode(PlayMode.LOOP_ALL)
		PlayMode.LOOP_ALL:
			set_play_mode(PlayMode.LOOP_ONE)
		PlayMode.LOOP_ONE:
			set_play_mode(PlayMode.SHUFFLE)
		PlayMode.SHUFFLE:
			set_play_mode(PlayMode.SEQUENTIAL)
	return _play_mode


# ── Mutations ─────────────────────────────────────────────────────────────────

func add(path: String) -> void:
	_tracks.append(path)
	_invalidate_shuffle()
	playlist_changed.emit()
	if _current_index < 0:
		_current_index = 0
		track_changed.emit(0)


func add_many(paths: PackedStringArray) -> void:
	var was_empty := _tracks.is_empty()
	for p in paths:
		_tracks.append(p)
	_invalidate_shuffle()
	playlist_changed.emit()
	if was_empty and not _tracks.is_empty():
		_current_index = 0
		track_changed.emit(0)


func remove(idx: int) -> void:
	if idx < 0 or idx >= _tracks.size():
		return
	_tracks.remove_at(idx)
	_invalidate_shuffle()

	if _tracks.is_empty():
		_current_index = -1
		track_changed.emit(-1)
		playlist_changed.emit()
		return

	# Adjust current index after removal
	if idx < _current_index:
		_current_index -= 1
	elif idx == _current_index:
		_current_index = mini(_current_index, _tracks.size() - 1)
		track_changed.emit(_current_index)

	playlist_changed.emit()


func clear() -> void:
	_tracks.clear()
	_current_index = -1
	_invalidate_shuffle()
	track_changed.emit(-1)
	playlist_changed.emit()


func move_track(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= _tracks.size():
		return
	if to_idx < 0 or to_idx >= _tracks.size():
		return
	if from_idx == to_idx:
		return
	var item: String = _tracks.pop_at(from_idx)
	_tracks.insert(to_idx, item)

	# Adjust current index
	if from_idx == _current_index:
		_current_index = to_idx
	else:
		if from_idx < _current_index and to_idx >= _current_index:
			_current_index -= 1
		elif from_idx > _current_index and to_idx <= _current_index:
			_current_index += 1

	_invalidate_shuffle()
	playlist_changed.emit()


# ── Navigation ────────────────────────────────────────────────────────────────

## Called when the current track finishes playing naturally.
## Returns the next track path, or "" if playback should stop.
func advance() -> String:
	if _tracks.is_empty():
		return ""

	match _play_mode:
		PlayMode.LOOP_ONE:
			return get_current_track()

		PlayMode.SEQUENTIAL:
			if _current_index + 1 < _tracks.size():
				_current_index += 1
				track_changed.emit(_current_index)
				return get_current_track()
			return ""  # end of playlist

		PlayMode.LOOP_ALL:
			_current_index = (_current_index + 1) % _tracks.size()
			track_changed.emit(_current_index)
			return get_current_track()

		PlayMode.SHUFFLE:
			return _advance_shuffle()

	return ""


## Explicitly go to next track (user pressed next). Wraps in loop modes.
func go_next() -> String:
	if _tracks.is_empty():
		return ""
	if _play_mode == PlayMode.SHUFFLE:
		return _advance_shuffle()
	_current_index = (_current_index + 1) % _tracks.size()
	track_changed.emit(_current_index)
	return get_current_track()


## Explicitly go to previous track (user pressed prev). Wraps in loop modes.
func go_prev() -> String:
	if _tracks.is_empty():
		return ""
	if _play_mode == PlayMode.SHUFFLE:
		return _retreat_shuffle()
	_current_index = (_current_index - 1 + _tracks.size()) % _tracks.size()
	track_changed.emit(_current_index)
	return get_current_track()


## Jump to a specific index (e.g. user clicked a track in the list).
func jump_to(idx: int) -> String:
	if idx < 0 or idx >= _tracks.size():
		return ""
	_current_index = idx
	track_changed.emit(_current_index)
	return get_current_track()


# ── Shuffle internals ─────────────────────────────────────────────────────────

func _rebuild_shuffle() -> void:
	_shuffled_order.clear()
	if _tracks.is_empty():
		_shuffle_pos = -1
		return
	for i in _tracks.size():
		_shuffled_order.append(i)
	# Fisher-Yates
	_shuffled_order.shuffle()
	# Put current track first if there is one
	if _current_index >= 0:
		var pos := _shuffled_order.find(_current_index)
		if pos >= 0:
			_shuffled_order.remove_at(pos)
			_shuffled_order.insert(0, _current_index)
	_shuffle_pos = 0


func _advance_shuffle() -> String:
	if _shuffled_order.is_empty():
		_rebuild_shuffle()
		if _shuffled_order.is_empty():
			return ""
	_shuffle_pos += 1
	if _shuffle_pos >= _shuffled_order.size():
		# Reshuffle and start over (loop)
		_rebuild_shuffle()
		_shuffle_pos = 0
	_current_index = _shuffled_order[_shuffle_pos]
	track_changed.emit(_current_index)
	return get_current_track()


func _retreat_shuffle() -> String:
	if _shuffled_order.is_empty():
		_rebuild_shuffle()
		if _shuffled_order.is_empty():
			return ""
	_shuffle_pos -= 1
	if _shuffle_pos < 0:
		_shuffle_pos = 0
	_current_index = _shuffled_order[_shuffle_pos]
	track_changed.emit(_current_index)
	return get_current_track()


func _invalidate_shuffle() -> void:
	_shuffled_order.clear()
	_shuffle_pos = -1
