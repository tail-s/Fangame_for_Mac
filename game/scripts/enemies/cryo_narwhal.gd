extends "res://scripts/enemies/boss_base.gd"
## CRYO NARWHAL — polar deep-sea base boss (GDD v0.2 §5-1). Weakness: HEAT MIRAGE.
## A narwhal-shaped submarine robot with an ice horn. Its room (levels/cryo_narwhal.txt)
## has a flooded seabed band 3 tiles deep: the narwhal rams along the seabed and surfaces
## to attack from above the water line. Every attack has a readable wind-up:
##   LANCE CHARGE  swims along the surface to the wall far from the player, hovers, sinks
##                 to the seabed, glints its horn over a lane marker, then rams across the
##                 floor (jump it). Phase 2: faster, and rams straight back once.
##   ICICLE RAIN   surfaces mid-room and flares the ceiling: icicles grow over every third
##                 32 px slot (always one over the player, never two slots in a row), then
##                 drop. Phase 2: a second wave re-aims at the player.
##   FROST BREATH  surfaces on the far side and breathes fans of ice shards at the player
##                 (3 shards x 2 volleys; phase 2: 5 shards x 3 volleys).
##   GLACIER WAVE  phase 2 only (and its first move after the phase-2 roar): breaches to
##                 the ceiling, flips horn-down, slams into the seabed, and ice pillars
##                 ripple across the floor away from it (jump the wave).
## The first cycle runs BREATH -> CHARGE -> RAIN so each attack is seen once; after that
## the order is shuffled (never the same attack twice in a row).
## While it travels it stays on the surface line, above a standing player's head; it only
## enters the seabed lane after a hover (charge dive / glacier slam). Each attack ends in a
## recovery — on the seabed lane after charges and slams (standing buster shots hit), on
## the surface otherwise (jump shots hit). A Heat Mirage hit melts the ice armour: the
## attack stops, icicle marks and pillars melt away, and it trembles in place, steaming
## (the base class caps this to once per stagger_cooldown).

enum S {
	INTRO, IDLE, SWIM, DIVE, CHARGE_WIND, CHARGE, BONK, RAIN_AIM, RAIN_MARK, RAIN_FALL,
	BREATH_WIND, BREATH, WAVE_LEAP, WAVE_AIM, WAVE_SLAM, WAVE_RUN, RECOVER, STAGGER, ROAR,
}

## Attack names, in the order they are introduced (`pattern` holds the current one).
const PATTERNS := ["charge", "rain", "breath", "wave"]
## Depth of the flooded band at the bottom of the room (3 tiles of `~`).
const BAND := 48.0
## Body centre to wall at the ends of the room (the horn just touches the wall).
const SIDE_MARGIN := 28.0
## Icicle rain grid: one icicle over every third slot.
const SLOT := 32.0
const PILLAR_STEP := 22.0
const PILLAR_INTERVAL := 0.085

const C_HULL := Color("1c375b")
const C_HULL_DARK := Color("101b36")
const C_BELLY := Color("d7edf3")
const C_ICE := Color("92dafa")
const C_ICE_HI := Color("e8fbff")
const C_ICE_DEEP := Color("4f8fb3")
const C_STRIPE := Color("00b8be")
const C_FIN := Color("6543a2")
const C_EYE := Color("f0b84a")
const C_HOT := Color("e34f5b")

var state := S.INTRO
## Current attack ("charge", "rain", "breath", "wave"), "roar" during the phase change.
var pattern := ""
## Horn tilt in radians: 0 = level, -PI/2 = up, PI/2 = down (mirrored by `facing`).
var tilt := 0.0

