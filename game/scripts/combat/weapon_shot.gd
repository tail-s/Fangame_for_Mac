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
		e.tint = INFO[kind].color
		e.position = position
		get_parent().add_child.call_deferred(e)
	queue_free()


# --- drawing ----------------------------------------------------------------------
# Each weapon keeps its INFO colour as its identity; shading is lit from the upper
# left, whole pixels only. Fixed shapes are cached sprites (PixelArt), authored
# facing right and mirrored by `dir`.

const PixelArt = preload("res://scripts/fx/pixel_art.gd")
const C_CYAN := Color("3de0ee")
const C_PINK := Color("ff8fc8")
const C_VOID := Color("0b1024")
const C_SPARK := Color("f0b84a")
const FLAME := [Color("a83a2a"), Color("ef9352"), Color("f0b84a"), Color("fff1c4")]
const ICE := [Color("2f5f99"), Color("4a8fc4"), Color("92dafa"), Color("e6fbff")]
const DRILL := [Color("3f6a2c"), Color("6f9a4c"), Color("9fc274"), Color("d8f0b0")]
const STEEL := [Color("3f5c7a"), Color("8aa7bd"), Color("d3e3ec")]


func _draw() -> void:
	var c: Color = INFO[kind].color
	match kind:
		"refraction_beam":
			_draw_prism(c)
		"gravity_wing":
			_draw_gravity(c)
		"heat_mirage":
			_draw_heat()
		"freeze_lance":
			_draw_mirrored(PixelArt.cached("freeze_lance", func() -> Image: return _lance_image()), Vector2(11, 3))
			for i in 3:
				var k := fmod(_t * 6.0 + i * 0.37, 1.0)
				var p := Vector2(-dir * (11.0 + k * 8.0), roundf(sin(i * 2.3 + _t * 20.0) * 2.0))
				draw_rect(Rect2(p.round(), Vector2.ONE), Color(ICE[3], 0.9 * (1.0 - k)))
		"core_drill":
			var f := int(_t * 30.0) % 4
			_draw_mirrored(PixelArt.cached("core_drill%d" % f, func() -> Image: return _drill_image(f)), Vector2(6, 5))
			if f == 0:
				var tip := Vector2(dir * 9.0, 0)
				draw_rect(Rect2(tip + Vector2(0, -2), Vector2.ONE), C_SPARK)
				draw_rect(Rect2(tip + Vector2(dir, 2), Vector2.ONE), Color.WHITE)
		"plasma":
			_draw_plasma(c)
		"pulse_ring":
			_draw_pulse(c)


func _draw_mirrored(tex: Texture2D, anchor: Vector2) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
	draw_texture(tex, -anchor)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Refraction beam: faceted gem trailing a purple streak split into cyan / pink fringes.
func _draw_prism(c: Color) -> void:
	var back := -velocity.normalized()
	var side := Vector2(-back.y, back.x)
	for i in range(3, 13):
		var a := 1.0 - (i - 3) / 10.0
		draw_rect(Rect2((back * i).round(), Vector2.ONE), Color(c, 0.9 * a))
		if i % 2 == 0 and i < 11:
			draw_rect(Rect2((back * i + side * 1.6).round(), Vector2.ONE), Color(C_CYAN, 0.75 * a))
			draw_rect(Rect2((back * (i + 1) - side * 1.6).round(), Vector2.ONE), Color(C_PINK, 0.75 * a))
	var tex := PixelArt.cached("refraction_gem", func() -> Image:
		var img := PixelArt.blank(9, 7)
		var tones := [Color("e8dcff"), c, Color("8a63d2"), Color("553894")]
		for y in 7:
			for x in 9:
				var d := Vector2(x + 0.5, y + 0.5) - Vector2(4.5, 3.5)
				if absf(d.x) / 4.7 + absf(d.y) / 3.7 > 1.0:
					continue
				var q := (0 if d.x < 0.0 else 1) if d.y < 0.0 else (2 if d.x < 0.0 else 3)
				img.set_pixel(x, y, tones[q])
		img.set_pixel(4, 3, Color.WHITE)
		img.set_pixel(3, 2, Color.WHITE)
		return img)
	draw_texture(tex, Vector2(-4, -3))


