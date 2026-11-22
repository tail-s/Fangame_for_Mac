extends Node
## TEMPORARY STUB — replaced by the procedural audio system (same API).

const SFX_NAMES: Array = []
const TRACKS: Array = []

var current_track := ""


func sfx(_name: String, _pitch := 1.0) -> void:
	pass


func music(track: String) -> void:
	current_track = track


func stop_music() -> void:
	current_track = ""


func set_volumes(_music_linear: float, _sfx_linear: float) -> void:
	pass