var _timer := 0.0
var _path: Array = []
var _after := S.IDLE
var _dir := 1.0
var _speed := 0.0
var _charges_left := 0
var _volleys_left := 0
var _waves_left := 0
var _rain_spots: Array = []
var _rain_time := 1.0
var _wind_time := 1.0
var _pillars: Array = []
var _deck: Array = []
var _last_pattern := ""
var _force_next := ""
var _roar_pending := false
var _shake := 0.0
var _glow := 0.0
var _intro_from := Vector2.ZERO
var _intro_total := 1.2
var _splashed := false
var _lane_y := 0.0
var _surface_y := 0.0
var _top_y := 0.0
var _left_x := 0.0
var _right_x := 0.0


func _init() -> void:
	boss_name = "CRYO NARWHAL"
	max_hp = 32
	weakness = "heat_mirage"
	contact_damage = 3
	hit_radius = 13.0
	intro_time = 1.2


func _boss_ready() -> void:
	_lane_y = arena.end.y - hit_radius
	_surface_y = maxf(arena.end.y - BAND - 4.0, arena.position.y + hit_radius)
	_top_y = arena.position.y + hit_radius + 4.0
	_left_x = arena.position.x + SIDE_MARGIN
	_right_x = arena.end.x - SIDE_MARGIN
	_intro_from = position
	_intro_total = intro_time
	# The first cycle shows each attack once in a readable order; later cycles shuffle.
	_deck = ["breath", "charge", "rain"]
	_face_player()


# --- flow -----------------------------------------------------------------------------

## Drops from the spawn marker onto the water line.
func _boss_intro(_delta: float) -> void:
	var k := clampf(t / _intro_total, 0.0, 1.0)
	position = Vector2(_intro_from.x, lerpf(_intro_from.y, _surface_y, 1.0 - pow(1.0 - k, 3.0)))
	_face_player()
	if k > 0.7 and not _splashed:
		_splashed = true
		fx(position + Vector2(0, 10), 14.0)


func _on_active() -> void:
	state = S.IDLE
	_timer = 0.5


func _boss_process(delta: float) -> void:
	_timer -= delta
	_shake = maxf(_shake - delta, 0.0)
	match state:
		S.IDLE:
			_face_player()
			_tilt_to(0.0, delta)
			if _timer <= 0.0:
				_next_pattern()
		S.SWIM:
			_tilt_to(0.0, delta)
			_process_swim(delta)
		S.DIVE:
			facing = _dir
			if _timer <= 0.0:
				position.y = move_toward(position.y, _lane_y, 150.0 * delta)
				if position.y >= _lane_y - 0.01:
					_enter_wind(0.5 if phase2 else 0.75)
		S.CHARGE_WIND:
			facing = _dir
			_glow = clampf(1.0 - _timer / _wind_time, 0.0, 1.0)
			if _timer <= 0.0:
				state = S.CHARGE
				_speed = 0.0
		S.CHARGE:
			_speed = minf(_speed + 1500.0 * delta, 360.0 if phase2 else 290.0)
			position.x += _dir * _speed * delta
			var end_x := _right_x if _dir > 0.0 else _left_x
			if (position.x - end_x) * _dir >= 0.0:
				position.x = end_x
				_bonk()
		S.BONK:
			position.x -= _dir * 35.0 * delta
			if _timer <= 0.0:
				if _charges_left > 0:
					_charges_left -= 1
					_dir = -_dir
					_enter_wind(0.4)
				else:
					_recover()
		S.RAIN_AIM:
			_face_player()
			_tilt_to(-PI / 2.0, delta)
			if _timer <= 0.0:
				_mark_rain(0.75 if phase2 else 0.95)
		S.RAIN_MARK:
			_face_player()
			_tilt_to(-PI / 2.0, delta)
			if _timer <= 0.0:
				_drop_rain()
		S.RAIN_FALL:
			_face_player()
			if _timer <= 0.0:
				if _waves_left > 0:
					_waves_left -= 1
					_mark_rain(0.65)
				else:
					_recover()
		S.BREATH_WIND:
			_face_player()
			_glow = clampf(1.0 - _timer / _wind_time, 0.0, 1.0)
			if _timer <= 0.0:
				state = S.BREATH
				_timer = 0.0
		S.BREATH:
			_face_player()
			_glow = maxf(_glow - delta * 3.0, 0.0)
			if _timer <= 0.0:
				if _volleys_left > 0:
					_volleys_left -= 1
					_breath_volley()
					_timer = 0.5 if phase2 else 0.6
				else:
					_recover()
		S.WAVE_LEAP:
			_tilt_to(-PI / 2.0, delta * 2.0)
			position.y = move_toward(position.y, _top_y, 320.0 * delta)
			if position.y <= _top_y + 0.01:
				state = S.WAVE_AIM
				_timer = 0.55
				_wind_time = 0.55
		S.WAVE_AIM:
			_tilt_to(PI / 2.0, delta * 1.6)
			_glow = clampf(1.0 - _timer / _wind_time, 0.0, 1.0)
			if _timer <= 0.0:
				tilt = PI / 2.0
				state = S.WAVE_SLAM
				_speed = 60.0
		S.WAVE_SLAM:
			_speed = minf(_speed + 2200.0 * delta, 480.0)
			position.y += _speed * delta
			if position.y >= _lane_y:
				position.y = _lane_y
				_slam()
		S.WAVE_RUN:
			_glow = maxf(_glow - delta * 2.0, 0.0)
			if _timer <= 0.0:
				_recover()
		S.RECOVER:
			_face_player()
			_tilt_to(0.0, delta)
			_glow = maxf(_glow - delta * 3.0, 0.0)
			if _timer <= 0.0:
				_next_pattern()
		S.STAGGER:
			_tilt_to(0.35, delta * 0.5)
			if _timer <= 0.0:
				_recover(0.3)
		S.ROAR:
			_face_player()
			_tilt_to(-0.5, delta)
			if _timer <= 0.0:
				state = S.IDLE
				_timer = 0.2
	clamp_to_arena(hit_radius)


