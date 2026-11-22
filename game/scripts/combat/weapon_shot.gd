extends Area2D
## IX special weapons (GDD v0.2 §5-1), one per boss. Behaviour by `kind`:
##   refraction_beam  fast prism bolt, bounces off walls twice
##   gravity_wing     slow gravity orb: pulls in and erases enemy shots, multi-hit
##   heat_mirage      heat wave running along the ground, pierces
##   freeze_lance     piercing lance that freezes enemies in place
##   core_drill       short-range drill: multi-hit, breaks cracked walls
##   pulse_ring       expanding ring around IX, erases enemy shots
## Weakness loop: each weapon hits the next boss hard (GDD §5-2).

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")

const ORDER := ["refraction_beam", "gravity_wing", "heat_mirage", "freeze_lance", "core_drill", "pulse_ring"]
const MAX_ENERGY := 28.0
const INFO := {
	"refraction_beam": {"name": "REFRACTION BEAM", "cost": 1.0, "max": 3, "color": Color("b78af3")},
	"gravity_wing": {"name": "GRAVITY WING", "cost": 3.0, "max": 1, "color": Color("8397f1")},
	"heat_mirage": {"name": "HEAT MIRAGE", "cost": 2.0, "max": 2, "color": Color("ef9352")},
	"freeze_lance": {"name": "FREEZE LANCE", "cost": 2.0, "max": 2, "color": Color("92dafa")},
	"core_drill": {"name": "CORE DRILL", "cost": 2.0, "max": 2, "color": Color("9fc274")},
	"pulse_ring": {"name": "PULSE RING", "cost": 4.0, "max": 1, "color": Color("efcf5f")},
	# Not selectable: left behind by Ultimate Armor IX full-charge shots.
	"plasma": {"name": "PLASMA", "cost": 0.0, "max": 99, "color": Color("b78af3")},
}

var kind := ""
var dir := 1
var velocity := Vector2.ZERO
var damage := 2
var life := 1.2
var bounces := 2
var radius := 4.0
var source = null
var _t := 0.0
var _last_hit := {}
var _shape: CollisionShape2D
var _done := false


func setup(k: String, d: int, src) -> void:
	kind = k
	dir = d
	source = src
	match kind:
		"refraction_beam":
			velocity = Vector2(380.0 * d, 0)
			damage = 2
		"gravity_wing":
			velocity = Vector2(80.0 * d, 0)
			damage = 1
			life = 2.2
		"heat_mirage":
			velocity = Vector2(210.0 * d, 0)
			damage = 2
			life = 0.8
		"freeze_lance":
			velocity = Vector2(320.0 * d, 0)
			damage = 2
		"core_drill":
			velocity = Vector2(150.0 * d, 0)
			damage = 1
			life = 0.8
		"pulse_ring":
			damage = 3
			life = 0.4
		"plasma":
			damage = 1
			life = 1.0


func _ready() -> void:
	add_to_group("weapon_shot")
	add_to_group("weapon_" + kind)
	collision_layer = Layers.PLAYER_SHOT
	collision_mask = Layers.ENEMY | Layers.ENEMY_SHOT
	if kind in ["heat_mirage", "freeze_lance", "core_drill"]:
		collision_mask |= Layers.WORLD
	_shape = CollisionShape2D.new()
	match kind:
		"pulse_ring", "gravity_wing", "plasma":
			var circle := CircleShape2D.new()
			circle.radius = {"pulse_ring": 4.0, "gravity_wing": 10.0, "plasma": 12.0}[kind]
			_shape.shape = circle
		_:
			var rect := RectangleShape2D.new()
			match kind:
				"heat_mirage":
					rect.size = Vector2(12, 18)
					_shape.position = Vector2(0, -11)
				"freeze_lance":
					rect.size = Vector2(20, 6)
				"core_drill":
					rect.size = Vector2(12, 10)
				_:
					rect.size = Vector2(8, 6)
			_shape.shape = rect
	add_child(_shape)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life:
		_finish(false)
		return
	match kind:
		"refraction_beam":
			_move_bouncing(delta)
		"pulse_ring":
			if source != null and is_instance_valid(source):
				global_position = source.global_position + Vector2(0, -14)
			radius = lerpf(4.0, 60.0, minf(_t / 0.3, 1.0))
			_shape.shape.radius = radius
		"gravity_wing":
			position += velocity * delta
			_pull_shots(delta)
		_:
			position += velocity * delta
	if not _done:
		_apply_hits()
	queue_redraw()


