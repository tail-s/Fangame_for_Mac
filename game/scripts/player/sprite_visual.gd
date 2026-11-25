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
const SpriteFx = preload("res://scripts/fx/sprite_fx.gd")
const ArmorFx = preload("res://scripts/fx/armor_fx.gd")
const Afterimage = preload("res://scripts/fx/afterimage.gd")
const Autoloads = preload("res://scripts/core/autoloads.gd")
const C_LV1 := Color("3de0ee")
const C_LV2 := Color("f0b84a")
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
## Transition clips and the base animations they lead into.
const CLIPS := {"run_start": ["run"], "dash_start": ["dash"], "dash_end": ["idle"], "land": ["idle"]}
## Seconds the warp beam falls before the sprite appears.
const BEAM_TIME := 0.3

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
var _aura: Sprite2D
var _fx_clock := 0.0
var _prev_shoot := 0.0
var _prev_charge := 0
var _f := 1
var _was_floor := true
var _warp_t := 0.0
var _ghost_clock := 0.0
## Time in the current special phase ("<kind><phase>"), for wing / landing effects.
var _sp_key := ""
var _sp_t := 0.0
## Set from outside: "warp_in" when a stage starts, "victory" on mission complete.
var force_anim := "":
	set(value):
		force_anim = value
		_warp_t = 0.0


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
	_aura = Sprite2D.new()
	_aura.region_enabled = true
	_aura.position = Vector2(0, -16)
	_aura.visible = false
	add_child(_aura)
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
	var prev := anim
	_pick(p, delta)
	_apply()
	_tint(p)
	_effects(p, delta, prev)
	queue_redraw()
	_front.queue_redraw()


func _pick(p, delta: float) -> void:
	var on_floor: bool = p.is_on_floor()
	var landed := on_floor and not _was_floor
	_was_floor = on_floor
	if force_anim != "":
		_pick_forced(p, delta, on_floor)
		return
	var base := "idle"
	var special: String = p.special_kind
	if p.is_hurt():
		base = "hurt"
	elif special in ["overdrive", "nova", "tag_strike"]:
		base = "rush"
	elif special == "skybreaker":
		base = "dive_rise" if p.special_phase == 0 else "dive"
	elif p.is_wall_sliding():
		base = "wall_slide"
	elif p.air_dashing:
		base = "air_dash"
	elif p.is_dashing():
		base = "dash"
	elif p.flying or _field(p, "hovering", false):
		base = "fly"
	elif p.gliding:
		base = "glide"
	elif not on_floor:
		var vy: float = p.velocity.y
		if _field(p, "wall_lock_timer", 0.0) > 0.0 and vy < 0.0:
			base = "wall_kick"
		elif vy < -90.0:
			base = "jump"
		elif vy < 70.0:
			base = "apex"
		else:
			base = "fall"
	elif absf(p.velocity.x) > 1.0:
		base = "run"
	# 32-bit style transition clips: run / dash start, dash brake, landing.
	var next := base
	var anims: Dictionary = _sheet.meta.anims
	if base == "dash" and not anim in ["dash", "dash_start"] and anims.has("dash_start"):
		next = "dash_start"
	elif base == "run" and anim in ["idle", "dash_end"] and anims.has("run_start"):
		next = "run_start"
	elif base == "idle" and anim in ["dash", "dash_start"] and on_floor and anims.has("dash_end"):
		next = "dash_end"
	elif base == "idle" and landed:
		next = "land"
	# Let a transition clip finish while what follows it is what we'd play anyway.
	if CLIPS.has(anim) and base in CLIPS[anim] and not _anim_done():
		next = anim
	if next != anim:
		_play(next)
	else:
		_anim_t += delta


## Stage start (beam in, then "warp_in") and mission complete ("victory").
func _pick_forced(p, delta: float, on_floor: bool) -> void:
	if force_anim == "warp_in":
		_warp_t += delta
		_rig.visible = _warp_t >= BEAM_TIME
		if _warp_t >= BEAM_TIME and (absf(p.velocity.x) > 1.0 or not on_floor or p.is_hurt()):
			force_anim = ""
			_rig.visible = true
			return
		if _warp_t < BEAM_TIME:
			return
	if anim != force_anim:
		_play(force_anim)
	else:
		_anim_t += delta
	if force_anim == "warp_in" and _anim_done():
		force_anim = ""


