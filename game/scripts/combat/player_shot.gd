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
const PixelArt = preload("res://scripts/fx/pixel_art.gd")

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
## Ultimate Armor full charge: stronger and leaves a lingering plasma orb.
var plasma := false
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
		_leave_plasma()
		queue_free()
	queue_redraw()


func _leave_plasma() -> void:
	if not plasma:
		return
	plasma = false
	var orb = load("res://scripts/combat/weapon_shot.gd").new()
	orb.setup("plasma", dir, source)
	orb.position = position
	get_parent().add_child.call_deferred(orb)


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
		var killed: bool = body.take_damage(damage + (1 if plasma else 0), kind)
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
	_leave_plasma()
	var fx := Explosion.new()
	fx.size = 5.0
	fx.duration = 0.15
	fx.tint = _spark_color()
	fx.position = position + Vector2(dir * 4, 0)
	get_parent().add_child(fx)
	queue_free()


## Hit-spark colour for the impact burst (visual only).
func _spark_color() -> Color:
	match kind:
		"echo":
			return GREEN[1]
		"copy":
			return VIOLET[1]
	return CYAN[1] if level == 1 else Color(0, 0, 0, 0)


# --- drawing ----------------------------------------------------------------------
# Pixel sprites built once (PixelArt cache), authored facing right and mirrored for
# dir < 0. Colour identity: tap shot amber, mid charge cyan, full charge flickers
# amber / cyan, ECHO rounds green, copy rounds purple / green, breaker ring red.

const AMBER := [Color("b4661c"), Color("f0b84a"), Color("ffe08a"), Color("fff6d8")]
const CYAN := [Color("17869a"), Color("3de0ee"), Color("a6f6fb"), Color("ffffff")]
const GREEN := [Color("2a8c60"), Color("5ad19a"), Color("b8f4d7"), Color("ffffff")]
const VIOLET := [Color("7a52c4"), Color("b78af3"), Color("e2d2ff"), Color("ffffff")]
const RED := [Color("9a2637"), Color("e34f5b"), Color("ff9f9b")]
const FULL_POLY := [Vector2(11, 0), Vector2(2, -7), Vector2(-11, -5), Vector2(-6, 0),
		Vector2(-11, 5), Vector2(2, 7)]


func _draw() -> void:
	if kind == "echo":
		_draw_echo()
		return
	if kind == "copy":
		_draw_copy()
		return
	var flick := int(_t * 30.0) % 2
	var key := "buster%d%s" % [level, "s" if small else ""]
	var tex: Texture2D
	match level:
		0:
			tex = PixelArt.cached(key, func() -> Image: return _tap_image(small))
		1:
			key += str(flick)
			tex = PixelArt.cached(key, func() -> Image: return _mid_image(small, flick))
		_:
			key += str(flick)
			tex = PixelArt.cached(key, func() -> Image: return _full_image(small, AMBER if flick == 0 else CYAN))
	var size := tex.get_size()
	# Anchor: the bright head sits on the shot's origin.
	var anchor := Vector2(size.x - roundf(size.y * 0.5) - 1.0, roundf(size.y * 0.5))
	if level == 2:
		anchor = (size * 0.5).floor()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(dir, 1))
	draw_texture(tex, -anchor)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if breaker:
		_draw_breaker_ring(5.0 if small else 7.0)


## Vanguard ARM breaker: a red ring with four bright teeth turning around the shot.
func _draw_breaker_ring(r: float) -> void:
	PixelArt.ring(self, Vector2.ZERO, r - 0.6, r + 0.5, Color(RED[1], 0.55))
	for i in 4:
		var p := (Vector2.from_angle(_t * 9.0 * dir + i * TAU / 4.0) * r).round()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), RED[0])
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(1, 1)), RED[2])


func _draw_echo() -> void:
	var tex := PixelArt.cached("echo_round", func() -> Image:
		var img := PixelArt.blank(5, 5)
		PixelArt.glow_ellipse(img, Vector2(2.5, 2.5), Vector2(2.6, 2.6), GREEN)
		return img)
	var back := -velocity.normalized()
	draw_rect(Rect2((back * 6.0).round(), Vector2(1, 1)), Color(GREEN[0], 0.6))
	draw_rect(Rect2((back * 4.0).round(), Vector2(1, 1)), Color(GREEN[1], 0.75))
	draw_texture(tex, Vector2(-2, -2))


