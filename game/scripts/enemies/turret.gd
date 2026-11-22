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


func _physics_process(delta: float) -> void:
	_tick_flash(delta)
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
	var dome := Color.WHITE if flash > 0.0 else Color("9fb8d6")
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 0), Vector2(8, 0), Vector2(6, -5), Vector2(-6, -5)]), Color("2a3550"))
	draw_circle(Vector2(0, -7), 5.0, dome)
	draw_line(Vector2(0, -9), Vector2(0, -9) + aim * 9.0, Color("1c375b"), 3.0)
	draw_circle(Vector2(0, -8) + aim * 2.0, 1.5, Color("e34f5b"))
