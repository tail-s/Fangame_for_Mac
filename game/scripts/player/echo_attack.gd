extends RefCounted
## ECHO's kit (original character in the GDD's copy-gunner role, §6).
## Hold shoot: rapid fire in 8 directions (up / down aims). Special: fire a copy
## round; an enemy destroyed by it leaves copy data, and the next special press
## turns ECHO into that form for a while:
##   mini   (from walkers) — small body that fits 1-tile gaps, no shooting
##   turret (from turrets) — 3-way rapid fire

const PlayerShot = preload("res://scripts/combat/player_shot.gd")

const COPY_NAMES := {"mini": "소형체", "turret": "터렛 사격"}
const FORM_TIME := 8.0
const MAX_SHOTS := 6

var p
var copy := ""
var form := ""
var form_t := 0.0
var _fire_cd := 0.0
var _copy_cd := 0.0


func _init(player) -> void:
	p = player


func status_text() -> String:
	if form != "":
		return "%s  %.0fs" % [COPY_NAMES[form], form_t]
	if copy != "":
		return "COPY: %s (V 변신)" % COPY_NAMES[copy]
	return "PISTOLS · V 복제탄"


func cycle(_step: int) -> void:
	pass


func locks_movement() -> bool:
	return false


func try_parry() -> bool:
	return false


func deactivate() -> void:
	if form == "turret":
		form = ""


func on_copy_kill(kind: String) -> void:
	if COPY_NAMES.has(kind):
		copy = kind


func update(delta: float) -> void:
	_fire_cd -= delta
	_copy_cd -= delta
	if form != "":
		form_t -= delta
		if form_t <= 0.0 or p.special_pressed:
			_end_form()
	elif p.special_pressed:
		if copy != "":
			_begin_form(copy)
			copy = ""
		elif _copy_cd <= 0.0:
			_fire_copy_round()
	if form == "mini":
		return
	if p.in_shoot and _fire_cd <= 0.0:
		_fire()


func aim() -> Vector2:
	var f: int = p.visual_facing()
	if p.in_up:
		return Vector2(f, -1).normalized() if p.in_dir != 0 else Vector2(0, -1)
	if p.in_down and not p.is_on_floor():
		return Vector2(f, 1).normalized() if p.in_dir != 0 else Vector2(0, 1)
	return Vector2(f, 0)


func _fire() -> void:
	if p.get_tree().get_nodes_in_group("echo_shot").size() >= MAX_SHOTS:
		return
	var dir := aim()
	var spread := [-0.18, 0.0, 0.18] if form == "turret" else [0.0]
	for a in spread:
		var shot := PlayerShot.new()
		shot.setup_vector("echo", dir.rotated(a), p)
		shot.position = p.position + Vector2(0, -15) + dir * 11.0
		p.get_parent().add_child(shot)
	_fire_cd = 0.14 if form == "turret" else 0.09
	p.shoot_pose_timer = 0.2


func _fire_copy_round() -> void:
	var shot := PlayerShot.new()
	shot.setup_vector("copy", Vector2(p.visual_facing(), 0), p)
	shot.position = p.position + Vector2(11 * p.visual_facing(), -15)
	p.get_parent().add_child(shot)
	_copy_cd = 0.8
	p.shoot_pose_timer = 0.3


func _begin_form(kind: String) -> void:
	form = kind
	form_t = FORM_TIME
	if kind == "mini":
		p.set_mini(true)
	p.notice.emit("변신: %s" % COPY_NAMES[kind])


func _end_form() -> void:
	if form == "mini" and not p.set_mini(false):
		form_t = 0.3  # no room to stand up yet: retry shortly
		return
	form = ""
