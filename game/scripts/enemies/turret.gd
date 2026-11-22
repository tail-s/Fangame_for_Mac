extends "res://scripts/enemies/enemy.gd"
## Dome turret: tracks the player within range and fires aimed shots.

const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")

@export var fire_interval := 1.8
@export var sight := 170.0
@export var shot_speed := 110.0

var aim := Vector2.LEFT
var cooldown := 1.0


func _init() -> void:
	max_hp = 4
	copy_kind = "turret"


func _physics_process(delta: float) -> void:
	_tick_flash(delta)
	if _tick_frozen(delta):
		return
	_apply_gravity(delta)
	velocity.x = 0.0
	move_and_slide()
	queue_redraw()
	var p = find_player()
	if p == null:
		return
	var muzzle := global_position + Vector2(0, -9)
	var to: Vector2 = p.global_position + Vector2(0, -13) - muzzle
	if to.length() > sight:
		return
	var want := to.normalized()
	want.y = minf(want.y, 0.2)  # cannot aim far below the horizon
	aim = aim.slerp(want.normalized(), 0.12)
	cooldown -= delta
	if cooldown <= 0.0:
		cooldown = fire_interval
		var shot := EnemyShot.new()
		shot.velocity = aim * shot_speed
		shot.position = muzzle + aim * 9.0 - get_parent().global_position
		get_parent().add_child(shot)


func _draw() -> void:
	var w := flash > 0.0
	var steel := Color.WHITE if w else Color("2c3a62")
	var steel_hi := Color.WHITE if w else Color("4a5d8f")
	var bolt := Color.WHITE if w else Color("8ea4c8")
	# Bolted base with a lighter top strip.
	draw_colored_polygon(PackedVector2Array([Vector2(-9, 0), Vector2(9, 0), Vector2(7, -5), Vector2(-7, -5)]), steel)
	draw_rect(Rect2(-7, -5, 14, 1), steel_hi)
	for bx in [-6.0, 5.0]:
		draw_rect(Rect2(bx, -3, 1, 1), bolt)
	# Barrel along the aim, behind the dome; muzzle ring.
	var pivot := Vector2(0, -9)
	var tip := pivot + aim * 10.0
	draw_line(pivot, tip, Color.WHITE if w else Color("1c2a4a"), 4.0)
	draw_line(pivot + aim * 3.0, tip - aim * 1.0, Color.WHITE if w else Color("3a4f80"), 2.0)
	draw_circle(tip, 2.2, Color.WHITE if w else Color("101b36"))
	# Dome: shadowed lower half, base, highlight arc.
	var dome := Color.WHITE if w else Color("9fb8d6")
	var dome_dark := Color.WHITE if w else Color("6b84ad")
	draw_circle(Vector2(0, -7), 5.5, dome_dark)
	draw_colored_polygon(PackedVector2Array([Vector2(-5.5, -7), Vector2(-4.5, -10.5), Vector2(-1.5, -12.4),
			Vector2(2, -12.3), Vector2(4.8, -10), Vector2(5.5, -7.5), Vector2(2, -8.5), Vector2(-3, -8.2)]), dome)
	draw_line(Vector2(-3.5, -11), Vector2(0, -12), Color.WHITE if w else Color("d7edf3"), 1.0)
	# Sensor eye follows the aim.
	var eye := Vector2(0, -8) + aim * 2.5
	draw_circle(eye, 1.8, Color.WHITE if w else Color("e34f5b"))
	draw_rect(Rect2(eye + Vector2(-0.5, -1.2), Vector2(1, 1)), Color("ffd9dc"))
	_draw_frozen()
