extends Sprite2D
## One-shot sprite effect from res://art/fx/<name>.png (a horizontal strip baked by
## tools/bake_fx.gd): plays its frames once and frees itself.

const FRAMES := {"dash_smoke": 4, "land_dust": 4, "muzzle": 3, "muzzle_gold": 3, "wall_spark": 3,
		"charge": 4, "charge_gold": 4,
		"muzzle_vanguard": 3, "muzzle_aero": 3, "muzzle_ultimate": 3,
		"charge_vanguard1": 4, "charge_vanguard2": 4, "charge_aero1": 4, "charge_aero2": 4,
		"charge_ultimate1": 4, "charge_ultimate2": 4}
const DIR := "res://art/fx/"

static var _tex := {}

var fps := 18.0
var _frames := 1
var _t := 0.0


static func strip(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(DIR + name + ".png")
	return _tex[name]


func setup(name: String, speed := 18.0) -> void:
	texture = strip(name)
	_frames = FRAMES.get(name, 1)
	fps = speed
	region_enabled = true
	_show(0)


func _show(f: int) -> void:
	var cw := texture.get_width() / _frames
	region_rect = Rect2(f * cw, 0, cw, texture.get_height())


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t * fps)
	if f >= _frames:
		queue_free()
		return
	_show(f)
