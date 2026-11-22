extends Area2D
## Player projectile.
## kind "buster": IX's buster. level 0 = tap shot, 1 = mid charge, 2 = full charge.
##   A full charge passes through enemies it destroys (all enemies with Vanguard ARM).
##   Armor flags: breaker (breaks cracked walls), homing (tap shots curve toward a
##   close enemy), spread pieces (Aero ARM: three smaller shots).
## kind "echo": ECHO's rapid-fire pistol round (any direction).
## kind "copy": ECHO's copy round — destroying an enemy with it copies its data.

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")

const SIZES := [Vector2(6, 4), Vector2(10, 8), Vector2(22, 14)]
const HOMING_RANGE := 72.0

var kind := "buster"
var level := 0
var dir := 1
var velocity := Vector2.ZERO
var damage := 1
var pierce := false
var pierce_all := false
var breaker := false
var homing := false
var small := false
var life := 1.3
var source = null
var _t := 0.0
var _hit := {}
var _done := false


func setup(lv: int, d: int, angle := 0.0, spread_piece := false) -> void:
	kind = "buster"
	level = clampi(lv, 0, 2)
	dir = d
	small = spread_piece
	var speed := 300.0
	match level:
		0:
			damage = 1
		1:
			speed = 330.0
			damage = 1 if small else 2
		_:
			speed = 360.0
			damage = 2 if small else 4
			pierce = true
	velocity = Vector2(cos(angle) * dir, sin(angle)) * speed


## ECHO rounds: "echo" (rapid fire) or "copy" (copy round), fired along `aim`.
func setup_vector(k: String, aim: Vector2, src) -> void:
	kind = k
	source = src
	level = 0
	dir = 1 if aim.x >= 0.0 else -1
	if k == "copy":
		velocity = aim.normalized() * 210.0
		damage = 2
		life = 1.0
	else:
		velocity = aim.normalized() * 340.0
		damage = 1
		life = 0.9


func _ready() -> void:
	collision_layer = Layers.PLAYER_SHOT
	collision_mask = Layers.WORLD | Layers.ENEMY
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	match kind:
		"echo":
			rect.size = Vector2(5, 5)
			add_to_group("echo_shot")
		"copy":
			rect.size = Vector2(9, 9)
			add_to_group("copy_shot")
		_:
			rect.size = SIZES[level] * (0.7 if small else 1.0)
			if level == 0:
				add_to_group("player_shot_small")
	cs.shape = rect
	add_child(cs)
	add_to_group("player_shot")
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if homing:
		_steer(delta)
	position += velocity * delta
	_t += delta
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _steer(delta: float) -> void:
	var best = null
	var best_d := HOMING_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		var c: Vector2 = e.global_position + Vector2(0, -8)
		var off: Vector2 = c - global_position
		if off.x * dir > 0.0 and off.length() < best_d:
			best = c
			best_d = off.length()
	if best != null:
		var want := clampf((best.y - global_position.y) * 5.0, -140.0, 140.0)
		velocity.y = move_toward(velocity.y, want, 900.0 * delta)


func _on_body_entered(body: Node) -> void:
	if _done:
		return
	if body.is_in_group("enemy"):
		if _hit.has(body):
			return
		_hit[body] = true
		var killed: bool = body.take_damage(damage, kind)
		if source != null and is_instance_valid(source):
			source.register_hit()
			if kind == "copy" and killed:
				source.on_copy_kill(body.get("copy_kind"))
		if not (pierce_all or (pierce and killed)):
			_impact()
	elif body.is_in_group("breakable"):
		if breaker:
			body.break_wall()
		_impact()
	else:
		_impact()


func _impact() -> void:
	_done = true
	var fx := Explosion.new()
	fx.size = 5.0
	fx.duration = 0.15
	fx.position = position + Vector2(dir * 4, 0)
	get_parent().add_child(fx)
	queue_free()


func _draw() -> void:
	if kind == "echo":
		draw_circle(Vector2.ZERO, 2.5, Color("5ad19a"))
		draw_circle(Vector2.ZERO, 1.2, Color.WHITE)
		return
	if kind == "copy":
		var c := Color("b78af3") if int(_t * 20.0) % 2 == 0 else Color("5ad19a")
		draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 12, c, 2.0)
		draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
		return
	var k := 0.7 if small else 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	match level:
		0:
			draw_rect(Rect2(-3, -2, 6, 4), Color("f0b84a"))
			draw_rect(Rect2(-2, -1, 4, 2), Color("fff6d8"))
		1:
			draw_rect(Rect2(-dir * 9 - 2, -1, 6, 2), Color("3de0ee", 0.5))
			draw_circle(Vector2.ZERO, 4.5, Color("3de0ee"))
			draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
		_:
			var c := Color("f0b84a") if int(_t * 30.0) % 2 == 0 else Color("3de0ee")
			var pts := PackedVector2Array([
				Vector2(11 * dir, 0), Vector2(2 * dir, -7), Vector2(-11 * dir, -5),
				Vector2(-6 * dir, 0), Vector2(-11 * dir, 5), Vector2(2 * dir, 7)])
			draw_colored_polygon(pts, c)
			draw_circle(Vector2(3 * dir, 0), 4.0, Color.WHITE)
	if breaker:
		draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 12, Color("e34f5b", 0.8), 1.0)