func _anim_done() -> bool:
	var a: Dictionary = _sheet.meta.anims.get(anim, {})
	if a.is_empty() or a.loop:
		return false
	return _anim_t * float(a.fps) >= a.frames.size()


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


## Sprite effects (art/fx): dash smoke, landing dust, wall sparks, muzzle flash,
## charge aura.
func _effects(p, delta: float, prev_anim: String) -> void:
	_fx_clock += delta
	var on_floor: bool = p.is_on_floor()
	if anim in ["dash", "dash_start"] and on_floor and _fx_clock >= 0.07:
		_fx_clock = 0.0
		_spawn("dash_smoke", Vector2(-9.0 * _f, -6.0), true)
	elif p.is_wall_sliding() and _fx_clock >= 0.1:
		_fx_clock = 0.0
		_spawn("wall_spark", Vector2(-8.0 * _f, -10.0), true)
	if anim == "land" and prev_anim != "land":
		_spawn("land_dust", Vector2(0, -5.0), true)
	if _arm_name == "buster":
		var st: float = p.shoot_pose_timer
		if st > _prev_shoot + 0.01:
			_spawn(ArmorFx.muzzle_strip(_family("arm"), _prev_charge), muzzle(), false, 24.0)
		_prev_shoot = st
	var charge: int = p.charge_level()
	_prev_charge = charge
	_aura.visible = charge > 0
	if charge > 0:
		_aura.texture = SpriteFx.strip(ArmorFx.charge_strip(_family("arm"), charge))
		var cw := _aura.texture.get_width() / 4
		_aura.region_rect = Rect2((int(p.anim_time * 14.0) % 4) * cw, 0, cw, _aura.texture.get_height())
	_afterimages(p, delta)


## Armor family worn in `slot` (IX only; SABLE / ECHO count as neutral).
func _family(slot: String) -> String:
	return part_armor.get(slot, "neutral") if character == "ix" else "neutral"


## Colour of SABLE / ECHO / IX for moves that are not armor-specific.
func _char_color() -> Color:
	return C_SABLE if character == "sable" else (C_ECHO if character == "echo" else C_LV1)


## Afterimages: rushes and dives always; dashes when the LEG armor gives them weight
## (Vanguard ground dash attack, Aero / Ultimate air dash).
func _afterimages(p, delta: float) -> void:
	var key: String = String(p.special_kind) + str(p.special_phase)
	if key != _sp_key:
		_sp_key = key
		_sp_t = 0.0
	else:
		_sp_t += delta
	_ghost_clock += delta
	if not (p is Node2D) or not visible:
		return
	var every := 0.0
	var color := Color.WHITE
	var alpha := 0.45
	var life := 0.18
	var special: String = p.special_kind
	if special in ["overdrive", "nova"]:
		every = 0.05
		color = ArmorFx.ghost(ArmorFx.SPECIAL_FAMILY[special])
	elif special == "skybreaker" and p.special_phase == 1:
		every = 0.03
		color = ArmorFx.ghost("aero")
	elif special == "tag_strike":
		every = 0.05
		color = _char_color()
	elif character == "ix" and p.air_dashing and _family("leg") in ["aero", "ultimate"]:
		every = 0.05
		color = ArmorFx.ghost(_family("leg"))
	elif character == "ix" and p.is_dashing() and not p.air_dashing and _family("leg") == "vanguard":
		every = 0.06
		color = ArmorFx.ghost("vanguard")
		alpha = 0.4
		life = 0.16
	if every <= 0.0:
		_ghost_clock = 0.0
		return
	if _ghost_clock >= every:
		_ghost_clock = 0.0
		Afterimage.capture(_rig, p, color, alpha, life)