func _next_pattern() -> void:
	if _roar_pending:
		_roar_pending = false
		pattern = "roar"
		state = S.ROAR
		_timer = 0.9
		_shake = 0.9
		for x in [-8.0, 7.0]:
			fx(position + Vector2(x * facing, -9), 7.0)
		return
	var pick := ""
	if _force_next != "":
		pick = _force_next
		_force_next = ""
	else:
		if _deck.is_empty():
			_deck = PATTERNS.slice(0, 4 if phase2 else 3)
			_deck.shuffle()
			if _deck[0] == _last_pattern:
				_deck.push_back(_deck.pop_front())
		pick = _deck.pop_front()
	_last_pattern = pick
	pattern = pick
	_glow = 0.0
	match pick:
		"charge":
			# Start from the wall far from the player and ram toward them.
			var from_right := player_pos().x < arena.get_center().x
			_dir = -1.0 if from_right else 1.0
			_charges_left = 1 if phase2 else 0
			_swim_surface(_right_x if from_right else _left_x, S.DIVE)
		"rain":
			_waves_left = 1 if phase2 else 0
			_swim_surface(arena.get_center().x, S.RAIN_AIM)
		"breath":
			_volleys_left = 3 if phase2 else 2
			var right := player_pos().x < arena.get_center().x
			_swim_surface(_right_x - 10.0 if right else _left_x + 10.0, S.BREATH_WIND)
		"wave":
			var right := player_pos().x < arena.get_center().x
			_swim_surface(_right_x if right else _left_x, S.WAVE_LEAP)


## Moves along the surface line (rising to it first) and enters `after` on arrival.
func _swim_surface(x: float, after: int) -> void:
	_path.clear()
	if absf(position.y - _surface_y) > 0.5:
		_path.append(Vector2(position.x, _surface_y))
	_path.append(Vector2(x, _surface_y))
	_after = after
	state = S.SWIM