func _move_bouncing(delta: float) -> void:
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, Layers.WORLD)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		return
	bounces -= 1
	if bounces < 0:
		_finish(true)
		return
	global_position = hit.position + hit.normal * 2.0
	velocity = velocity.bounce(hit.normal)


func _pull_shots(delta: float) -> void:
	for s in get_tree().get_nodes_in_group("enemy_shot"):
		var off: Vector2 = global_position - s.global_position
		if off.length() < 8.0:
			s.hit()
		elif off.length() < 64.0:
			s.global_position += off.normalized() * 160.0 * delta


func _apply_hits() -> void:
	var interval := 0.12 if kind in ["core_drill", "gravity_wing", "plasma"] else 999.0
	for b in get_overlapping_bodies():
		if b.is_in_group("enemy"):
			if _last_hit.has(b) and _t - _last_hit[b] < interval:
				continue
			_last_hit[b] = _t
			var killed: bool = b.take_damage(damage, kind)
			if source != null and is_instance_valid(source):
				source.register_hit()
			if kind == "freeze_lance" and not killed and b.has_method("freeze"):
				b.freeze(2.5)
			if kind == "refraction_beam":
				_finish(true)
				return
		elif b.is_in_group("breakable"):
			if kind == "core_drill":
				b.break_wall()
			_finish(true)
			return
		elif kind in ["heat_mirage", "freeze_lance", "core_drill"]:
			_finish(true)
			return
	if kind == "pulse_ring":
		for a in get_overlapping_areas():
			if a.is_in_group("enemy_shot"):
				a.hit()


func _finish(fx: bool) -> void:
	if _done:
		return
	_done = true
	if fx:
		var e := Explosion.new()
		e.size = 6.0
		e.duration = 0.18
		e.position = position
		get_parent().add_child.call_deferred(e)
	queue_free()


func _draw() -> void:
	var c: Color = INFO[kind].color
	var flick := int(_t * 30.0) % 2 == 0
	match kind:
		"refraction_beam":
			var back := -velocity.normalized() * 10.0
			draw_line(Vector2.ZERO, back, Color(c, 0.5), 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -4), Vector2(4, 0), Vector2(0, 4), Vector2(-4, 0)]), c)
			draw_circle(Vector2.ZERO, 1.5, Color.WHITE)
		"gravity_wing":
			draw_circle(Vector2.ZERO, 7.0, Color("101b36"))
			for i in 3:
				var a := _t * 8.0 + i * TAU / 3.0
				draw_arc(Vector2.ZERO, 10.0, a, a + 1.2, 6, c, 2.0)
			draw_circle(Vector2.ZERO, 2.5, Color.WHITE)
		"heat_mirage":
			for i in 3:
				var h := 10.0 + 6.0 * sin(_t * 30.0 + i * 2.0)
				var x := (i - 1) * 4.0
				draw_colored_polygon(PackedVector2Array([Vector2(x - 3, -2), Vector2(x, -2 - h),
						Vector2(x + 3, -2)]), Color("f0b84a") if (i + int(_t * 20.0)) % 2 == 0 else c)
		"freeze_lance":
			draw_colored_polygon(PackedVector2Array([Vector2(11 * dir, 0), Vector2(-3 * dir, -3),
					Vector2(-10 * dir, 0), Vector2(-3 * dir, 3)]), c)
			draw_line(Vector2(-8 * dir, 0), Vector2(9 * dir, 0), Color.WHITE, 1.0)
		"core_drill":
			draw_colored_polygon(PackedVector2Array([Vector2(8 * dir, 0), Vector2(-5 * dir, -5),
					Vector2(-5 * dir, 5)]), c)
			for i in 3:
				var x := (-3.0 + i * 3.0 + (2.0 if flick else 0.0)) * dir
				draw_line(Vector2(x, -4 + i), Vector2(x, 4 - i), Color("2a3550"), 1.0)
		"plasma":
			var r := 9.0 + sin(_t * 30.0) * 2.0
			draw_circle(Vector2.ZERO, r, Color(c, 0.35))
			draw_arc(Vector2.ZERO, r + 2.0, _t * 9.0, _t * 9.0 + 4.0, 12, Color("f0b84a"), 1.0)
			draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
		"pulse_ring":
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, c, 3.0)
			draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, 32, Color(c, 0.4), 1.0)
