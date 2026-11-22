extends Node
## Debug helper: scripted tour of every screen and system, saving screenshots
## (3x nearest-neighbour) to `out_dir`, then quits. Runs on an in-memory save
## (main turns saving off), so the player's save file is never touched.
## Run: godot --path game -- --autoshot=/absolute/output/dir

const N := "neutral"
const V := "vanguard"
const A := "aero"

var out_dir := ""
var main: Node
## --gallery=<dir>: generic tour of every registered stage instead of the scripted one.
var gallery := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	if gallery:
		_gallery.call_deferred()
	else:
		_tour.call_deferred()


func _p():
	var p = main.player
	p.scripted = true
	p.god_mode = true
	return p


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("autoshot: ", shot_name)


func _release() -> void:
	var p = _p()
	p.in_dir = 0
	p.in_jump = false
	p.in_shoot = false
	p.in_dash = false
	p.in_special = false
	p.in_up = false
	p.in_down = false
	p.in_tag = false


func _teleport(pos: Vector2) -> void:
	_release()
	var p = _p()
	p.global_position = pos
	p.velocity = Vector2.ZERO
	p.reset_physics_interpolation()
	var cam: Camera2D = p.get_viewport().get_camera_2d()
	if cam != null:
		cam.reset_smoothing()
	await _frames(3)


func _equip(h: String, b: String, a: String, l: String) -> void:
	for pair in [["head", h], ["body", b], ["arm", a], ["leg", l]]:
		Game.set_slot(pair[0], pair[1])


## SABLE 3-hit combo: press during the second half of each swing.
func _saber_combo(extra_frames: int) -> void:
	var p = _p()
	p.in_shoot = true
	await _frames(1)
	p.in_shoot = false
	var presses := 1
	for f in 60:
		await _frames(1)
		var a = p.attack
		if presses < 3 and not p.in_shoot and a.swing == presses and a.swing_t > a.swing_len * 0.5:
			p.in_shoot = true
			presses += 1
		else:
			p.in_shoot = false
		if presses == 3 and a.swing == 3 and a.swing_t > a.swing_len * 0.4:
			break
	await _frames(extra_frames if extra_frames < 3 else 0)


