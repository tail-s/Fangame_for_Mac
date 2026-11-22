extends Node2D
## Pixel-art character visual built from the baked sprite sheets in
## res://art/characters/<character>/ (see tools/bake_characters.gd).
## Layers are stacked back to front. For IX each layer's row follows the armor
## part in its slot, so all 81 part combinations change shape as well as colour.
## The near arm is swapped for a weapon-arm sprite at the frame's shoulder anchor:
##   IX     buster while shooting / charging
##   SABLE  arm + saber while swinging (16 angles, follows the swing)
##   ECHO   arm + pistol along the aim direction (16 angles); crawler sprite in mini form
##
## `player` can be the real player or a preview puppet with the same fields.

const ART := "res://art/characters/"
const FLASH := preload("res://scripts/player/sprite_flash.gdshader")
const C_LV1 := Color("3de0ee")
const C_LV2 := Color("f0b84a")
const C_MINT := Color("71dedf")
const C_SABLE := Color("f08a3a")
const C_ECHO := Color("b78af3")
const C_BLADE := Color(0.85, 1.0, 1.0)
const ARM_SPRITES := ["buster", "saber", "pistol"]
## SaberAttack.Swing values.
const SW_NONE := 0
const SW_COMBO2 := 2
const SW_COMBO3 := 3
const SW_AIR := 4
const SW_DASH := 5

static var _sheets := {}

var player
var character := "ix"
var part_armor := {"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "neutral"}

var anim := ""
var frame := 0
var _anim_t := 0.0
var _sheet: Dictionary
var _rig: Node2D
var _layers := {}
var _arm: Sprite2D
var _arm_name := ""
var _arm_angle := 0.0
var _mini: Sprite2D
var _mat: ShaderMaterial
var _front: Node2D
var _f := 1
var _was_floor := true
var _land_t := 0.0


static func sheet(id: String) -> Dictionary:
	if _sheets.has(id):
		return _sheets[id]
	var dir := ART + id + "/"
	var meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "sheet.json"))
	var data := {"meta": meta, "tex": {}, "extras": {}}
	for layer in meta.layers:
		data.tex[layer] = load(dir + layer + ".png")
	for name in meta.extras:
		data.extras[name] = load(dir + name + ".png")
	_sheets[id] = data
	return data


func _ready() -> void:
	_sheet = sheet(character)
	_mat = ShaderMaterial.new()
	_mat.shader = FLASH
	_rig = Node2D.new()
	add_child(_rig)
	var meta: Dictionary = _sheet.meta
	var origin := Vector2(meta.origin[0], meta.origin[1])
	for layer in meta.layers:
		_layers[layer] = _sprite(_sheet.tex[layer], -origin)
	for name in ARM_SPRITES:
		if meta.extras.has(name):
			_arm_name = name
			_arm = _sprite(_sheet.extras[name], Vector2.ZERO)
			_arm.visible = false
	if meta.extras.has("mini"):
		var ex: Dictionary = meta.extras.mini
		_mini = _sprite(_sheet.extras.mini, -Vector2(ex.origin[0], ex.origin[1]))
		_mini.visible = false
	_front = Node2D.new()
	_front.draw.connect(_draw_front)
	add_child(_front)
	_play("idle")
	_apply()