func _draw_copy() -> void:
	var purple := int(_t * 20.0) % 2 == 0
	var tex := PixelArt.cached("copy_round%d" % int(purple), func() -> Image:
		var tones: Array = VIOLET if purple else GREEN
		var img := PixelArt.blank(11, 11)
		var c := Vector2(5.5, 5.5)
		for y in 11:
			for x in 11:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var l := d.length()
				if l > 5.6 or l < 3.2:
					continue
				var col: Color = tones[1]
				if l > 4.9 or d.x + d.y > 3.0:
					col = tones[0]
				elif d.x + d.y < -2.5:
					col = tones[2]
				img.set_pixel(x, y, col)
		# Data core: a white diamond with a lit edge.
		for p in [Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]:
			img.set_pixel(p.x, p.y, Color.WHITE)
		img.set_pixel(6, 6, tones[2])
		return img)
	draw_texture(tex, Vector2(-5, -5))
	var g := (Vector2.from_angle(_t * 14.0) * 4.5).round()
	draw_rect(Rect2(g, Vector2(1, 1)), Color.WHITE)


## Tap shot: amber pellet with a short glow trail.
static func _tap_image(is_small: bool) -> Image:
	var pal := {"a": AMBER[1], "d": AMBER[0], "y": AMBER[2], "w": AMBER[3], "t": Color(AMBER[2], 0.4),
			"u": Color(AMBER[1], 0.55)}
	if is_small:
		return PixelArt.from_rows([
			"...aaa.",
			"tuaywwa",
			"tuayywd",
			"...ddd.",
		], pal)
	return PixelArt.from_rows([
		"....aaaa..",
		"...aywwwa.",
		"ttaywwwwwa",
		"uuayywwwyd",
		"...dyyyyd.",
		"....dddd..",
	], pal)


## Mid charge: cyan orb with a flickering comet tail.
static func _mid_image(is_small: bool, phase: int) -> Image:
	var r := Vector2(3.5, 3.0) if is_small else Vector2(5.0, 4.0)
	var tail := 5 if is_small else 8
	var w := int(r.x * 2.0) + tail
	var h := int(r.y * 2.0)
	var img := PixelArt.blank(w, h)
	var mid := h / 2
	for x in tail + 2:
		var k := float(x + 1) / float(tail + 2)
		var half := 2 if k > 0.55 and not is_small else 1
		for y in range(mid - half, mid + half):
			if k < 0.45 and (x + y + phase) % 2 == 0:
				continue
			var col: Color = CYAN[0]
			if k > 0.7 and absf(y - mid + 0.5) < 1.0:
				col = CYAN[2]
			elif k > 0.4:
				col = CYAN[1]
			img.set_pixel(x, y, Color(col, 0.35 + 0.6 * k))
	PixelArt.glow_ellipse(img, Vector2(tail + r.x, r.y), r, CYAN)
	return img


## Full charge: swallow-tail plasma bolt in rim / mid / light bands around a white core.
static func _full_image(is_small: bool, tones: Array) -> Image:
	var k := 0.7 if is_small else 1.0
	var poly := PackedVector2Array()
	for p in FULL_POLY:
		poly.append(p * k)
	var w := int(ceil(22.0 * k)) + 2
	var h := int(ceil(14.0 * k)) + 2
	var img := PixelArt.blank(w, h)
	var c := (Vector2(w, h) * 0.5).floor()
	var core := Vector2(3.0, 0.0) * k
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) - c
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			var d := 99.0
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				d = minf(d, p.distance_to(q))
			var cd := p.distance_to(core)
			# Bands from the edge in; upper edges catch the light.
			var col: Color = tones[2]
			if cd < 3.0 * k:
				col = tones[3]
			elif cd < 4.4 * k:
				col = tones[2]
			elif d < 1.0:
				col = tones[0] if p.y > -2.0 * k else tones[1]
			elif d < 2.6 * k:
				col = tones[1] if p.y > -3.0 * k else tones[2]
			img.set_pixel(x, y, col)
	return img