func _process_swim(delta: float) -> void:
	var step := (210.0 if phase2 else 170.0) * delta
	while step > 0.0 and not _path.is_empty():
		var target: Vector2 = _path[0]
		var off := target - position
		if absf(off.x) > 0.5:
			facing = signf(off.x)
		if off.length() <= step:
			position = target
			step -= off.length()
			_path.pop_front()
		else:
			position += off.normalized() * step
			step = 0.0
	if _path.is_empty():
		_arrive(_after)


func _arrive(next: int) -> void:
	state = next
	match next:
		S.DIVE:
			_timer = 0.3
		S.RAIN_AIM:
			_timer = 0.4
		S.BREATH_WIND:
			_wind_time = 0.4 if phase2 else 0.55
			_timer = _wind_time
		S.WAVE_LEAP:
			facing = 1.0 if position.x < arena.get_center().x else -1.0
			fx(position + Vector2(0, 8), 12.0)


func _enter_wind(time: float) -> void:
	state = S.CHARGE_WIND
	facing = _dir
	_wind_time = time
	_timer = time
	_glow = 0.0


func _bonk() -> void:
	state = S.BONK
	_timer = 0.22
	_shake = 0.25
	_glow = 0.0
	fx(position + Vector2(24.0 * _dir, 0), 9.0)


func _recover(time := -1.0) -> void:
	state = S.RECOVER
	_timer = time if time >= 0.0 else (0.55 if phase2 else 0.8)


# --- attacks ------------------------------------------------------------------------------

## Marks every third slot, counted from the player's slot (safe spots are 1 slot away).
func _mark_rain(time: float) -> void:
	state = S.RAIN_MARK
	_rain_time = time
	_timer = time
	_rain_spots.clear()
	var slots := maxi(int(arena.size.x / SLOT), 1)
	var px := clampf(player_pos().x, arena.position.x, arena.end.x - 1.0)
	var ps := int((px - arena.position.x) / SLOT)
	for s in slots:
		var x := arena.position.x + (s + 0.5) * SLOT
		# Skip the column through its own body unless the player is under it.
		if posmod(s - ps, 3) == 0 and (s == ps or absf(x - position.x) > 18.0):
			_rain_spots.append(x)


func _drop_rain() -> void:
	for x in _rain_spots:
		var ic := Icicle.new()
		ic.position = Vector2(x, arena.position.y + 9.0)
		ic.velocity = Vector2(0, 40.0)
		get_parent().add_child(ic)
	_rain_spots.clear()
	state = S.RAIN_FALL
	_timer = 0.6


func _breath_volley() -> void:
	var mouth := position + Vector2(16.0 * facing, 2.0)
	var aim := (player_pos() - mouth).angle()
	var n := 5 if phase2 else 3
	var spread := 0.26 if phase2 else 0.32
	for i in n:
		var shard := Shard.new()
		shard.position = mouth
		shard.velocity = Vector2.from_angle(aim + (i - (n - 1) / 2.0) * spread) * (150.0 if phase2 else 135.0)
		get_parent().add_child(shard)
	_glow = 1.0


func _slam() -> void:
	state = S.WAVE_RUN
	_shake = 0.35
	fx(position + Vector2(0, hit_radius), 14.0)
	var dir := 1.0 if position.x < arena.get_center().x else -1.0
	var x := position.x + dir * 26.0
	var i := 0
	while x > arena.position.x + 6.0 and x < arena.end.x - 6.0:
		var p := IcePillar.new()
		p.position = Vector2(x, arena.end.y)
		p.delay = i * PILLAR_INTERVAL
		get_parent().add_child(p)
		_pillars.append(p)
		x += dir * PILLAR_STEP
		i += 1
	_timer = i * PILLAR_INTERVAL + 0.7


func _clear_pillars() -> void:
	for p in _pillars:
		if is_instance_valid(p):
			p.queue_free()
	_pillars.clear()


# --- base hooks -----------------------------------------------------------------------------

