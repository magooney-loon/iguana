extends Control
## Root node script for Iguana. Handles OS-level file drops onto the window.

var _playlist: Playlist  # set by player_ui.gd in _ready()


func _ready() -> void:
	get_window().files_dropped.connect(_on_files_dropped)


func _on_files_dropped(files: PackedStringArray) -> void:
	var audio_exts := ["mp3", "ogg", "wav"]
	var audio_files: PackedStringArray = []
	for file in files:
		if file.get_extension().to_lower() in audio_exts:
			audio_files.append(file)
	if not audio_files.is_empty() and _playlist != null:
		_playlist.add_many(audio_files)
