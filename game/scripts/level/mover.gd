extends AnimatableBody2D
## Moving platform: 'm' runs slide left-right, 'n' runs bob up-down, by AMPLITUDE
## pixels over PERIOD seconds. The player rides it through move_and_slide().

const Layers = preload("res://scripts/core/layers.gd")
const AMPLITUDE := 48.0
const PERIOD := 3.2
## Car pieces (tools/bake_devices.gd): column = single / left / middle / right,
## row = 0 slider ('m'), 1 lift ('n').
const TEX = preload("res://art/devices/mover.png")
const TILE := 16.0
## Lamp gold (dim -> glint) and thruster jet (orange -> white).
const LIGHT := [Color("a3772a"), Color("f0b84a"), Color("ffe3a0"), Color("fff8e0")]
const JET := [Color("ef9352"), Color("f0b84a"), Color("fff0b0")]

var rect := Rect2()
var axis := Vector2.RIGHT
var _base := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = true
	_base = rect.position
	position = _base
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.size / 2.0
	add_child(cs)


func _physics_process(delta: float) -> void:
	_t += delta
	position = _base + axis * sin(_t * TAU / PERIOD) * AMPLITUDE
	queue_redraw()  # direction lamps and thruster jets follow the motion


func _draw() -> void:
	var row := 0 if axis.x != 0.0 else 1
	var n := int(rect.size.x / TILE)
	for i in n:
		var piece := 0 if n == 1 else (1 if i == 0 else (3 if i == n - 1 else 2))
		draw_texture_rect_region(TEX, Rect2(i * TILE, 0, TILE, TILE), Rect2(piece * TILE, row * TILE, TILE, TILE))
	# Direction: velocity along the axis (d/dt of the sine in _physics_process).
	var v := cos(_t * TAU / PERIOD)
	var moving := absf(v) > 0.12
	var blink := int(_t * 8.0) % 2 == 0
	if row == 0:
		# Slider: the lamp on the leading end lights, window lights chase that way.
		var lead_right := v > 0.0
		_lamp(Vector2(2, 7), moving and not lead_right, blink)
		_lamp(Vector2(rect.size.x - 3.0, 7), moving and lead_right, blink)
		if moving and n > 1:
			var step := int(_t * 10.0)
			for i in n:
				var k := posmod(i - step if lead_right else i + step, 3)
				if k == 0:
					draw_rect(Rect2(i * TILE + 6.0, 7, 4, 1), LIGHT[2])
					draw_rect(Rect2(i * TILE + 6.0, 8, 4, 1), LIGHT[1])
	else:
		# Lift: both lamps on; thruster jets long while rising, short sinking.
		_lamp(Vector2(2, 7), true, true)
		_lamp(Vector2(rect.size.x - 3.0, 7), true, true)
		var rising := v > 0.0
		var flick := int(_t * 30.0) % 2
		for i in n:
			for nx in [3.0, 10.0]:
				var x: float = i * TILE + nx
				var h := (4.0 if rising else 1.0) + float(flick)
				draw_rect(Rect2(x, 16, 3, h), Color(JET[0], 0.8))
				draw_rect(Rect2(x + 1.0, 16, 1, h + 1.0), JET[1])
				draw_rect(Rect2(x + 1.0, 16, 1, maxf(1.0, h - 2.0)), JET[2])


## Direction lamp in the nose bezel (2 px tall).
func _lamp(p: Vector2, lit: bool, blink: bool) -> void:
	if not lit:
		return
	draw_rect(Rect2(p, Vector2(1, 2)), LIGHT[1] if blink else LIGHT[2])
	draw_rect(Rect2(p, Vector2(1, 1)), LIGHT[3])
