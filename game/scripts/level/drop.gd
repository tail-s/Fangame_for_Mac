extends Area2D
## Small capsule dropped by enemies: "hp" heals 3, "energy" refills 6 weapon energy.

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")

var kind := "hp"
var life := 7.0
var _t := 0.0
var _vy := -80.0
var _landed := false


func _ready() -> void:
	collision_layer = Layers.TRIGGER
	collision_mask = Layers.PLAYER
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	cs.shape = rect
	cs.position = Vector2(0, -5)
	add_child(cs)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	if not _landed:
		_vy = minf(_vy + 600.0 * delta, 240.0)
		var step := Vector2(0, _vy * delta)
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, 1), Layers.WORLD)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or _vy < 0.0:
			global_position += step
		else:
			global_position = hit.position
			_landed = true
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or is_queued_for_deletion():
		return
	if kind == "hp":
		body.heal(3)
	else:
		body.add_weapon_energy(6.0)
	Autoloads.sfx("pickup")
	queue_free()


func _draw() -> void:
	if life - _t < 2.0 and int(_t * 12.0) % 2 == 0:
		return
	var c := Color("00b8be") if kind == "hp" else Color("f0b84a")
	draw_rect(Rect2(-4, -9, 8, 8), Color("2a3550"))
	draw_rect(Rect2(-3, -8, 6, 6), c)
	draw_rect(Rect2(-1, -7, 2, 4), Color.WHITE)