## Gravity wing: a dark singularity with a lit accretion rim, three turning wing
## arcs and motes spiralling in.
func _draw_gravity(c: Color) -> void:
	for i in 5:
		var r := 15.0 - fmod(_t * 26.0 + i * 3.1, 11.0)
		var p := (Vector2.from_angle(-_t * 5.0 + i * 1.9 + r * 0.25) * r).round()
		draw_rect(Rect2(p, Vector2.ONE), Color(c.lightened(0.45), 0.95) if r < 9.0 else Color(c, 0.6))
	for i in 3:
		var a0 := _t * 8.0 + i * TAU / 3.0
		_arc_px(a0 - 0.2, 1.0, 7.5, c.darkened(0.35))
		_arc_px(a0, 1.2, 8.5, c)
		_arc_px(a0 + 0.3, 0.9, 9.5, c.lightened(0.45))
	PixelArt.ring(self, Vector2.ZERO, 4.0, 6.0, c.lightened(0.25), c.darkened(0.4))
	PixelArt.disc(self, Vector2.ZERO, 4.0, C_VOID)
	draw_rect(Rect2(-3, -3, 2, 1), c.lightened(0.55))
	if int(_t * 12.0) % 2 == 0:
		draw_rect(Rect2(-1, -1, 2, 2), Color(c.lightened(0.5), 0.9))


func _arc_px(start: float, span: float, r: float, col: Color) -> void:
	var steps := int(ceil(span * r * 1.4))
	for s in steps + 1:
		var p := (Vector2.from_angle(start + span * s / steps) * r).round()
		draw_rect(Rect2(p, Vector2.ONE), col)


## Heat mirage: three swaying flame tongues (dark rim, orange, yellow, white-hot
## base), a ground glow and rising heat motes.
func _draw_heat() -> void:
	draw_rect(Rect2(-7, -2, 14, 1), Color(FLAME[1], 0.85))
	draw_rect(Rect2(-6, -1, 12, 1), Color(FLAME[0], 0.6))
	for i in 3:
		var h := roundf(10.0 + 6.0 * sin(_t * 30.0 + i * 2.0))
		_flame((i - 1) * 4.0, h, i)
	for i in 3:
		var k := fmod(_t * 3.0 + i * 0.33, 1.0)
		var p := Vector2(roundf(sin(_t * 9.0 + i * 2.0) * 4.0), roundf(-6.0 - k * 14.0))
		draw_rect(Rect2(p, Vector2.ONE), Color(FLAME[2], 0.8 * (1.0 - k)))


func _flame(x: float, h: float, i: int) -> void:
	for r in int(h):
		var t := r / h
		var cx := x + roundf(sin(_t * 26.0 + r * 0.6 + i * 1.7) * t * 1.4)
		var half := 3.2 * (1.0 - t) + 0.5
		var y := -3.0 - r
		for layer in 4:
			var hw := half - layer * 0.9
			if hw < 0.4 or (layer == 2 and t > 0.6) or (layer == 3 and t > 0.3):
				break
			var l := roundf(cx - hw)
			var w := maxf(roundf(cx + hw) - l, 1.0)
			# Tips burn orange; the dark rim only hugs the body of the tongue.
			var col: Color = FLAME[1] if layer == 0 and t > 0.72 else FLAME[layer]
			draw_rect(Rect2(l, y, w, 1), col)


## Plasma: translucent orb with a hot core and crackling arcs re-rolled every frame pair.
func _draw_plasma(c: Color) -> void:
	var r := roundf(9.0 + sin(_t * 30.0) * 2.0)
	PixelArt.disc(self, Vector2.ZERO, r, Color(c, 0.28))
	PixelArt.ring(self, Vector2.ZERO, r - 1.0, r, Color(c.lightened(0.35), 0.6))
	PixelArt.disc(self, Vector2.ZERO, 5.0, Color(c, 0.9))
	PixelArt.disc(self, Vector2(-1, -1), 3.0, c.lightened(0.6))
	draw_rect(Rect2(-2, -2, 2, 2), Color.WHITE)
	var roll := int(_t * 15.0)
	for i in 3:
		var a := _rand01(roll * 7 + i) * TAU
		var p := Vector2.from_angle(a) * 3.0
		for s in 3:
			var q := p + Vector2.from_angle(a + (_rand01(roll * 13 + i * 5 + s) - 0.5) * 1.8) * 3.0
			PixelArt.line(self, p, q, C_SPARK if s < 2 else Color.WHITE)
			p = q