func _spawn(name: String, offset: Vector2, world: bool, speed := 18.0) -> void:
	var fx := SpriteFx.new()
	fx.setup(name, speed)
	fx.scale.x = _f
	if world:
		fx.top_level = true
		add_child(fx)
		fx.global_position = global_position + offset
	else:
		fx.position = offset
		add_child(fx)


func _tint(p) -> void:
	var frame_n := Engine.get_physics_frames()
	modulate.a = 0.35 if (p.invuln_timer > 0.0 and frame_n % 4 < 2) else 1.0
	var amount := 0.0
	var tint := Color.WHITE
	if p.is_hurt() and frame_n % 4 < 2:
		amount = 0.85
	elif p.charge_level() == 2 or p.special_kind != "":
		var fam := _family("arm")
		if ArmorFx.SPECIAL_FAMILY.has(p.special_kind):
			fam = ArmorFx.SPECIAL_FAMILY[p.special_kind]
		# Armored IX glows in its energy's mid tone (a light tint would bleach white armor).
		tint = ArmorFx.energy(fam)[1] if character == "ix" and fam != "neutral" else C_LV2
		# "Reduce flashes": a steady glow instead of the strobe.
		if not Autoloads.flashes():
			amount = 0.18
		elif frame_n % 6 < 3:
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


## Behind the sprites: speed streaks, armor special auras and wings, thrusters, warp beam.
func _draw() -> void:
	var p = player
	if p == null:
		return
	var t: float = p.anim_time
	var special: String = p.special_kind
	var strobe := Autoloads.flashes()
	if p.air_dashing or special in ["overdrive", "nova", "tag_strike"]:
		var c := _char_color()
		if ArmorFx.SPECIAL_FAMILY.has(special):
			c = ArmorFx.energy(ArmorFx.SPECIAL_FAMILY[special])[1]
		elif character == "ix" and p.air_dashing and _family("leg") != "neutral":
			c = ArmorFx.energy(_family("leg"))[1]
		for i in 4:
			var y := -26.0 + i * 6.0
			var x0 := -_f * (8.0 + (i % 2) * 4.0)
			draw_line(Vector2(x0, y), Vector2(x0 - _f * (10.0 + i * 2.0), y), Color(c, 0.55 - i * 0.1), 1.0)
	if force_anim == "warp_in" and _warp_t < BEAM_TIME + 0.12:
		var c := _char_color()
		var k := clampf(_warp_t / BEAM_TIME, 0.0, 1.0)
		var top := -220.0
		var bottom := lerpf(top, -2.0, k)
		draw_rect(Rect2(-3, top, 6, bottom - top), Color(c, 0.85))
		draw_rect(Rect2(-1, top, 2, bottom - top), Color(1, 1, 1, 0.9))
		if k >= 1.0:
			draw_rect(Rect2(-8, -3, 16, 3), Color(c, 0.7))
	match special:
		"overdrive":
			_draw_rush_sparks(t)
		"nova":
			_draw_nova_aura(t, strobe)
		"skybreaker":
			_draw_sky_breaker(int(p.special_phase))
	if p.flying or _field(p, "hovering", false):
		_draw_thrusters(t)
	elif character == "ix" and _field(p, "gliding", false):
		_draw_glide_wisps(t)


## Pixel at facing-space (x, y): mirrored by hand like _v, so a 1px cell stays a cell.
func _dot(ci: CanvasItem, x: float, y: float, size: Vector2, col: Color) -> void:
	var px := x if _f > 0 else -x - size.x
	ci.draw_rect(Rect2(Vector2(px, y).round(), size), col)


