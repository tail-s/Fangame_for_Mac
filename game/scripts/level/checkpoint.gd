extends Area2D
## Respawn point. Lights up when the player touches it.

const Autoloads = preload("res://scripts/core/autoloads.gd")

signal reached(pos: Vector2)

const Layers = preload("res://scripts/core/layers.gd")
## Beacon sprite (tools/bake_devices.gd): frame 0 unlit, 1-4 lit (LED chase).
const TEX = preload("res://art/devices/checkpoint.png")
const FRAME := Vector2(18, 46)
const LENS := Vector2(0, -36)

var active := false
var _t := 0.0


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 40)
	cs.shape = rect
	cs.position = Vector2(0, -20)
	add_child(cs)
	body_entered.connect(_on_body_entered)


## announce = false when restoring an already-reached checkpoint after a respawn.
func activate(announce := true) -> void:
	if active:
		return
	active = true
	if announce:
		Autoloads.sfx("checkpoint")
		reached.emit(global_position)
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		activate()


func _process(delta: float) -> void:
	_t += delta
	if active:
		queue_redraw()


func _draw() -> void:
	var frame := 0
	if active:
		# Lens light stepping in and out with the pulse (whole-pixel radii).
		var r := 7.0 + roundf(sin(_t * 6.0) * 1.5)
		draw_circle(LENS, r, Color(0.0, 0.72, 0.75, 0.14))
		draw_circle(LENS, r - 3.0, Color(0.0, 0.72, 0.75, 0.18))
		frame = 1 + int(_t * 8.0) % 4
	draw_texture_rect_region(TEX, Rect2(-FRAME.x / 2.0, -FRAME.y, FRAME.x, FRAME.y),
			Rect2(frame * FRAME.x, 0, FRAME.x, FRAME.y))