## Pulse ring: dark rim, bright band shaded lower-right, a light inner edge,
## a faint inner ripple and sparks riding the ring.
func _draw_pulse(c: Color) -> void:
	var r := roundf(radius)
	PixelArt.ring(self, Vector2.ZERO, r * 0.8 - 0.5, r * 0.8 + 0.5, Color(c, 0.35))
	PixelArt.ring(self, Vector2.ZERO, r + 0.5, r + 1.5, Color(c.darkened(0.5), 0.9))
	PixelArt.ring(self, Vector2.ZERO, r - 1.5, r + 0.5, c, c.darkened(0.18))
	PixelArt.ring(self, Vector2.ZERO, r - 2.5, r - 1.5, Color(c.lightened(0.6), 0.85))
	for i in 6:
		var p := (Vector2.from_angle(i * TAU / 6.0 + _t * 5.0) * (r - 0.5)).round()
		draw_rect(Rect2(p - Vector2(1, 0), Vector2(3, 1)), Color.WHITE)
		draw_rect(Rect2(p - Vector2(0, 1), Vector2(1, 3)), Color.WHITE)


## Deterministic 0..1 noise (visual only; never touches the global RNG).
static func _rand01(n: int) -> float:
	return float(posmod(hash(n), 1000)) / 1000.0


## Freeze lance: crystal head, shaft lit on top, frost fins at the back (22x7).
static func _lance_image() -> Image:
	var img := PixelArt.blank(22, 7)
	for x in range(3, 14):
		img.set_pixel(x, 2, ICE[3] if x % 4 == 1 else ICE[2])
		img.set_pixel(x, 3, ICE[2] if x % 4 != 3 else ICE[3])
		img.set_pixel(x, 4, ICE[1])
	for x in range(12, 22):
		var hh := clampi(int(roundf((21 - x) * 0.42)), 0, 3)
		for y in range(3 - hh, 4 + hh):
			var col: Color = ICE[2]
			if y == 3 - hh:
				col = ICE[3]
			elif y > 3:
				col = ICE[1] if y < 3 + hh else ICE[0]
			img.set_pixel(x, y, col)
	img.set_pixel(13, 2, Color.WHITE)
	img.set_pixel(16, 3, Color.WHITE)
	for p in [Vector2i(2, 1), Vector2i(1, 1), Vector2i(0, 0)]:
		img.set_pixel(p.x, p.y, ICE[3])
	for p in [Vector2i(2, 5), Vector2i(1, 5), Vector2i(0, 6)]:
		img.set_pixel(p.x, p.y, ICE[1])
	img.set_pixel(2, 3, ICE[2])
	img.set_pixel(1, 3, ICE[1])
	return img


## Core drill: steel collar and a green cone whose helical flutes scroll with `phase`.
static func _drill_image(phase: int) -> Image:
	var img := PixelArt.blank(15, 11)
	for y in range(1, 10):
		img.set_pixel(0, y, STEEL[1])
		img.set_pixel(1, y, STEEL[2] if y < 5 else STEEL[1])
		img.set_pixel(2, y, STEEL[0])
	img.set_pixel(1, 1, Color.WHITE)
	for x in range(3, 15):
		var hh := 4.6 * (1.0 - (x - 3) / 12.0)
		for y in range(int(roundf(5.0 - hh)), int(roundf(5.0 + hh)) + 1):
			var col: Color = DRILL[2] if y < 5 else DRILL[1]
			var m := posmod(x + y - phase, 4)
			if m == 0:
				col = DRILL[0]
			elif m == 1:
				col = DRILL[3] if y < 6 else DRILL[2]
			img.set_pixel(x, y, col)
	img.set_pixel(14, 5, Color.WHITE)
	return img