## Heat Mirage melts the ice armour: stop the attack and tremble in place, steaming.
## (May run inside a physics callback: only state changes and frees here.)
func _on_stagger() -> void:
	state = S.STAGGER
	_timer = 1.0
	_shake = 0.3
	_glow = 0.0
	_speed = 0.0
	_charges_left = 0
	_volleys_left = 0
	_waves_left = 0
	_rain_spots.clear()
	_path.clear()
	_clear_pillars()


func _on_phase2() -> void:
	_roar_pending = true
	_force_next = "wave"
	_deck.clear()


func _on_death() -> void:
	_rain_spots.clear()
	_clear_pillars()
	_glow = 0.0
	state = S.STAGGER  # drawn overheated and steaming while it blows up
	_timer = 1.0


# --- helpers ---------------------------------------------------------------------------------

func _face_player() -> void:
	var dx := player_pos().x - position.x
	if absf(dx) > 2.0:
		facing = signf(dx)


func _tilt_to(target: float, delta: float) -> void:
	tilt = move_toward(tilt, target, 5.0 * delta)


# --- drawing ---------------------------------------------------------------------------------

func _boss_draw(white: bool) -> void:
	_draw_telegraphs()
	var off := Vector2.ZERO
	if _shake > 0.0:
		off = Vector2(sin(t * 91.0) * 1.5, cos(t * 77.0))
	if state in [S.IDLE, S.SWIM, S.RAIN_MARK, S.RAIN_FALL, S.BREATH, S.RECOVER] and _dying < 0.0:
		off.y += sin(t * 3.2) * 1.5
	var hot := 0.0
	if state == S.STAGGER:
		hot = clampf(_timer, 0.0, 1.0) * 0.6
	var col := func(c: Color) -> Color: return Color.WHITE if white else c
	var hull: Color = col.call(C_HULL.lerp(C_HOT, hot))
	if state == S.CHARGE:
		for i in 3:
			var bx := -facing * (22.0 + i * 7.0 + fmod(t * 70.0, 7.0))
			draw_circle(off + Vector2(bx, sin(t * 11.0 + i) * 3.0), 1.5 + i * 0.5, Color(C_ICE_HI, 0.45))
	draw_set_transform(off, tilt * facing, Vector2(facing, 1.0))
	# tail flukes and propeller
	draw_colored_polygon(PackedVector2Array([Vector2(-13, 0), Vector2(-20, -7), Vector2(-17, 0),
			Vector2(-20, 7)]), col.call(C_FIN))
	var blade := sin(t * 32.0) * 5.0
	draw_line(Vector2(-15, -blade), Vector2(-15, blade), col.call(C_STRIPE), 2.0)
	# hull with a pale belly plate
	var body := PackedVector2Array([Vector2(-14, -2), Vector2(-10, -7), Vector2(-2, -9), Vector2(7, -8),
			Vector2(12, -5), Vector2(14, 0), Vector2(12, 5), Vector2(5, 8), Vector2(-6, 8), Vector2(-12, 5)])
	draw_colored_polygon(body, hull)
	draw_colored_polygon(PackedVector2Array([Vector2(-11, 4), Vector2(12, 3), Vector2(12, 5),
			Vector2(5, 8), Vector2(-6, 8), Vector2(-12, 5)]), col.call(C_BELLY))
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, col.call(C_HULL_DARK), 1.0)
	# conning tower with a teal band
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -8), Vector2(-3, -13), Vector2(3, -13),
			Vector2(5, -8)]), col.call(C_HULL_DARK))
	draw_line(Vector2(-3, -11), Vector2(3, -11), col.call(C_STRIPE), 1.0)
	# ice armour plates on the back (one breaks off in phase 2)
	for px in ([-10.0] if phase2 else [-10.0, 8.0]):
		draw_colored_polygon(PackedVector2Array([Vector2(px - 3, -6), Vector2(px, -10), Vector2(px + 3, -6),
				Vector2(px, -4)]), col.call(C_ICE.lerp(C_HOT, hot)))
	if phase2:
		draw_polyline(PackedVector2Array([Vector2(6, -8), Vector2(8, -5), Vector2(7, -2)]), col.call(C_ICE), 1.0)
	# flipper, visor, mouth
	draw_colored_polygon(PackedVector2Array([Vector2(0, 6), Vector2(-5, 11), Vector2(4, 8)]), col.call(C_FIN))
	draw_rect(Rect2(7, -5, 4, 3), col.call(C_HOT if phase2 else C_EYE))
	draw_line(Vector2(10, 3), Vector2(14, 2), col.call(C_HULL_DARK), 1.0)
	if state == S.BREATH_WIND or (state == S.BREATH and _glow > 0.0):
		draw_circle(Vector2(15, 2), 1.5 + 3.0 * _glow, Color(C_ICE_HI, 0.85))
	# spiral ice horn; it glows and glints during wind-ups
	draw_colored_polygon(PackedVector2Array([Vector2(12, -3), Vector2(27, -1), Vector2(12, 1)]),
			col.call(C_ICE.lerp(C_ICE_HI, _glow)))
	for i in 3:
		var hx := 15.0 + i * 4.0
		draw_line(Vector2(hx, -2.4 + i * 0.4), Vector2(hx + 2.0, 0.6 - i * 0.3), col.call(C_ICE_DEEP), 1.0)
	if _glow > 0.05 and state in [S.CHARGE_WIND, S.WAVE_AIM]:
		var g := 2.0 + 4.0 * _glow
		draw_line(Vector2(27 - g, -1), Vector2(27 + g, -1), Color(C_ICE_HI, _glow), 1.0)
		draw_line(Vector2(27, -1 - g), Vector2(27, -1 + g), Color(C_ICE_HI, _glow), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state == S.STAGGER:
		for i in 4:
			var ph := fmod(t * 1.6 + i * 0.25, 1.0)
			draw_circle(off + Vector2(-9.0 + i * 6.0, -12.0 - ph * 14.0), 1.5 + ph * 2.5, Color(1, 1, 1, 0.55 * (1.0 - ph)))


## World-space warnings: charge lane, icicle marks, slam column, dive bubbles.
func _draw_telegraphs() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match state:
		S.CHARGE_WIND:
			var end_x := _right_x if _dir > 0.0 else _left_x
			var a := 0.25 + 0.5 * _glow * (0.6 + 0.4 * sin(t * 30.0))
			var y := arena.end.y - 2.0
			draw_dashed_line(to_local(Vector2(position.x + _dir * 28.0, y)), to_local(Vector2(end_x + _dir * 26.0, y)),
					Color(C_ICE, a), 2.0, 6.0)
		S.RAIN_MARK:
			var k := clampf(1.0 - _timer / _rain_time, 0.0, 1.0)
			var blink := int(t * (8.0 + 14.0 * k)) % 2 == 0
			for x in _rain_spots:
				var top := to_local(Vector2(x, arena.position.y))
				var length := 4.0 + 11.0 * k
				draw_colored_polygon(PackedVector2Array([top + Vector2(-4, 0), top + Vector2(4, 0),
						top + Vector2(0, length)]), C_ICE)
				draw_line(top + Vector2(-1, 1), top + Vector2(0, length - 3.0), C_ICE_HI, 1.0)
				if blink:
					draw_dashed_line(top + Vector2(0, length + 4.0), to_local(Vector2(x, arena.end.y)),
							Color(C_ICE, 0.3), 1.0, 4.0)
				draw_line(to_local(Vector2(x - 6.0, arena.end.y - 1.0)), to_local(Vector2(x + 6.0, arena.end.y - 1.0)),
						Color(C_ICE, 0.35 + 0.5 * k), 2.0)
		S.WAVE_AIM:
			if int(t * 16.0) % 2 == 0:
				draw_dashed_line(Vector2(0, 16), to_local(Vector2(position.x, arena.end.y)), Color(C_ICE, 0.35), 1.0, 4.0)
			draw_arc(to_local(Vector2(position.x, arena.end.y - 2.0)), 6.0 + 6.0 * _glow, PI, TAU, 10,
					Color(C_ICE, 0.7), 2.0)
		S.DIVE:
			for i in 3:
				var ph := fmod(t * 2.2 + i * 0.33, 1.0)
				draw_circle(Vector2(-8.0 + i * 8.0, 14.0 - ph * 10.0), 1.5, Color(C_ICE_HI, 0.6 * (1.0 - ph)))


# --- projectiles (inner classes keep the boss to one file) --------------------------------

## ICICLE RAIN: accelerates downward and shatters on the floor or the player.
class Icicle extends "res://scripts/combat/enemy_shot.gd":
	var accel := 700.0
	var max_speed := 430.0

	func _ready() -> void:
		super()
		life = 2.5
		var rect := RectangleShape2D.new()
		rect.size = Vector2(8, 14)
		(get_child(0) as CollisionShape2D).shape = rect

	func _physics_process(delta: float) -> void:
		velocity.y = minf(velocity.y + accel * delta, max_speed)
		super(delta)

	func hit() -> void:
		if not is_queued_for_deletion() and get_parent() != null:
			var e := Explosion.new()
			e.size = 6.0
			e.duration = 0.2
			e.position = position
			get_parent().add_child.call_deferred(e)
		super()

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(-4, -7), Vector2(4, -7), Vector2(0, 8)]), C_ICE)
		draw_line(Vector2(-1, -6), Vector2(0, 4), C_ICE_HI, 1.0)