func _tour() -> void:
	main.show_title()
	await _frames(20)
	await _shot("01_title")
	main.show_select()
	await _frames(20)
	await _shot("02_stage_select")

	# Training: capsule pickup.
	main.start_stage("training")
	await _frames(30)
	_p().in_dir = 1
	await _frames(40)
	await _shot("03_capsule_pickup")

	# Armor lab with everything unlocked, hybrid loadout.
	Game.unlock_all()
	_equip(V, A, V, A)
	main.open_lab()
	await _frames(20)
	await _shot("04_armor_lab")
	main._close_lab()
	await _frames(5)

	# Hybrid: dash jump + air dash, then flight.
	await _teleport(Vector2(560, 270))
	var p = _p()
	p.set_core(100.0)
	p.in_dir = 1
	p.in_dash = true
	p.in_jump = true
	await _frames(14)
	p.in_dash = false
	await _frames(1)
	p.in_dash = true
	await _frames(4)
	await _shot("05_hybrid_air_dash")
	_release()
	await _frames(30)
	p.in_jump = true
	await _frames(20)
	p.in_jump = false
	await _frames(2)
	p.in_jump = true
	await _frames(14)
	await _shot("06_aero_leg_flight")
	_release()
	await _frames(40)

	# Aero ARM spread charge.
	_equip(A, A, A, N)
	await _teleport(Vector2(600, 270))
	p = _p()
	p.in_shoot = true
	await _frames(85)
	p.in_shoot = false
	await _frames(8)
	await _shot("07_aero_spread_shot")

	# Full Aero: Sky Breaker.
	_equip(A, A, A, A)
	await _teleport(Vector2(1500, 96))
	p = _p()
	p.set_core(100.0)
	p.in_special = true
	await _frames(20)
	await _shot("08_sky_breaker_dive")
	await _frames(12)
	await _shot("09_sky_breaker_waves")
	_release()

	# Full Vanguard: Overdrive Rush; then cracked wall with Vanguard ARM.
	_equip(V, V, V, V)
	await _teleport(Vector2(1660, 270))
	p = _p()
	p.set_core(100.0)
	p.in_special = true
	await _frames(10)
	await _shot("10_overdrive_rush")
	_release()
	await _frames(40)
	await _teleport(Vector2(1760, 270))
	p = _p()
	p.facing = 1
	p.in_shoot = true
	await _frames(40)
	p.in_shoot = false
	await _frames(14)
	await _shot("11_cracked_wall_broken")

	# Party select, tag combo, SABLE.
	Game.set_party(["ix", "sable"])
	main.show_select()
	main._show_party_select("training")
	await _frames(20)
	await _shot("12_party_select")
	main.start_stage("training")
	await _frames(10)
	await _teleport(Vector2(600, 270))
	p = _p()
	p.register_hit()
	p.in_tag = true
	await _frames(6)
	await _shot("13_tag_combo")
	_release()
	p.in_tag = false
	await _frames(40)
	await _saber_combo(10)
	await _shot("14_sable_combo")
	await _frames(30)
	p = _p()
	p.in_special = true
	await _frames(3)
	await _shot("15_sable_parry")
	_release()
	await _frames(20)

	# ECHO: aimed fire, hover, copy -> mini form through the tunnel.
	Game.set_party(["echo", "ix"])
	main.start_stage("training")
	await _frames(10)
	await _teleport(Vector2(600, 270))
	p = _p()
	p.in_up = true
	p.in_dir = 1
	p.in_shoot = true
	await _frames(16)
	await _shot("16_echo_aim_diagonal")
	_release()
	p.in_up = false
	await _frames(20)
	p.in_jump = true
	await _frames(30)
	p.in_jump = false
	await _frames(2)
	p.in_jump = true
	p.in_shoot = true
	await _frames(14)
	await _shot("17_echo_hover")
	_release()
	await _frames(40)
	await _teleport(Vector2(352, 270))
	p = _p()
	p.attack.copy = "mini"
	p.in_special = true
	await _frames(3)
	p.in_special = false
	p.in_dir = 1
	await _frames(45)
	await _shot("18_echo_mini_tunnel")
	_release()

	# IX special weapons.
	Game.set_party(["ix", "echo"])
	main.start_stage("training")
	await _frames(10)
	await _teleport(Vector2(760, 270))
	p = _p()
	p.weapon_index = 1
	for i in 3:
		p.in_shoot = true
		await _frames(2)
		p.in_shoot = false
		await _frames(5)
	await _frames(4)
	await _shot("19_refraction_beam")
	await _frames(40)
	p.weapon_index = 4
	p.facing = -1
	p.in_shoot = true
	await _frames(2)
	p.in_shoot = false
	await _frames(10)
	await _shot("20_freeze_lance")
	await _frames(30)
	p.weapon_index = 6
	p.in_shoot = true
	await _frames(2)
	p.in_shoot = false
	await _frames(12)
	await _shot("21_pulse_ring")
	await _frames(30)
	p.weapon_index = 2
	p.facing = 1
	p.in_shoot = true
	await _frames(2)
	p.in_shoot = false
	await _frames(20)
	await _shot("22_gravity_wing")
	_release()

	# Prism Gecko stage: lasers, fake platforms (revealed by Vanguard HEAD), holograms.
	main.start_stage("prism_gecko")
	await _frames(10)
	await _teleport(Vector2(470, 270))
	await _frames(100)
	await _shot("30_laser_corridor")
	_equip(N, N, N, N)
	await _teleport(Vector2(990, 270))
	await _frames(10)
	await _shot("31_fake_platforms_hidden")
	_equip(V, N, N, N)
	await _frames(5)
	await _shot("32_fake_platforms_revealed")
	await _teleport(Vector2(1530, 270))
	await _frames(30)
	await _shot("33_hologram_platforms")

	# Boss.
	_equip(V, A, V, A)
	await _teleport(Vector2(2300, 270))
	p = _p()
	p.in_dir = 1
	await _frames(90)
	_release()
	await _frames(40)
	await _shot("34_boss_intro")
	for i in 240:
		await _frames(1)
		_p().invuln_timer = 1.0
		if i % 40 == 0:
			_p().in_shoot = not _p().in_shoot
	await _shot("35_boss_fight")
	main.boss.take_damage(17)
	for i in 300:
		await _frames(1)
		_p().invuln_timer = 1.0
		if main.boss.state == 8:  # DECOY
			break
	await _frames(20)
	await _shot("36_boss_phase2")
	main.boss._invuln = 0.0
	main.boss.take_damage(99)
	await _frames(150)
	await _shot("37_mission_complete")
	get_tree().quit()


## Every stage: spawn, each checkpoint, then the boss (and hidden boss) fights.
func _gallery() -> void:
	Game.unlock_all()
	Game.set_party(["ix", "sable"])
	for s in main.stages:
		Game.data["cleared"] = []
		for other in main.stages:
			if other.id != s.id:
				Game.data["cleared"].append(other.id)
		Game.data["cleared"].append("hidden_eclipse")
		main.start_stage(s.id)
		await _frames(25)
		await _shot("%s_0_spawn" % s.id)
		var i := 1
		for cp in main.level.checkpoints:
			await _teleport(cp.global_position + Vector2(-20, -2))
			await _frames(20)
			await _shot("%s_%d_checkpoint" % [s.id, i])
			i += 1
		for kind in ["main", "hidden"]:
			if not main.level.has_arena(kind):
				continue
			if kind == "hidden":
				# Meet the hidden requirement: every stage cleared (+ Eclipse for Λ),
				# but not this hidden boss itself.
				var hid: String = s.get("hidden_id", "")
				Game.data["cleared"] = main.stages.map(func(st): return st.id)
				if hid == "fragment":
					Game.data["cleared"].append("hidden_eclipse")
				main.hud.hide_boss()
			var arena: Rect2 = main.level.arenas[kind].rect
			await _teleport(Vector2(arena.position.x + 48.0, arena.end.y - 2.0))
			main._on_boss_trigger(kind)
			await _frames(110)
			await _shot("%s_%s_boss_a" % [s.id, kind])
			for f in 200:
				await _frames(1)
				if f % 30 == 0:
					_p().in_shoot = not _p().in_shoot
			await _shot("%s_%s_boss_b" % [s.id, kind])
			_release()
			if main.boss != null and is_instance_valid(main.boss):
				main.boss.queue_free()
			main.boss = null
			main._in_boss = false
			await _frames(5)
	get_tree().quit()

