extends Node2D
## Stage background: one theme per stage id (sky on a CanvasLayer behind
## everything + Parallax2D layers far -> near). Theme code lives in
## scripts/level/backdrops/ (see theme_base.gd for the drawing rules).
## main.gd adds one of these and calls set_theme(stage id) through the
## "backdrop" group on every level load; unknown ids get the training theme.

const THEMES := {
	"training": preload("res://scripts/level/backdrops/training.gd"),
	"prism_gecko": preload("res://scripts/level/backdrops/prism_gecko.gd"),
	"gravity_albatross": preload("res://scripts/level/backdrops/gravity_albatross.gd"),
	"solar_fennec": preload("res://scripts/level/backdrops/solar_fennec.gd"),
	"cryo_narwhal": preload("res://scripts/level/backdrops/cryo_narwhal.gd"),
	"terra_pangolin": preload("res://scripts/level/backdrops/terra_pangolin.gd"),
	"pulse_cicada": preload("res://scripts/level/backdrops/pulse_cicada.gd"),
	"final_eden_core": preload("res://scripts/level/backdrops/final_eden_core.gd"),
}
const DEFAULT_THEME := "training"
const ThemeBase = preload("res://scripts/level/backdrops/theme_base.gd")
const DepthProps = preload("res://scripts/level/backdrops/depth_props.gd")

## Accessibility (options menu): false disables lightning and any other bright
## flash; a flash already on screen goes away at once (even while paused).
var flashes_enabled := true:
	set(value):
		flashes_enabled = value
		if not value and _current != null:
			_current.stop_flashes()
## Theme currently shown ("" until the first set_theme).
var theme := ""
var _current: ThemeBase = null


func _ready() -> void:
	add_to_group("backdrop")
	if _current == null:
		set_theme(DEFAULT_THEME)


static func theme_for(stage_id: String) -> String:
	return stage_id if THEMES.has(stage_id) else DEFAULT_THEME


## Rebuilds the layers for the stage's theme; does nothing if it is already shown.
func set_theme(stage_id: String) -> void:
	var t := theme_for(stage_id)
	if t == theme and _current != null:
		return
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	theme = t
	_current = THEMES[t].new()
	_current.name = "Theme"
	_current.root = self
	_current.build()
	# 2.5D props in front of the theme's parallax layers, behind the play field.
	if DepthProps.PRESETS.has(t):
		var props := DepthProps.new()
		props.name = "DepthProps"
		props.style = DepthProps.PRESETS[t]
		_current.add_child(props)
	add_child(_current)


## The live theme node (tests / debugging).
func current() -> ThemeBase:
	return _current