## FROST BREATH shard: a plain enemy shot drawn as an ice splinter.
class Shard extends "res://scripts/combat/enemy_shot.gd":
	func _draw() -> void:
		var d := velocity.normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([d * 6.0, n * 2.5, -d * 4.0, -n * 2.5]), C_ICE)
		draw_line(-d * 2.0, d * 4.0, C_ICE_HI, 1.0)


## GLACIER WAVE pillar: cracks (harmless), bursts up from the floor, holds, sinks.
class IcePillar extends "res://scripts/level/damage_zone.gd":
	const WARN := 0.32
	const RISE := 0.06
	const HOLD := 0.3
	const SINK := 0.14

	var delay := 0.0
	var height := 34.0
	var _t := 0.0

	func _ready() -> void:
		super()
		damage = 2
		collision_layer = 0
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(12, height)
		cs.shape = rect
		cs.position = Vector2(0, -height / 2.0)
		add_child(cs)

	func is_armed() -> bool:
		var k := _t - delay
		return k >= WARN and k < WARN + RISE + HOLD

	func _physics_process(delta: float) -> void:
		_t += delta
		collision_layer = Layers.HAZARD if is_armed() else 0
		if _t - delay >= WARN + RISE + HOLD + SINK:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := _t - delay
		if k < 0.0:
			return
		if k < WARN:
			var a := 0.35 + 0.65 * k / WARN
			draw_polyline(PackedVector2Array([Vector2(-7, -1), Vector2(-3, -2), Vector2(0, -1), Vector2(4, -3),
					Vector2(7, -1)]), Color(C_ICE, a), 1.5)
			if int(k * 30.0) % 2 == 0:
				draw_rect(Rect2(-1, -4.0 - 4.0 * k / WARN, 2, 2), Color(C_ICE_HI, a))
			return
		var h := height
		if k < WARN + RISE:
			h = height * (k - WARN) / RISE
		elif k > WARN + RISE + HOLD:
			h = height * maxf(1.0 - (k - WARN - RISE - HOLD) / SINK, 0.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(-4, -h * 0.8), Vector2(0, -h),
				Vector2(4, -h * 0.75), Vector2(6, 0)]), C_ICE)
		draw_line(Vector2(-1, -2), Vector2(0, -h + 3.0), C_ICE_HI, 1.0)
