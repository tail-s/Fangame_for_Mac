extends "res://scripts/enemies/enemy.gd"
## Crawler drone: patrols a platform and turns at walls and ledges.

@export var speed := 30.0

var dir := -1
var _t := 0.0


func _init() -> void:
	copy_kind = "mini"


func _physics_process(delta: float) -> void:
	_t += delta
	_tick_flash(delta)
	if _tick_frozen(delta):
		return
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
	var w := flash > 0.0
	var f := float(dir)
	var leg_c := Color.WHITE if w else Color("3b4a72")
	var joint_c := Color.WHITE if w else Color("5d6f9c")
	# Three jointed legs (side view), alternating steps.
	for i in 3:
		var hip := Vector2((-5.0 + i * 5.0) * f, -5.0)
		var step := sin(_t * 12.0 + i * 2.1)
		var knee := hip + Vector2((1.5 + step * 1.2) * f, -1.5)
		var foot := Vector2(hip.x + (step * 2.0 - 0.5) * f, 0.0 - maxf(0.0, -step) * 1.5)
		draw_line(hip, knee, leg_c, 2.0)
		draw_line(knee, foot, leg_c, 2.0)
		draw_rect(Rect2(knee - Vector2(1, 1), Vector2(2, 2)), joint_c)
	# Domed shell: shadow band, base, highlight strip, segment seams.
	var base := Color.WHITE if w else Color("6a48b0")
	var shade := Color.WHITE if w else Color("452c84")
	var hi := Color.WHITE if w else Color("9a7ce0")
	var seam := Color.WHITE if w else Color("33205f")
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -3), Vector2(9, -3), Vector2(8, -6), Vector2(-8, -6)]), shade)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -6), Vector2(8, -6), Vector2(6, -11), Vector2(2, -12),
			Vector2(-3, -12), Vector2(-7, -10)]), base)
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -11), Vector2(2, -11.5), Vector2(5, -10), Vector2(-4, -10)]), hi)
	for sx in [-3.0, 2.0]:
		draw_line(Vector2(sx, -11), Vector2(sx - 0.5, -6), seam, 1.0)
	# Sensor head at the front with a red eye and glint.
	var head := Color.WHITE if w else Color("2c365a")
	draw_colored_polygon(PackedVector2Array([Vector2(6 * f, -4), Vector2(10 * f, -4), Vector2(10 * f, -8),
			Vector2(7 * f, -9)]), head)
	draw_rect(Rect2(Vector2(minf(8 * f, 10 * f), -7.5), Vector2(2, 2)), Color.WHITE if w else Color("e34f5b"))
	draw_rect(Rect2(Vector2(9 * f if f > 0 else -9.5, -7.5), Vector2(1, 1)), Color("ffd9dc"))
	_draw_frozen()
