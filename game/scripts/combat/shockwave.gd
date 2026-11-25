extends Area2D
## Sky Breaker landing wave: runs along the ground and hits each enemy once.

const Layers = preload("res://scripts/core/layers.gd")

var dir := 1
var speed := 240.0
var damage := 3
var life := 0.6
var _t := 0.0
var _hit := {}


func _ready() -> void:
	collision_layer = Layers.PLAYER_SHOT
	collision_mask = Layers.ENEMY
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 18)
	cs.shape = rect
	cs.position = Vector2(0, -9)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position.x += dir * speed * delta
	_t += delta
	if _t >= life:
		queue_free()
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not _hit.has(body):
		_hit[body] = true
		body.take_damage(damage)


# Aero energy blade rising off the ground (dark trailing edge, bright leading edge,
# white crest), a ground streak and kicked-up grit; fades out over its life.
# Colours: the Aero armor's blue energy (scripts/fx/armor_fx.gd).
const MINT := [Color("1f5fb8"), Color("2f8cff"), Color("8ec8ff"), Color("eef8ff")]
const GRIT := Color("8aa7bd")


func _draw() -> void:
	var a := 1.0 - _t / life
	var h := roundf(18.0 * (0.6 + 0.4 * sin(_t * 40.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
	draw_rect(Rect2(-10, -2, 18, 1), Color(MINT[3], a))
	draw_rect(Rect2(-9, -1, 16, 1), Color(MINT[1], a * 0.8))
	for r in int(h):
		var t := r / h
		var l := roundf(-7.0 + 11.0 * t)
		var f := maxf(roundf(8.0 - 3.0 * t * t), l + 1.0)
		var y := -3.0 - r
		if t > 0.82:
			draw_rect(Rect2(l, y, f - l, 1), Color(MINT[3], a))
			continue
		var w := f - l
		var back := minf(2.0, floorf(w / 3.0))
		var lead := minf(2.0, w - back)
		draw_rect(Rect2(l, y, back, 1), Color(MINT[0], a))
		draw_rect(Rect2(l + back, y, w - back - lead, 1), Color(MINT[1] if t < 0.45 else MINT[2], a))
		draw_rect(Rect2(f - lead, y, lead, 1), Color(MINT[3] if r % 3 == 0 else MINT[2], a))
	for i in 3:
		var k := fmod(_t / life * 1.6 + i * 0.3, 1.0)
		var p := Vector2(-5.0 - i * 3.0 - k * 6.0, -2.0 - sin(k * PI) * (7.0 + i * 3.0)).round()
		draw_rect(Rect2(p, Vector2(2, 2) if i == 0 else Vector2.ONE), Color(GRIT, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