func _ellipse_pts(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := i * TAU / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse_ring(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := _ellipse_pts(c, rx, ry)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, 1.0)


## Energy blade (Sky Breaker wing): narrow root, widest just past the middle, sharp tip.
func _blade(root: Vector2, dir: Vector2, length: float, width: float, ramp: Array, alpha := 0.85) -> void:
	var n := Vector2(-dir.y, dir.x)
	var tip := root + dir * length
	var mid := root + dir * length * 0.55
	draw_colored_polygon(PackedVector2Array([root, mid + n * width, tip, mid - n * width * 0.45]),
			Color(ramp[1], alpha))
	draw_line(root.round(), tip.round(), Color(ramp[2], alpha), 1.0)
	draw_rect(Rect2(tip.round() - Vector2(1, 1), Vector2(2, 2)), Color(ramp[3], alpha))


## Overdrive Rush: gold sparks scraping off the boots and a crimson heat wake.
func _draw_rush_sparks(t: float) -> void:
	var red: Array = ArmorFx.energy("vanguard")
	for i in 8:
		var k := fmod(t * 4.0 + i * 0.125, 1.0)
		var col: Color = ArmorFx.GOLD[2] if k < 0.3 else (ArmorFx.GOLD[1] if k < 0.65 else red[0])
		_dot(self, -4.0 - k * 28.0, -1.0 - sin(k * PI) * (3.0 + (i % 3) * 2.5),
				Vector2(2, 1) if k < 0.4 else Vector2.ONE, col)
	for i in 3:
		var y := -24.0 + i * 8.0
		_dot(self, -30.0, y, Vector2(22, 1), Color(red[1], 0.25))


## Nova Strike: a gold energy shell with a violet inner ring and a comet tail.
func _draw_nova_aura(t: float, strobe: bool) -> void:
	var gold: Array = ArmorFx.energy("ultimate")
	var violet: Array = ArmorFx.accent("ultimate")
	var c := Vector2(0, -18)
	var pulse := 1.0 + (0.08 * sin(t * 40.0) if strobe else 0.0)
	var rx := 13.0 * pulse
	var ry := 19.0 * pulse
	draw_colored_polygon(_ellipse_pts(c, rx, ry), Color(gold[1], 0.2))
	_ellipse_ring(self, c, rx - 2.0, ry - 2.0, Color(violet[3], 0.55))
	_ellipse_ring(self, c, rx, ry, Color(gold[2], 0.9))
	for i in 3:
		var y := -26.0 + i * 8.0
		var pts := PackedVector2Array()
		for k in 7:
			pts.append(_v(-10.0 - k * 4.0, y + (i - 1) * k * 0.9))
		draw_polyline(pts, Color(gold[1], 0.75 - i * 0.18), 1.0)


## Sky Breaker: wings flare open on the rise, a lance of light rides the dive,
## and a ring of air spreads from the landing.
func _draw_sky_breaker(phase: int) -> void:
	var blue: Array = ArmorFx.energy("aero")
	match phase:
		0:
			var k := clampf(_sp_t / 0.2, 0.0, 1.0)
			var ease := 1.0 - (1.0 - k) * (1.0 - k)
			# Far wing (faint, leaning forward), then the near wing's three blades fanning back.
			for i in 2:
				var a := 0.2 + i * 0.4
				var d := Vector2(sin(a * ease) * _f, -cos(a * ease))
				_blade(_v(2, -24), d, (14.0 + i * 4.0) * (0.4 + 0.6 * ease), 2.6, blue, 0.45)
			for i in 3:
				var a := (0.45 + i * 0.45) * ease
				var d := Vector2(-sin(a) * _f, -cos(a))
				_blade(_v(-4, -24), d, (21.0 + i * 4.0) * (0.4 + 0.6 * ease), 4.4 - i * 0.7, blue)
		1:
			draw_rect(Rect2(-6, -74, 12, 50), Color(blue[1], 0.28))
			draw_rect(Rect2(-3, -70, 6, 46), Color(blue[2], 0.55))
			draw_rect(Rect2(-1, -66, 2, 42), Color(blue[3], 0.9))
			for i in 4:
				var k := fmod(_sp_t * 6.0 + i * 0.25, 1.0)
				var x := -9.0 if i % 2 == 0 else 8.0
				draw_rect(Rect2(x, -20.0 - k * 50.0, 1, 6), Color(blue[2], 1.0 - k))
		_:
			var k := clampf(_sp_t / 0.2, 0.0, 1.0)
			var rx := 6.0 + k * 26.0
			_ellipse_ring(self, Vector2(0, -1), rx, 2.0 + k * 4.0, Color(blue[2], 1.0 - k))
			_ellipse_ring(self, Vector2(0, -1), rx * 0.6, 1.0 + k * 2.0, Color(blue[3], 0.8 * (1.0 - k)))


## Flight / hover jets from the boots in the LEG armor's energy colour (ECHO violet),
## plus drifting motes off Aero / Ultimate wings.
func _draw_thrusters(t: float) -> void:
	var ramp: Array
	if character == "echo":
		ramp = [C_ECHO.darkened(0.4), C_ECHO, C_ECHO.lightened(0.5), Color.WHITE]
	else:
		ramp = ArmorFx.energy(_family("leg"))
	for x in [-1.0, 3.0]:
		var flame := 5.0 + fmod(t * 50.0 + x, 3.0)
		draw_colored_polygon(PackedVector2Array([_v(x - 2, 0), _v(x + 2, 0), _v(x, flame)]), Color(ramp[1], 0.85))
		draw_colored_polygon(PackedVector2Array([_v(x - 1, 0), _v(x + 1, 0), _v(x, flame * 0.6)]), ramp[2])
		_dot(self, x - 0.5, 0.0, Vector2.ONE, ramp[3])
	if character == "ix" and _family("leg") in ["aero", "ultimate"]:
		for i in 3:
			var k := fmod(t * 2.5 + i / 3.0, 1.0)
			_dot(self, -7.0 - k * 12.0, -24.0 + i * 3.0 + k * 4.0, Vector2.ONE, Color(ramp[2], 1.0 - k))


## Aero BODY glide: wind wisps peeling off the back.
func _draw_glide_wisps(t: float) -> void:
	var ramp: Array = ArmorFx.energy(_family("body"))
	for i in 3:
		var k := fmod(t * 3.0 + i / 3.0, 1.0)
		_dot(self, -6.0 - k * 14.0, -22.0 + i * 3.0 + k * 2.0, Vector2(2, 1), Color(ramp[2], (1.0 - k) * 0.8))


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
	match p.special_kind:
		"overdrive":
			_draw_claw_ram(t)
		"nova":
			_draw_nova_core(t)
	var charge: int = p.charge_level()
	if charge <= 0:
		return
	var cc := ArmorFx.charge_color(_family("arm"), charge)
	_front.draw_circle(muzzle(), 1.5 + (frame_n % 3) * 0.5, cc)


## Overdrive Rush: a magenta energy wedge thrown ahead of the claw, with talon streaks.
func _draw_claw_ram(t: float) -> void:
	var red: Array = ArmorFx.energy("vanguard")
	var flick := Autoloads.flashes() and int(t * 30.0) % 2 == 0
	var top := _v(13, -31)
	var tip := _v(26, -16)
	var bot := _v(13, -1)
	_front.draw_colored_polygon(PackedVector2Array([top, tip, bot, _v(17, -16)]),
			Color(red[1], 0.35 if flick else 0.5))
	_front.draw_colored_polygon(PackedVector2Array([_v(15, -25), _v(23, -16), _v(15, -7), _v(18, -16)]),
			Color(red[2], 0.55))
	_front.draw_polyline(PackedVector2Array([top, tip, bot]), red[3] if flick else red[2], 1.0)
	for i in 3:
		var y := -22.0 + i * 6.0
		_front.draw_line(_v(8, y), _v(20.0 - absf(i - 1) * 3.0, y + (i - 1) * 1.5), Color(red[2], 0.9), 1.0)


## Nova Strike: a gold four-point star at the chest.
func _draw_nova_core(t: float) -> void:
	var gold: Array = ArmorFx.energy("ultimate")
	var c := _v(9, -18).round()
	var r := 5.0 + (fmod(t * 20.0, 2.0) if Autoloads.flashes() else 0.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_front.draw_line(c, c + d * r, gold[2], 1.0)
	_front.draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), gold[3])


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