func _sprite(tex: Texture2D, offset: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = offset
	s.region_enabled = true
	s.material = _mat
	_rig.add_child(s)
	return s


func _process(delta: float) -> void:
	var p = player
	if p == null:
		return
	_f = p.visual_facing()
	_rig.scale.x = _f
	_pick(p, delta)
	_apply()
	_tint(p)
	queue_redraw()
	_front.queue_redraw()


func _pick(p, delta: float) -> void:
	var on_floor: bool = p.is_on_floor()
	if on_floor and not _was_floor:
		_land_t = 0.1
	_was_floor = on_floor
	_land_t = maxf(_land_t - delta, 0.0)
	var next := "idle"
	var special: String = p.special_kind
	if p.is_hurt():
		next = "hurt"
	elif special in ["overdrive", "nova", "tag_strike"]:
		next = "rush"
	elif special == "skybreaker":
		next = "dive_rise" if p.special_phase == 0 else "dive"
	elif p.is_wall_sliding():
		next = "wall_slide"
	elif p.air_dashing:
		next = "air_dash"
	elif p.is_dashing():
		next = "dash"
	elif p.flying or _field(p, "hovering", false):
		next = "fly"
	elif p.gliding:
		next = "glide"
	elif not on_floor:
		var vy: float = p.velocity.y
		if _field(p, "wall_lock_timer", 0.0) > 0.0 and vy < 0.0:
			next = "wall_kick"
		elif vy < -90.0:
			next = "jump"
		elif vy < 70.0:
			next = "apex"
		else:
			next = "fall"
	elif absf(p.velocity.x) > 1.0:
		next = "run"
	elif _land_t > 0.0:
		next = "land"
	if next != anim:
		_play(next)
	else:
		_anim_t += delta


func _play(name: String) -> void:
	anim = name
	_anim_t = 0.0


func _apply() -> void:
	var meta: Dictionary = _sheet.meta
	var a: Dictionary = meta.anims[anim]
	var frames: Array = a.frames
	var i := int(_anim_t * float(a.fps))
	i = i % frames.size() if a.loop else mini(i, frames.size() - 1)
	frame = int(frames[i])
	var cw: int = meta.cell[0]
	var ch: int = meta.cell[1]
	var variants: Array = meta.variants
	var is_mini: bool = _mini != null and player != null and _field(player, "mini", false)
	var arm_index := _arm_index()
	for layer in meta.layers:
		var s: Sprite2D = _layers[layer]
		var row := 0
		if character == "ix":
			row = maxi(variants.find(part_armor.get(meta.layer_slot[layer], "neutral")), 0)
		s.region_rect = Rect2(frame * cw, row * ch, cw, ch)
		s.visible = not is_mini and not (arm_index >= 0 and layer == "near_arm")
	if _arm != null:
		_arm.visible = arm_index >= 0 and not is_mini
		if _arm.visible:
			var ex: Dictionary = meta.extras[_arm_name]
			var row := 0
			if character == "ix":
				row = maxi(variants.find(part_armor.get("arm", "neutral")), 0)
			_arm.region_rect = Rect2(arm_index * ex.cell[0], row * ex.cell[1], ex.cell[0], ex.cell[1])
			var sh: Array = meta.shoulder[frame]
			_arm.position = Vector2(sh[0], sh[1]) - Vector2(ex.origin[0], ex.origin[1])
	if _mini != null:
		_mini.visible = is_mini
		if is_mini:
			var ex: Dictionary = meta.extras.mini
			var step := int(_field(player, "anim_time", 0.0) * 10.0) % 2 if absf(player.velocity.x) > 1.0 else 0
			_mini.region_rect = Rect2(step * ex.cell[0], 0, ex.cell[0], ex.cell[1])


## Column of the weapon-arm sprite to show, or -1 to keep the animated near arm.
func _arm_index() -> int:
	var p = player
	if p == null or _arm == null or anim in ["rush", "dive_rise", "dive", "hurt"]:
		return -1
	match _arm_name:
		"buster":
			return 0 if (p.shoot_pose_timer > 0.0 or p.charge_level() > 0) else -1
		"saber":
			var atk = _field(p, "attack", null)
			if atk == null or atk.swing == SW_NONE:
				return -1
			_arm_angle = _swing_angle(atk)
		"pistol":
			var atk = _field(p, "attack", null)
			var aim: Vector2 = atk.aim() if atk != null else Vector2(_f, 0)
			_arm_angle = Vector2(aim.x * _f, aim.y).angle()
	var n: int = _sheet.meta.extras[_arm_name].angles.size()
	return posmod(int(round(_arm_angle / (TAU / n))), n)


## Blade angle in the facing-right frame (0 = forward, + = downwards).
func _swing_angle(atk) -> float:
	var k: float = clampf(atk.swing_t / maxf(atk.swing_len, 0.001), 0.0, 1.0)
	match int(atk.swing):
		SW_AIR:
			return -PI * 0.5 + k * TAU * 1.25
		SW_DASH:
			return 0.05
		SW_COMBO2:
			return lerpf(1.2, -1.9, k)
		SW_COMBO3:
			return lerpf(-2.6, 1.5, k)
	return lerpf(-2.1, 1.25, k)


func _tint(p) -> void:
	var frame_n := Engine.get_physics_frames()
	modulate.a = 0.35 if (p.invuln_timer > 0.0 and frame_n % 4 < 2) else 1.0
	var amount := 0.0
	var tint := Color.WHITE
	if p.is_hurt() and frame_n % 4 < 2:
		amount = 0.85
	elif (p.charge_level() == 2 or p.special_kind != "") and frame_n % 6 < 3:
		tint = C_LV2
		amount = 0.4
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("amount", amount)


func _shoulder() -> Vector2:
	var sh: Array = _sheet.meta.shoulder[frame]
	return Vector2(sh[0] * _f, sh[1])


## Muzzle of IX's buster (local, facing applied).
func muzzle() -> Vector2:
	var meta: Dictionary = _sheet.meta
	if not meta.extras.has("buster"):
		return Vector2(13 * _f, -15)
	var tip: Array = meta.extras.buster.tip
	return _shoulder() + Vector2(tip[0] * _f, tip[1])


static func _field(p, key: String, fallback):
	var v = p.get(key)
	return fallback if v == null else v


# --- effects (drawn unflipped, x mirrored by hand) ---------------------------------------

func _v(x: float, y: float) -> Vector2:
	return Vector2(x * _f, y)


## Behind the sprites: speed streaks, flames, dust, wall sparks.
func _draw() -> void:
	var p = player
	if p == null:
		return
	var t: float = p.anim_time
	var frame_n := Engine.get_physics_frames()
	var special: String = p.special_kind
	if p.air_dashing or special in ["overdrive", "nova", "tag_strike"]:
		var c := C_SABLE if character == "sable" else (C_ECHO if character == "echo" else C_LV1)
		for i in 4:
			var y := -26.0 + i * 6.0
			var x0 := -_f * (8.0 + (i % 2) * 4.0)
			draw_line(Vector2(x0, y), Vector2(x0 - _f * (10.0 + i * 2.0), y), Color(c, 0.55 - i * 0.1), 1.0)
	if special == "skybreaker" and p.special_phase == 1:
		draw_rect(Rect2(-5, -62, 10, 40), Color(C_MINT, 0.35))
	if p.flying or _field(p, "hovering", false):
		var fc := C_ECHO if character == "echo" else C_LV2
		for x in [-1.0, 3.0]:
			var flame := 4.0 + fmod(t * 50.0, 3.0)
			draw_colored_polygon(PackedVector2Array([_v(x - 2, 0), _v(x + 2, 0), _v(x, flame)]), fc)
	if p.is_dashing() and p.is_on_floor():
		for i in 3:
			var a := 0.5 - i * 0.15
			draw_circle(_v(-11 - i * 4, -2 - fmod(t * 20.0 + i, 3.0)), 1.6 - i * 0.3, Color(1, 1, 1, a))
	if p.is_wall_sliding() and frame_n % 6 < 3:
		draw_rect(Rect2(_v(-7, -4) - Vector2(1, 1), Vector2(2, 2)), C_LV2)


## In front of the sprites: charge aura, saber trails, parry, ECHO form marks.
func _draw_front() -> void:
	var p = player
	if p == null:
		return
	var t: float = p.anim_time
	var frame_n := Engine.get_physics_frames()
	var atk = _field(p, "attack", null)
	if character == "sable" and atk != null:
		if atk.swing != SW_NONE:
			_saber_trail(atk)
		if atk.parry_t > 0.0:
			var mid := 0.0 if _f > 0 else PI
			_front.draw_arc(_v(10, -16), 12.0, mid - 1.2, mid + 1.2, 12, Color(C_SABLE, 0.9), 2.0)
	if character == "echo" and atk != null and not _field(p, "mini", false):
		if atk.form == "turret":
			_front.draw_arc(_shoulder(), 13.0, 0.0, TAU, 16, Color(C_ECHO, 0.5), 1.0)
		elif atk.copy != "":
			_front.draw_circle(_v(-6, -33), 2.0, C_ECHO)
	var charge: int = p.charge_level()
	if charge <= 0:
		return
	var cc := C_LV2 if charge == 2 else C_LV1
	var center := Vector2(0, -16)
	for i in 6:
		var ang := t * 9.0 + i * TAU / 6.0
		var r := 14.0 + sin(t * 30.0 + i) * 2.0
		var at := center + Vector2(cos(ang), sin(ang) * 1.2) * r
		_front.draw_line(at, at + Vector2(cos(ang), sin(ang)) * 3.0, cc, 1.0)
	if charge == 2 and frame_n % 4 < 2:
		_front.draw_arc(center, 17.0, 0.0, TAU, 20, cc, 1.0)
	_front.draw_circle(muzzle(), 1.5 + (frame_n % 3) * 0.5, cc)


## Arc trailing the blade over the last part of the swing.
func _saber_trail(atk) -> void:
	var c := _shoulder()
	if int(atk.swing) == SW_DASH:
		_front.draw_line(c + _v(10, 0), c + _v(30, 1), Color(C_BLADE, 0.8), 3.0)
		_front.draw_line(c + _v(10, 0), c + _v(30, 1), C_SABLE, 1.0)
		return
	var a1 := _arm_angle
	var back := -1.0 if int(atk.swing) == SW_COMBO2 else 1.0
	var a0 := a1 - back * 1.3
	for ring in [[25.0, 3.0, Color(C_BLADE, 0.75)], [21.0, 1.0, Color(C_SABLE, 0.6)]]:
		var pts := PackedVector2Array()
		for k in 9:
			var ang := lerpf(a0, a1, k / 8.0)
			var d := Vector2(cos(ang), sin(ang)) * float(ring[0])
			pts.append(c + Vector2(d.x * _f, d.y))
		_front.draw_polyline(pts, ring[2], ring[1])
