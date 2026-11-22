extends "res://scripts/enemies/enemy.gd"
## Crawler drone: patrols a platform and turns at walls and ledges.

@export var speed := 30.0

var dir := -1
var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	_tick_flash(delta)
	_apply_gravity(delta)
	velocity.x = dir * speed
	move_and_slide()
	if is_on_wall() or (is_on_floor() and not _ground_ahead()):
		dir = -dir
	queue_redraw()


func _ground_ahead() -> bool:
	var from := global_position + Vector2(dir * 9.0, -2.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 10), Layers.WORLD)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _draw() -> void:
	var shell := Color.WHITE if flash > 0.0 else Color("6543a2")
	for i in 3:
		var lx := -6.0 + i * 6.0
		var step := sin(_t * 12.0 + i * 2.0) * 1.5
		draw_line(Vector2(lx, -4), Vector2(lx + step, 0), Color("2a3550"), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, -3), Vector2(8, -3), Vector2(6, -10), Vector2(-6, -10)]), shell)
	draw_rect(Rect2(-5, -10, 10, 1), shell.lightened(0.35))
	draw_rect(Rect2(dir * 4 - 1.5, -8, 3, 2), Color("e34f5b"))
