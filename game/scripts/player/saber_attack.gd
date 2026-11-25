extends RefCounted
## SABLE's saber (original character in the GDD's saber role, §6).
## Ground 3-hit combo, air slash, dash lunge, wall slash, and a parry (special)
## that turns a blocked hit into a counter slash. Slashes also cut enemy shots.
## Styles (weapon prev / next):
##   0 섬광류 flash   — fast swings, two air slashes per jump
##   1 파쇄류 crush   — slow heavy swings, the 3rd hit breaks cracked walls
##   2 반격류 counter — long parry window, strong counter

const Autoloads = preload("res://scripts/core/autoloads.gd")

const Layers = preload("res://scripts/core/layers.gd")
const Explosion = preload("res://scripts/fx/explosion.gd")
const ArmorFx = preload("res://scripts/fx/armor_fx.gd")

enum Swing { NONE, COMBO1, COMBO2, COMBO3, AIR, DASH, WALL, COUNTER }

const STYLE_NAMES := ["섬광류", "파쇄류", "반격류"]
const STYLE_SPEED := [0.8, 1.25, 1.0]
const COMBO_DAMAGE := [[1, 1, 2], [2, 2, 3], [1, 1, 2]]
const PARRY_WINDOW := [0.18, 0.18, 0.35]
const BASE_LEN := {
	Swing.COMBO1: 0.22, Swing.COMBO2: 0.22, Swing.COMBO3: 0.32, Swing.AIR: 0.28,
	Swing.DASH: 0.26, Swing.WALL: 0.24, Swing.COUNTER: 0.3,
}
## [hitbox size, offset in facing-right space]
const BOX := {
	Swing.COMBO1: [Vector2(24, 18), Vector2(16, -14)],
	Swing.COMBO2: [Vector2(24, 18), Vector2(16, -14)],
	Swing.COMBO3: [Vector2(30, 24), Vector2(18, -15)],
	Swing.AIR: [Vector2(34, 34), Vector2(2, -14)],
	Swing.DASH: [Vector2(28, 16), Vector2(18, -12)],
	Swing.WALL: [Vector2(24, 18), Vector2(16, -16)],
	Swing.COUNTER: [Vector2(40, 26), Vector2(16, -14)],
}

var p
var style := 0
var swing := Swing.NONE
var swing_t := 0.0
var swing_len := 0.0
var parry_t := 0.0
var queued := false
var air_used := 0
var hitbox: Area2D

var _box: RectangleShape2D
var _parry_cd := 0.0
var _hits := {}


func _init(player) -> void:
	p = player
	hitbox = Area2D.new()
	hitbox.collision_layer = Layers.PLAYER_SHOT
	hitbox.collision_mask = Layers.ENEMY | Layers.ENEMY_SHOT | Layers.WORLD
	var cs := CollisionShape2D.new()
	_box = RectangleShape2D.new()
	_box.size = Vector2(2, 2)
	cs.shape = _box
	hitbox.add_child(cs)
	p.add_child(hitbox)


func status_text() -> String:
	return "SABER · %s" % STYLE_NAMES[style]


func cycle(step: int) -> void:
	style = (style + step + 3) % 3
	p.notice.emit("검술: %s" % STYLE_NAMES[style])


func locks_movement() -> bool:
	return swing in [Swing.COMBO1, Swing.COMBO2, Swing.COMBO3, Swing.COUNTER] and p.is_on_floor()


func deactivate() -> void:
	swing = Swing.NONE
	parry_t = 0.0
	queued = false


func on_copy_kill(_kind) -> void:
	pass


## Called by the player when a hit is about to land. Returns true if parried.
func try_parry() -> bool:
	if parry_t <= 0.0:
		return false
	parry_t = 0.0
	_start(Swing.COUNTER)
	p.invuln_timer = maxf(p.invuln_timer, 0.4)
	Autoloads.sfx("parry")
	p.notice.emit("PARRY!")
	return true


func update(delta: float) -> void:
	parry_t = maxf(parry_t - delta, 0.0)
	_parry_cd = maxf(_parry_cd - delta, 0.0)
	if p.is_on_floor() or p.is_wall_sliding():
		air_used = 0
	if p.special_pressed and _parry_cd <= 0.0 and swing == Swing.NONE:
		parry_t = PARRY_WINDOW[style]
		_parry_cd = 0.5
	if swing != Swing.NONE:
		swing_t += delta
		var k := swing_t / swing_len
		if k >= 0.2 and k <= 0.75:
			_apply_hits()
		if p.shoot_pressed and swing in [Swing.COMBO1, Swing.COMBO2]:
			queued = true
		if swing_t >= swing_len:
			var next := Swing.NONE
			if queued and swing in [Swing.COMBO1, Swing.COMBO2] and p.is_on_floor():
				next = swing + 1
			swing = Swing.NONE
			if next != Swing.NONE:
				_start(next)
	elif p.shoot_pressed:
		if p.is_wall_sliding():
			_start(Swing.WALL)
		elif not p.is_on_floor():
			if air_used < (2 if style == 0 else 1):
				_start(Swing.AIR)
		elif p.is_dashing():
			_start(Swing.DASH)
		else:
			_start(Swing.COMBO1)


func damage() -> int:
	match swing:
		Swing.COMBO1, Swing.COMBO2, Swing.COMBO3:
			return COMBO_DAMAGE[style][swing - 1]
		Swing.AIR:
			return 1 if style == 0 else 2
		Swing.COUNTER:
			return 4 if style == 2 else 3
	return 2


func _start(s: int) -> void:
	Autoloads.sfx("saber_heavy" if s in [Swing.COMBO3, Swing.COUNTER, Swing.DASH] else "saber")
	swing = s
	swing_t = 0.0
	queued = false
	_hits.clear()
	if s == Swing.AIR:
		air_used += 1
	swing_len = BASE_LEN[s] * STYLE_SPEED[style]
	var box: Array = BOX[s]
	_box.size = box[0]
	var f: int = p.visual_facing()
	hitbox.position = Vector2(box[1].x * f, box[1].y)
	p.shoot_pose_timer = swing_len


func _apply_hits() -> void:
	for b in hitbox.get_overlapping_bodies():
		if _hits.has(b):
			continue
		if b.is_in_group("enemy"):
			_hits[b] = true
			b.take_damage(damage(), "saber")
			p.register_hit()
			_spark(ArmorFx.saber(style)[1], 7.0)
			if style == 1:
				_spark(ArmorFx.saber(style)[2], 5.0, Vector2(0, -6))
		elif b.is_in_group("breakable") and style == 1 and swing == Swing.COMBO3:
			_hits[b] = true
			b.break_wall()
	for a in hitbox.get_overlapping_areas():
		if a.is_in_group("enemy_shot"):
			var fresh: bool = not a.is_queued_for_deletion()
			a.hit()
			if fresh:
				_spark(Color.WHITE, 5.0, a.global_position - hitbox.global_position)


## Hit spark in the sword style's colour at the slash (visual only).
func _spark(tint: Color, size: float, offset := Vector2.ZERO) -> void:
	var host: Node = p.get_parent()
	if host == null:
		return
	var fx := Explosion.new()
	fx.size = size
	fx.duration = 0.18
	fx.tint = tint
	host.add_child(fx)
	fx.global_position = hitbox.global_position + offset
