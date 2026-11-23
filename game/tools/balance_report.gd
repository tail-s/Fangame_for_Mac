extends SceneTree
## Boss balance report: fights every boss headlessly with a simple scripted bot
## and writes markdown tables (time to kill, damage taken, how often the boss can
## be hit, which attacks connect).
##
## Run:
##   godot --headless --fixed-fps 60 --path game -s res://tools/balance_report.gd -- --out=/abs/report.md
## Options (after `--`):
##   --out=PATH        markdown report (default: print to stdout)
##   --json=PATH       also write the summary numbers as JSON (for --before)
##   --before=PATH     JSON from an earlier run: adds a before / after table
##   --seeds=N         runs per boss and mode (default 3)
##   --only=a,b        boss ids (prism_gecko, ..., eclipse, fragment, arca)
##   --max-time=S      give up on a fight after S seconds (default 300)
##   --react=X         bot reaction chance per threat (default 0.7; 1.0 = never ignores one)
##   --debug=N         print the bot / boss state every N frames
##   --trace-hits=1    print every hit the player takes, with the bot's last dodge
##
## The bot (class Bot below) is deliberately simple and imperfect: it keeps a
## shooting distance, turns to face the boss, jump-shoots bosses that hover at
## jump height, climbs arena ledges when the boss stays above floor reach,
## and dodges (jump over low shots / charges, dash out from under shots from
## above, telegraphed columns and laser sweeps) but only reacts to ~70% of
## threats. Boss patterns and the bot are seeded, so a run is deterministic.
##
## The player has 100000 HP instead of god mode: damage still triggers the real
## hurt / knockback / 1 s i-frames, so "damage per minute" is what a normal
## difficulty player (x1.0, neutral armor, base HP 16) would have taken.

const Level = preload("res://scripts/level/level.gd")
const Player = preload("res://scripts/player/player.gd")
const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")
const EnemyShot = preload("res://scripts/combat/enemy_shot.gd")
const PrismOrb = preload("res://scripts/combat/prism_orb.gd")
const DamageZone = preload("res://scripts/level/damage_zone.gd")
const GameScript = preload("res://scripts/autoload/game.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")

const FPS := 60.0
const BIG_HP := 100000
const MODES := ["tap", "charge", "weak"]
const MODE_NAME := {"tap": "buster tap spam", "charge": "buster full charge", "weak": "weakness weapon"}

## Targets (task brief): buster TTK 60-120 s, weakness 30-60% of it, survive
## >= 1.5x the buster TTK on base HP (hidden bosses / ARCA may be ~30% harder).
const TTK_MIN := 60.0
const TTK_MAX := 120.0
const WEAK_MIN := 0.30
const WEAK_MAX := 0.60
const SURVIVE_MULT := 1.5
const HARD_SLACK := 1.3

var _opts := {}
var _results: Array = []  # one Dictionary per boss
var _shot_names := {}


func _initialize() -> void:
	InputSetup.register()
	_run.call_deferred()


func _run() -> void:
	_parse_args()
	var game = root.get_node_or_null("Game")
	if game != null:
		game.save_enabled = false
		game.silent = true
		game.apply_settings()
	var seeds: int = int(_opts.get("seeds", "3"))
	var max_time: float = float(_opts.get("max-time", "300"))
	var only: Array = []
	if _opts.has("only"):
		only = str(_opts.only).split(",")
	for entry in _boss_entries():
		if not only.is_empty() and not only.has(entry.id):
			continue
		var res := {"entry": entry, "modes": {}, "stat": {}}
		for mode in MODES:
			if mode == "weak" and entry.weakness == "":
				continue
			var runs: Array = []
			for s in seeds:
				var r: Dictionary = await _fight(entry, mode, 1000 + s * 37, max_time)
				runs.append(r)
				printerr("  %-18s %-6s seed %d: %s %.1f s, took %d dmg (%d hits), %.0f%% vulnerable" % [entry.id, mode, s,
						"killed in" if r.killed else "NOT killed after", r.ttk, r.damage, r.hits, r.vuln * 100.0])
				if res.stat.is_empty():
					res.stat = r.stat
			res.modes[mode] = runs
		_results.append(res)
	var md := _report()
	if _opts.has("out"):
		var f := FileAccess.open(str(_opts.out), FileAccess.WRITE)
		f.store_string(md)
		f.close()
		printerr("wrote ", _opts.out)
	else:
		print(md)
	if _opts.has("json"):
		var f := FileAccess.open(str(_opts.json), FileAccess.WRITE)
		f.store_string(JSON.stringify(_summary_json(), "\t"))
		f.close()
		printerr("wrote ", _opts.json)
	quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1]


# --- boss list ------------------------------------------------------------------------

## Main bosses in stage order, then the hidden bosses, then the final boss.
func _boss_entries() -> Array:
	var mains: Array = []
	var hidden: Array = []
	var final: Array = []
	for meta in Level.load_registry("res://levels"):
		if meta.has("boss"):
			var e := {"id": meta.id, "stage": meta.id, "path": meta.path, "kind": "main", "script": meta.boss,
					"tier": "main", "desc_weak": _weak_from_desc(str(meta.get("desc", ""))),
					"stage_name": str(meta.get("name", meta.id))}
			if meta.get("final", "") == "true":
				e.id = "arca"
				e.tier = "final"
				final.append(e)
			else:
				mains.append(e)
		if meta.has("hidden_boss"):
			hidden.append({"id": meta.get("hidden_id", meta.id + "_hidden"), "stage": meta.id, "path": meta.path,
					"kind": "hidden", "script": meta.hidden_boss, "tier": "hidden", "desc_weak": "",
					"stage_name": str(meta.get("hidden_id", meta.id)).to_upper()})
	hidden.sort_custom(func(a, b) -> bool: return a.id < b.id)  # eclipse before fragment
	var out: Array = mains + hidden + final
	for e in out:
		var b = load(e.script).new()
		e["name"] = str(b.get("boss_name")) if b.get("boss_name") != null else e.stage_name
		e["weakness"] = _boss_const(b, "weakness", "WEAKNESS", "")
		b.free()
	return out


## "광학 데이터 보관소 · 약점 PULSE RING" -> "pulse_ring".
func _weak_from_desc(desc: String) -> String:
	var i := desc.find("약점 ")
	if i < 0:
		return ""
	var label := desc.substr(i + 3).strip_edges()
	for id in WeaponShot.ORDER:
		if WeaponShot.INFO[id].name == label:
			return id
	return "?" + label


## A tunable from boss_base (`var_name`) or the stand-alone Prism Gecko (`const_name`).
func _boss_const(b, var_name: String, const_name: String, fallback):
	var v = b.get(var_name)
	if v != null:
		return v
	var consts: Dictionary = b.get_script().get_script_constant_map()
	return consts.get(const_name, fallback)


# --- one fight ------------------------------------------------------------------------

func _fight(entry: Dictionary, mode: String, seed_value: int, max_time: float) -> Dictionary:
	seed(seed_value)
	var lv = Level.new()
	lv.stage_id = entry.stage
	root.add_child(lv)
	lv.load_from_file(entry.path)
	var info: Dictionary = lv.arenas[entry.kind]
	var arena: Rect2 = info.rect
	var p = Player.new()
	p.scripted = true
	p.position = Vector2(arena.position.x + 40.0, arena.end.y - 1.0)
	lv.add_child(p)
	p.env = lv
	p.setup_party(["ix"], BIG_HP)
	p.damage_taken_mult = 1.0
	p.kill_y = lv.pixel_size().y + 48.0
	if mode == "weak":
		p.weapons = ["buster", entry.weakness]
		p.weapon_index = 1
	lv.close_door(entry.kind)
	var b = load(entry.script).new()
	b.arena = arena
	b.position = info.spawn
	b.player = p
	lv.add_actor(b)
	b._rng.seed = seed_value * 7919 + 17

	var bot := Bot.new()
	bot.react_chance = float(_opts.get("react", "0.7"))
	bot.setup(p, b, lv, arena, mode, entry.weakness if mode == "weak" else "", seed_value)
	var stat := _static_numbers(b)
	var state_names := _state_names(b)
	var initial_zones := {}
	for z in get_nodes_in_group("damaging"):
		initial_zones[z.get_instance_id()] = true
	bot.ignore_zones = initial_zones

	var frame := 0
	var active_frames := 0
	var vuln_frames := 0
	var reach_frames := 0
	var last_hp: int = p.hp
	var pending := ""
	var damage := 0
	var hits := 0
	var by_attack := {}  # label -> {"hits", "damage"}
	var spawned := {}  # instance id -> true
	var attacks := {}  # label -> {"damage": int, "count": int}
	var deaths := 0
	var killed := false
	var dry_at := -1.0
	var boss_hp0: int = b.get_max_hp()
	var hp_left := boss_hp0
	var max_frames := int(max_time * FPS)
	while frame < max_frames + 600:
		await physics_frame
		frame += 1
		# Damage that landed during the previous tick.
		if p.hp < last_hp:
			var lost: int = last_hp - p.hp
			damage += lost
			hits += 1
			var label := pending if pending != "" else "other"
			if not by_attack.has(label):
				by_attack[label] = {"hits": 0, "damage": 0}
			by_attack[label].hits += 1
			by_attack[label].damage += lost
			if _opts.has("trace-hits"):
				printerr("    HIT t=%.2f %s -%d p=%s v=%s floor=%s state=%s boss=%s last=%s" % [frame / FPS, label, lost,
						str(p.global_position.round()), str(p.velocity.round()), p.is_on_floor(), p.state_name(),
						str(b.global_position.round()) if is_instance_valid(b) else "-", bot.last_action])
		if p.state == Player.State.DEAD:
			deaths += 1
			_revive(p, arena)
		last_hp = p.hp
		if not is_instance_valid(b):
			killed = true
			break
		hp_left = b.hp
		if hp_left <= 0:
			killed = true
			break
		var is_active := _is_active(b)
		if is_active:
			active_frames += 1
			if active_frames > max_frames:
				break
			if bot.boss_vulnerable():
				vuln_frames += 1
				if bot.in_reach(b):
					reach_frames += 1
		var sname: String = state_names.get(b.get("state"), str(b.get("state")))
		_note_spawns(b, sname, spawned, attacks, initial_zones)
		pending = _predict_source(p, b, sname)
		bot.tick(frame, is_active)
		if _opts.has("debug") and frame % int(_opts.debug) == 0:
			printerr("    t=%5.1f p=%s on_floor=%s ledge=%d h_avg=%.0f boss=%s hp=%d state=%s vuln=%s jump=%s shoot=%s dir=%d ledges=%s" % [
					frame / FPS, str(p.global_position.round()), p.is_on_floor(), bot._ledge, bot._h_avg,
					str(b.global_position.round()), b.hp, sname, bot.boss_vulnerable(), p.in_jump, p.in_shoot, p.in_dir, str(bot.ledges)])
		if dry_at < 0.0 and bot.dry:
			dry_at = active_frames / FPS
	var ttk := active_frames / FPS
	var out := {"killed": killed, "ttk": ttk, "damage": damage, "hits": hits, "deaths": deaths,
			"vuln": float(vuln_frames) / maxf(active_frames, 1), "reach": float(reach_frames) / maxf(active_frames, 1),
			"by_attack": by_attack, "attacks": attacks, "stat": stat, "dry_at": dry_at,
			"hp_left": hp_left, "hp_max": boss_hp0, "minutes": maxf(active_frames, 1) / FPS / 60.0}
	for s in get_nodes_in_group("enemy_shot"):
		s.queue_free()
	for s in get_nodes_in_group("player_shot"):
		s.queue_free()
	for s in get_nodes_in_group("weapon_shot"):
		s.queue_free()
	lv.queue_free()
	await process_frame
	await physics_frame
	return out


func _revive(p, arena: Rect2) -> void:
	p.state = Player.State.NORMAL
	p.hp = BIG_HP
	p.party[0].hp = BIG_HP
	p.velocity = Vector2.ZERO
	p.position = Vector2(arena.get_center().x, arena.end.y - 1.0)
	p.invuln_timer = 1.0
	p.visual.visible = true


func _is_active(b) -> bool:
	var a = b.get("active")
	if a != null:
		return a and b.hp > 0
	return b.state != 0 and b.hp > 0  # Prism Gecko: S.INTRO == 0


func _state_names(b) -> Dictionary:
	var out := {}
	var consts: Dictionary = b.get_script().get_script_constant_map()
	if consts.has("S"):
		for k in consts.S:
			out[consts.S[k]] = k
	return out


## Which attack is about to hurt the player this tick. Mirrors player.gd
## _check_damage() (same overlaps, same priority) and runs before it.
func _predict_source(p, b, sname: String) -> String:
	for area in p.hurtbox.get_overlapping_areas():
		if area.is_in_group("hazard"):
			return "hazard (instant death)"
		if area.is_in_group("damaging"):
			return "%s @ %s" % [_node_kind(area, b), sname]
		if area.is_in_group("enemy_shot"):
			return "%s @ %s" % [_node_kind(area, b), sname]
	for body in p.hurtbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and not body.is_queued_for_deletion() and body.get_contact_damage() > 0:
			return "contact @ %s" % sname
	return ""


## Class name of a shot / zone: plain EnemyShot, PrismOrb, DamageZone or a boss inner class.
func _node_kind(n: Node, b) -> String:
	var s = n.get_script()
	if s == null:
		return n.get_class()
	if _shot_names.has(s):
		return _shot_names[s]
	var label := "?"
	if s == EnemyShot:
		label = "EnemyShot"
	elif s == PrismOrb:
		label = "PrismOrb"
	elif s == DamageZone:
		label = "DamageZone"
	elif is_instance_valid(b):
		var consts: Dictionary = b.get_script().get_script_constant_map()
		for k in consts:
			if typeof(consts[k]) == TYPE_OBJECT and consts[k] == s:
				label = k
				break
	if label == "?" and s.resource_path != "":
		label = s.resource_path.get_file().get_basename()
	_shot_names[s] = label
	return label


## First sighting of each boss shot / zone: remember its damage by attack.
func _note_spawns(b, sname: String, spawned: Dictionary, attacks: Dictionary, ignore: Dictionary) -> void:
	var nodes: Array = get_nodes_in_group("enemy_shot") + get_nodes_in_group("damaging")
	for n in nodes:
		var id: int = n.get_instance_id()
		if spawned.has(id) or ignore.has(id):
			continue
		spawned[id] = true
		var label := "%s @ %s" % [_node_kind(n, b), sname]
		var dmg = n.get("damage")
		if not attacks.has(label):
			attacks[label] = {"damage": dmg, "count": 0}
		attacks[label].count += 1
	var contact := "contact @ %s" % sname
	if b.get_contact_damage() > 0 and not attacks.has(contact):
		attacks[contact] = {"damage": b.get_contact_damage(), "count": 0}


func _static_numbers(b) -> Dictionary:
	return {
		"hp": b.get_max_hp(),
		"weakness": _boss_const(b, "weakness", "WEAKNESS", ""),
		"weak_mult": _boss_const(b, "weak_mult", "WEAK_MULT", 0.0),
		"stagger_cd": _boss_const(b, "stagger_cooldown", "STAGGER_COOLDOWN", 0.0),
		"contact": b.get("contact_damage"),
		"radius": b.get("hit_radius") if b.get("hit_radius") != null else 10.0,
	}


# --- report ------------------------------------------------------------------------------

func _mean(runs: Array, key: String) -> float:
	var s := 0.0
	for r in runs:
		s += float(r[key])
	return s / maxf(runs.size(), 1)


func _dpm(runs: Array) -> float:
	var dmg := 0.0
	var mins := 0.0
	for r in runs:
		dmg += r.damage
		mins += r.minutes
	return dmg / maxf(mins, 0.0001)


func _hpm(runs: Array) -> float:
	var n := 0.0
	var mins := 0.0
	for r in runs:
		n += r.hits
		mins += r.minutes
	return n / maxf(mins, 0.0001)


func _all_killed(runs: Array) -> bool:
	for r in runs:
		if not r.killed:
			return false
	return true


func _ttk_text(runs: Array) -> String:
	var lo := INF
	var hi := 0.0
	for r in runs:
		lo = minf(lo, r.ttk)
		hi = maxf(hi, r.ttk)
	var t := "%.0f s (%.0f–%.0f)" % [_mean(runs, "ttk"), lo, hi]
	if not _all_killed(runs):
		t += " ⚠ %d/%d not killed" % [runs.filter(func(r) -> bool: return not r.killed).size(), runs.size()]
	return t


## Per boss: headline numbers used by the summary and the JSON.
func _summary_row(res: Dictionary) -> Dictionary:
	var m: Dictionary = res.modes
	var tap: float = _mean(m.tap, "ttk")
	var charge: float = _mean(m.charge, "ttk")
	var buster := minf(tap, charge)
	var weak := -1.0
	if m.has("weak"):
		weak = _mean(m.weak, "ttk")
	var buster_runs: Array = m.tap + m.charge
	var dpm := _dpm(buster_runs)
	var base_hp: int = GameScript.BASE_HP
	var survive := INF if dpm <= 0.0 else base_hp / dpm * 60.0
	return {"id": res.entry.id, "name": res.entry.name, "tier": res.entry.tier, "hp": res.stat.hp,
			"tap": tap, "charge": charge, "buster": buster, "weak": weak,
			"ratio": weak / buster if weak > 0.0 else -1.0, "dpm": dpm, "hpm": _hpm(buster_runs),
			"survive": survive, "vuln": _mean(buster_runs, "vuln"), "reach": _mean(buster_runs, "reach"),
			"killed": _all_killed(buster_runs) and (not m.has("weak") or _all_killed(m.weak))}


func _verdicts(row: Dictionary) -> Array:
	var out: Array = []
	var slack: float = 1.0 if row.tier == "main" else HARD_SLACK
	if row.buster < TTK_MIN:
		out.append("buster TTK short (<%d s)" % TTK_MIN)
	elif row.buster > TTK_MAX * slack:
		out.append("buster TTK long (>%d s)" % int(TTK_MAX * slack))
	if row.ratio > 0.0:
		if row.ratio < WEAK_MIN:
			out.append("weakness too strong (<%d%%)" % int(WEAK_MIN * 100))
		elif row.ratio > WEAK_MAX:
			out.append("weakness too weak (>%d%%)" % int(WEAK_MAX * 100))
	var need: float = SURVIVE_MULT * row.buster / slack
	if row.survive < need:
		out.append("too much damage (survive %.0f s < %.0f s)" % [row.survive, need])
	return out


func _summary_json() -> Dictionary:
	var rows := {}
	for res in _results:
		rows[res.entry.id] = _summary_row(res)
	return {"seeds": int(_opts.get("seeds", "3")), "rows": rows}


func _report() -> String:
	var L: PackedStringArray = []
	L.append("# Boss balance report")
	L.append("")
	L.append("Generated by `game/tools/balance_report.gd` (%d seeded runs per boss and mode, bot described in the script header)." % int(_opts.get("seeds", "3")))
	L.append("TTK is measured from the end of the boss intro to the killing blow. Damage is what the bot")
	L.append("took on **normal** difficulty with the neutral armor (real hurt / knockback / i-frames, the")
	L.append("player just has enough HP not to die). *Survive* = seconds a base-HP (%d) player lasts at that rate." % GameScript.BASE_HP)
	L.append("")
	L.append_array(_summary_lines())
	if _opts.has("before"):
		L.append_array(_before_after_lines(str(_opts.before)))
	L.append_array(_static_lines())
	for res in _results:
		L.append_array(_boss_lines(res))
	return "\n".join(L) + "\n"


func _summary_lines() -> PackedStringArray:
	var L: PackedStringArray = []
	L.append("## Summary")
	L.append("")
	L.append("Targets: buster TTK %d–%d s (main bosses; hidden / ARCA up to ~30%% harder), weakness TTK %d–%d%% of the buster TTK," % [TTK_MIN, TTK_MAX, WEAK_MIN * 100, WEAK_MAX * 100])
	L.append("survive ≥ %.1f× the buster TTK on base HP. *Buster* = the faster of tap spam and full charges." % SURVIVE_MULT)
	L.append("")
	L.append("| boss | HP | buster TTK (tap / charge) | weakness TTK | weak ÷ buster | dmg taken /min | hits /min | survive (16 HP) | vulnerable | in reach | flags |")
	L.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
	for res in _results:
		var r := _summary_row(res)
		var weak := "—" if r.weak < 0.0 else "%.0f s" % r.weak
		var ratio := "—" if r.ratio < 0.0 else "%.0f%%" % (r.ratio * 100.0)
		var flags := _verdicts(r)
		if not r.killed:
			flags.push_front("timeouts")
		L.append("| %s | %d | **%.0f s** (%.0f / %.0f) | %s | %s | %.1f | %.1f | %s | %.0f%% | %.0f%% | %s |" % [
				r.name, r.hp, r.buster, r.tap, r.charge, weak, ratio, r.dpm, r.hpm,
				"∞" if r.survive == INF else "%.0f s" % r.survive, r.vuln * 100.0, r.reach * 100.0,
				"ok" if flags.is_empty() else ", ".join(flags)])
	L.append("")
	return L


func _before_after_lines(path: String) -> PackedStringArray:
	var L: PackedStringArray = []
	if not FileAccess.file_exists(path):
		return L
	var before = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(before) != TYPE_DICTIONARY or not before.has("rows"):
		return L
	L.append("## Before / after tuning")
	L.append("")
	L.append("| boss | HP | buster TTK | weakness TTK | weak ÷ buster | dmg taken /min | survive (16 HP) |")
	L.append("|---|---:|---:|---:|---:|---:|---:|")
	for res in _results:
		var a := _summary_row(res)
		var b0 = before.rows.get(a.id)
		if b0 == null:
			continue
		var fmt := func(x: float, unit: String) -> String:
			return "—" if x < 0.0 else ("%.0f%s" % [x, unit])
		L.append("| %s | %d → %d | %s → **%s** | %s → **%s** | %s → **%s** | %.1f → **%.1f** | %s → **%s** |" % [
				a.name, int(b0.hp), a.hp,
				fmt.call(float(b0.buster), " s"), fmt.call(a.buster, " s"),
				fmt.call(float(b0.weak), " s"), fmt.call(a.weak, " s"),
				fmt.call(float(b0.ratio) * 100.0 if float(b0.ratio) > 0.0 else -1.0, "%"),
				fmt.call(a.ratio * 100.0 if a.ratio > 0.0 else -1.0, "%"),
				float(b0.dpm), a.dpm,
				"∞" if b0.survive == null or float(b0.survive) > 1e9 else "%.0f s" % float(b0.survive),
				"∞" if a.survive == INF else "%.0f s" % a.survive])
	L.append("")
	return L


func _static_lines() -> PackedStringArray:
	var L: PackedStringArray = []
	L.append("## Static numbers")
	L.append("")
	var hpups := _count_hp_ups()
	L.append("- Player HP: base %d (`Game.BASE_HP`), +2 per HP-up (`main.gd` → `Game.add_hp_bonus(2)`); %d HP-ups in the stage files → max %d." % [
			GameScript.BASE_HP, hpups, GameScript.BASE_HP + 2 * hpups])
	var pl = Player.new()
	L.append("- Player i-frames after a hit: %.2f s (hurt stun %.2f s). Neutral armor: no air / dash damage reduction." % [pl.invuln_time, pl.hurt_time])
	pl.free()
	var diffs: PackedStringArray = []
	for d in GameScript.DIFFICULTIES:
		diffs.append("%s ×%.1f" % [d, GameScript.DIFFICULTY_DAMAGE[d]])
	L.append("- Damage taken by difficulty (`Game.DIFFICULTY_DAMAGE`): %s (rounded up, min 1)." % ", ".join(diffs))
	L.append("- Buster: tap 1 (max 3 on screen), mid charge 2 (≥0.45 s), full charge 4 (≥1.3 s, pierces on kill). Boss flicker after any hit: 0.08 s.")
	var wl: PackedStringArray = []
	for id in WeaponShot.ORDER:
		var w = WeaponShot.new()
		w.setup(id, 1, null)
		wl.append("%s %d (cost %.0f/%.0f, max %d)" % [WeaponShot.INFO[id].name, w.damage, WeaponShot.INFO[id].cost, WeaponShot.MAX_ENERGY, WeaponShot.INFO[id].max])
		w.free()
	L.append("- Special weapons (damage, energy cost): %s. Weakness hits deal ×weak_mult (rounded up)." % "; ".join(wl))
	L.append("")
	L.append("| boss | HP | weakness | weak × | stagger cd | contact dmg | hit radius |")
	L.append("|---|---:|---|---:|---:|---:|---:|")
	for res in _results:
		var s: Dictionary = res.stat
		var weak := "—" if str(s.weakness) == "" else str(s.weakness)
		if res.entry.desc_weak != "" and res.entry.desc_weak != s.weakness:
			weak += " ⚠ stage @desc says %s" % res.entry.desc_weak
		L.append("| %s | %d | %s | %s | %s | %s | %.0f |" % [res.entry.name, s.hp, weak,
				"—" if weak == "—" else "%.1f" % s.weak_mult, "—" if weak == "—" else "%.1f s" % s.stagger_cd,
				str(s.contact), s.radius])
	L.append("")
	return L


func _count_hp_ups() -> int:
	var n := 0
	for meta in Level.load_registry("res://levels"):
		var alts := {}
		var text := FileAccess.get_file_as_string(meta.path)
		for line in text.split("\n"):
			if line.begins_with("; @alt "):
				var parts := line.substr(7).split(" ", false)
				if parts.size() >= 4 and parts[3] == "+":
					alts[parts[0]] = true
		for line in text.split("\n"):
			if line.begins_with(";"):
				continue
			n += line.count("+")
			for ch in alts:
				n += line.count(ch)
	return n


func _boss_lines(res: Dictionary) -> PackedStringArray:
	var L: PackedStringArray = []
	var e: Dictionary = res.entry
	L.append("## %s (%s, %s)" % [e.name, e.stage, e.tier])
	L.append("")
	L.append("| mode | TTK mean (min–max) | dmg taken /min | hits taken /min | vulnerable | in reach | notes |")
	L.append("|---|---:|---:|---:|---:|---:|---|")
	for mode in MODES:
		if not res.modes.has(mode):
			continue
		var runs: Array = res.modes[mode]
		var notes: PackedStringArray = []
		var dry := runs.filter(func(r) -> bool: return r.dry_at >= 0.0)
		if not dry.is_empty():
			notes.append("weapon energy ran out in %d/%d runs (≈%.0f s in), finished with the charged buster" % [dry.size(), runs.size(), _mean(dry, "dry_at")])
		var deaths := 0
		for r in runs:
			deaths += r.deaths
		if deaths > 0:
			notes.append("%d instant deaths (pits / spikes)" % deaths)
		for r in runs:
			if not r.killed:
				notes.append("timeout with %d/%d HP left" % [r.hp_left, r.hp_max])
		var label: String = MODE_NAME[mode]
		if mode == "weak":
			label += " (%s)" % e.weakness
		L.append("| %s | %s | %.1f | %.1f | %.0f%% | %.0f%% | %s |" % [label, _ttk_text(runs), _dpm(runs), _hpm(runs),
				_mean(runs, "vuln") * 100.0, _mean(runs, "reach") * 100.0, "; ".join(notes)])
	L.append("")
	# Attack breakdown over the buster runs.
	var runs: Array = res.modes.tap + res.modes.charge
	var total := 0.0
	var mins := 0.0
	var agg := {}
	var dmg_of := {}
	for r in runs:
		total += r.damage
		mins += r.minutes
		for k in r.by_attack:
			if not agg.has(k):
				agg[k] = {"hits": 0, "damage": 0}
			agg[k].hits += r.by_attack[k].hits
			agg[k].damage += r.by_attack[k].damage
		for k in r.attacks:
			dmg_of[k] = r.attacks[k].damage
	var keys: Array = agg.keys()
	keys.sort_custom(func(a, b) -> bool: return agg[a].damage > agg[b].damage)
	L.append("Attacks that connected (buster runs, %.1f min in total):" % mins)
	L.append("")
	L.append("| attack (source @ boss state) | dmg per hit | hits | hits /min | share of damage |")
	L.append("|---|---:|---:|---:|---:|")
	for k in keys:
		var per = dmg_of.get(k, "%.1f" % (float(agg[k].damage) / maxi(agg[k].hits, 1)))
		L.append("| %s | %s | %d | %.2f | %.0f%% |" % [k, str(per), agg[k].hits, agg[k].hits / maxf(mins, 0.0001),
				100.0 * agg[k].damage / maxf(total, 1.0)])
	# Attacks seen but never landing.
	var unseen: PackedStringArray = []
	var seen := {}
	for r in runs:
		for k in r.attacks:
			seen[k] = r.attacks[k].damage
	for k in seen:
		if not agg.has(k):
			unseen.append("%s (%s)" % [k, str(seen[k])])
	unseen.sort()
	if not unseen.is_empty():
		L.append("")
		L.append("Also seen, never connected: %s." % ", ".join(unseen))
	L.append("")
	return L


# --- the bot ---------------------------------------------------------------------------------

class Bot:
	## Chance to react to any one threat (--react=X overrides, e.g. 1.0 for a perfect dodger).
	var react_chance := 0.7
	const TAP_PERIOD := 8  # frames between trigger presses (7.5 / s)
	## Weapon models: shot line offset from the feet, half height, horizontal range,
	## preferred distance band, radial (Pulse Ring hits around the player).
	const WEAPONS := {
		"buster": {"oy": -15.0, "half": 2.0, "range": 400.0, "band": [56.0, 150.0]},
		"buster_full": {"oy": -15.0, "half": 7.0, "range": 400.0, "band": [56.0, 150.0]},
		"refraction_beam": {"oy": -15.0, "half": 3.0, "range": 400.0, "band": [56.0, 150.0]},
		"freeze_lance": {"oy": -15.0, "half": 3.0, "range": 400.0, "band": [56.0, 150.0]},
		"gravity_wing": {"oy": -15.0, "half": 10.0, "range": 160.0, "band": [40.0, 130.0]},
		"heat_mirage": {"oy": -11.0, "half": 9.0, "range": 160.0, "band": [40.0, 130.0]},
		"core_drill": {"oy": -15.0, "half": 5.0, "range": 110.0, "band": [30.0, 90.0]},
		"pulse_ring": {"oy": -14.0, "half": 48.0, "range": 52.0, "band": [0.0, 34.0], "radial": true},
	}

	var p
	var b
	var lv
	var arena := Rect2()
	var mode := "tap"
	var weak := ""
	var dry := false
	var ignore_zones := {}
	var rng := RandomNumberGenerator.new()
	var floor_y := 0.0
	var ledges: Array = []  # Rect2: x span and top y (height 0)
	var _decided := {}
	var _prev_pos := {}
	var _dodge_dir := 0
	var _dodge_frames := 0
	var _jump_frames := 0
	var _jump_req := false
	var _aim_jump := false
	var _h_avg := 0.0
	var _ledge := -1
	var _ledge_clock := 0.0
	var _boss_prev := Vector2.ZERO
	var _boss_episode := 0
	var _boss_calm := 0
	var _col_epoch := 0
	var _dash_req := false
	## Last dodge decision and when (for --trace-hits).
	var last_action := ""
	var _frame := 0
	var _ledge_block := 0.0
	var _had_columns := false

	func setup(player, boss, level, rect: Rect2, m: String, weapon: String, s: int) -> void:
		p = player
		b = boss
		lv = level
		arena = rect
		mode = m
		weak = weapon
		rng.seed = s * 31 + 7
		floor_y = arena.end.y
		_find_ledges()
		_boss_prev = b.global_position

	## Solid tiles inside the arena with an empty tile above: ledges to stand on.
	func _find_ledges() -> void:
		var t := 16
		var x0 := int(arena.position.x / t)
		var x1 := int(arena.end.x / t)
		var y0 := int(arena.position.y / t)
		var y1 := int(arena.end.y / t)
		for cy in range(y0 + 1, y1):
			var run_start := -1
			for cx in range(x0, x1 + 1):
				var top: bool = cx < x1 and lv.is_solid(cx, cy) and not lv.is_solid(cx, cy - 1)
				if top and run_start < 0:
					run_start = cx
				elif not top and run_start >= 0:
					ledges.append(Rect2(run_start * t, cy * t, (cx - run_start) * t, 0))
					run_start = -1

	func _radius() -> float:
		var r = b.get("hit_radius")
		return 10.0 if r == null else float(r)

	func _weapon() -> String:
		if mode == "weak" and not dry:
			return weak
		if mode == "tap":
			return "buster"
		return "buster_full"

	## Damage would land right now (not counting the 0.08 s post-hit flicker):
	## Terra Pangolin not curled / underground, Fragment core open, ARCA shield open.
	func boss_vulnerable() -> bool:
		if b.has_method("is_vulnerable"):
			return b.is_vulnerable()
		if b.get("core_open") != null:
			return b.core_open
		if b.has_method("shield_solid"):
			return not b.shield_solid()
		return true

	## The boss can be hit by a buster shot from the floor or a ledge (standing or jumping).
	func in_reach(boss) -> bool:
		var y: float = boss.global_position.y
		var r := _radius()
		if not arena.grow(4.0).has_point(boss.global_position):
			return false
		var surfaces: Array = [floor_y]
		for l in ledges:
			surfaces.append(l.position.y)
		for s in surfaces:
			var top: float = s - 15.0 - 63.0 - r
			var bottom: float = s - 15.0 + r
			if y >= top and y <= bottom:
				return true
		return false

	func tick(frame: int, boss_active: bool) -> void:
		_frame = frame
		var feet: Vector2 = p.global_position
		var body_c := feet + Vector2(0, -13)
		var on_floor: bool = p.is_on_floor()
		var tgt: Vector2 = b.global_position
		var r := _radius()
		var dx := tgt.x - feet.x
		var sdx := 1 if dx >= 0.0 else -1
		var boss_vel := (tgt - _boss_prev) * 60.0
		_boss_prev = tgt
		var w := _weapon()
		var spec: Dictionary = WEAPONS[w]
		var vuln := boss_active and boss_vulnerable()
		var surface := _surface_y(feet, on_floor)

		# Weakness weapon energy.
		if mode == "weak" and not dry:
			if p.weapon_energy[weak] < WeaponShot.INFO[weak].cost:
				dry = true
				p.weapon_index = 0
				w = _weapon()
				spec = WEAPONS[w]

		# Ledges: climb one when the boss stays above floor reach.
		_h_avg = lerpf(_h_avg, floor_y - tgt.y, 1.0 / 90.0)
		_ledge_clock -= 1.0 / 60.0
		_ledge_block -= 1.0 / 60.0
		if _ledge_block > 0.0:
			_ledge = -1
		elif not ledges.is_empty() and _ledge_clock <= 0.0:
			_ledge_clock = 1.0
			if _h_avg - r > 62.0:
				if _ledge < 0:
					_ledge = _nearest_ledge(feet.x)
			elif _h_avg - r < 45.0:
				_ledge = -1

		# Threats.
		var react := _threats(frame, body_c, feet, on_floor, tgt, boss_vel, r)
		if react == "jump":
			last_action = "jump %.2f" % (frame / 60.0)
		var dir := 0
		if _dodge_frames > 0:
			_dodge_frames -= 1
			dir = _dodge_dir
		elif _ledge >= 0:
			dir = _ledge_nav(feet, on_floor)
		else:
			var band: Array = spec.band
			var adx := absf(dx)
			var boss_low := tgt.y > feet.y - 95.0  # within reach of a jumping body
			if adx > band[1]:
				dir = sdx
			elif adx < band[0] and boss_low:
				dir = -sdx
				if (dir < 0 and feet.x < arena.position.x + 20.0) or (dir > 0 and feet.x > arena.end.x - 20.0):
					dir = 0
		# Turn to face the boss when standing still.
		if dir == 0 and sdx != p.facing and absf(dx) > 4.0:
			dir = sdx
		if _ledge >= 0 and _on_ledge(feet, on_floor):
			var l: Rect2 = ledges[_ledge]
			var nx: float = feet.x + dir * 3.0
			if nx < l.position.x + 7.0 or nx > l.end.x - 7.0:
				if sdx != p.facing and dir == sdx:
					pass  # a one-frame turn moves 1.5 px, allowed
				else:
					dir = 0

		# Aiming.
		var oy: float = spec.oy
		var half: float = spec.half
		var reach: float = spec.range
		var radial: bool = spec.get("radial", false)
		var line_y: float = feet.y + oy
		var aligned := false
		if radial:
			aligned = (tgt - (feet + Vector2(0, oy))).length() <= reach + r
		else:
			aligned = absf(line_y - tgt.y) <= r + half - 1.0 and absf(dx) <= reach
		var facing_ok: bool = sdx == p.facing or absf(dx) < 4.0 or radial

		# Jump shots: the boss is above the standing shot line but within a jump.
		var stand_line: float = surface + oy
		var rise: float = stand_line - (tgt.y + r + half - 3.0)
		var wants_shot: bool = mode != "charge" or p.charge_level() == 2 or (mode == "weak" and not dry)
		if mode == "weak" and dry:
			wants_shot = p.charge_level() == 2
		if vuln and wants_shot and rise > 0.0 and rise < 66.0 and on_floor and _jump_frames <= 0 \
				and absf(dx) > r + 24.0 \
				and not _jump_req and absf(dx) <= reach + 40.0 and _dodge_frames <= 0:
			_jump_req = true
			_aim_jump = true
		if react == "jump":
			_jump_req = true
			_aim_jump = false

		# Jump input (needs a fresh press edge).
		var jump := false
		if _jump_req:
			if p.in_jump:
				jump = false  # release one frame first
			elif on_floor or p.coyote_timer > 0.0:
				jump = true
				_jump_frames = 22
				_jump_req = false
			else:
				_jump_req = false
		elif _jump_frames > 0:
			_jump_frames -= 1
			jump = true
			# Aim jumps: stop rising once the shot line passes the boss.
			if _aim_jump and p.velocity.y < 0.0 and line_y <= tgt.y + 1.0:
				_jump_frames = 0
				jump = false
		p.in_jump = jump
		p.in_dir = dir
		# Sidesteps start with a ground dash (needs a fresh press).
		if _dash_req:
			if p.in_dash:
				p.in_dash = false
			else:
				p.in_dash = true
				_dash_req = false
		else:
			p.in_dash = p.in_dash and _dodge_frames > 0

		# Trigger.
		var shoot := false
		match w:
			"buster_full":
				if not p.charging:
					shoot = not p.in_shoot  # a fresh press starts the charge (and fires a tap shot)
				else:
					shoot = true
					if p.charge_level() == 2 and aligned and facing_ok and vuln:
						shoot = false  # release the full charge
			_:
				shoot = aligned and facing_ok and vuln and frame % TAP_PERIOD < TAP_PERIOD / 2
		p.in_shoot = shoot

	func _surface_y(feet: Vector2, on_floor: bool) -> float:
		if _ledge >= 0 and _on_ledge(feet, on_floor):
			return ledges[_ledge].position.y
		return floor_y

	func _on_ledge(feet: Vector2, on_floor: bool) -> bool:
		if _ledge < 0:
			return false
		var l: Rect2 = ledges[_ledge]
		return on_floor and absf(feet.y - l.position.y) < 3.0 and feet.x >= l.position.x - 6.0 and feet.x <= l.end.x + 6.0

	func _nearest_ledge(x: float) -> int:
		var best := -1
		var best_d := INF
		for i in ledges.size():
			var d: float = absf(ledges[i].get_center().x - x)
			if d < best_d:
				best_d = d
				best = i
		return best

	## Walks to the inner edge of the ledge, jumps straight up, steers on.
	func _ledge_nav(feet: Vector2, on_floor: bool) -> int:
		var l: Rect2 = ledges[_ledge]
		var c := l.get_center().x
		if _on_ledge(feet, on_floor):
			if absf(feet.x - c) > 16.0:
				return 1 if c > feet.x else -1
			return 0
		var above := feet.y < l.position.y - 2.0
		if not on_floor and above:
			if feet.x > l.position.x + 10.0 and feet.x < l.end.x - 10.0:
				return 0  # over the ledge already (jump shot): keep facing the boss
			return 1 if c > feet.x else -1
		if not on_floor:
			return 0
		var inner := 1 if c < arena.get_center().x else -1  # side facing the room
		var launch: float = (l.end.x + 12.0) if inner > 0 else (l.position.x - 12.0)
		if absf(feet.x - launch) > 3.0:
			return 1 if launch > feet.x else -1
		_jump_req = true
		_aim_jump = false
		return 0

	## Scans shots, telegraphed columns, zones and the boss body. Returns "jump"
	## when the bot decides to jump this frame (sidesteps are set directly).
	func _threats(frame: int, body_c: Vector2, feet: Vector2, on_floor: bool, tgt: Vector2, boss_vel: Vector2, r: float) -> String:
		if _dodge_frames > 0:
			return ""
		var on_ledge := _ledge >= 0 and _on_ledge(feet, on_floor)
		var tree: SceneTree = p.get_tree()
		# Shots.
		var seen := {}
		for s in tree.get_nodes_in_group("enemy_shot"):
			if s.is_queued_for_deletion():
				continue
			var id: int = s.get_instance_id()
			seen[id] = true
			var pos: Vector2 = s.global_position
			var prev: Vector2 = _prev_pos.get(id, pos)
			_prev_pos[id] = pos
			var v := (pos - prev) * 60.0
			if v.length() < 5.0:
				continue
			var rel := pos - body_c
			var tstar := -rel.dot(v) / v.length_squared()
			if tstar < 0.0 or tstar > 0.4:
				continue
			var miss := (rel + v * tstar).length()
			if miss > 16.0:
				continue
			if not _decide(id):
				continue
			if not on_floor:
				return ""
			if absf(v.x) > absf(v.y) and pos.y > body_c.y - 12.0 or on_ledge:
				return "jump"
			var impact_x := pos.x + v.x * tstar
			_sidestep(feet.x, impact_x, 16)
			return ""
		for id in _prev_pos.keys():
			if not seen.has(id):
				_prev_pos.erase(id)
		# Telegraphed columns (pillars, icicles, falling rocks, inversion marks).
		for col in _columns():
			var x: float = col[0]
			var half: float = col[1]
			if absf(feet.x - x) < half + 8.0 and _decide(str(col[2])):
				if on_ledge:
					return "jump"
				_sidestep(feet.x, x, int((half + 14.0) / 1.5) + 4, true)
				return ""
		# New boss zones (axis-aligned shapes), live or still warning. Low / wide
		# ones are jumped just before they go live, tall narrow ones are left.
		var me := Rect2(feet.x - 6.0, feet.y - 26.0, 12.0, 26.0)
		for z in tree.get_nodes_in_group("damaging"):
			var zid: int = z.get_instance_id()
			if ignore_zones.has(zid):
				continue
			# Rotated beams (ARCA laser, Fragment lattice): get under the emitter,
			# where the sweep starts / the safe pocket is.
			var tracking = z.get("mode")
			for seg in _beam_segments(z):
				if tracking != null and int(tracking) == 0:
					break  # still following the player: move once it locks
				var d := Geometry2D.get_closest_point_to_segment(body_c, seg[0], seg[1]).distance_to(body_c)
				if d > seg[2] + 22.0:
					continue
				var origin: Vector2 = seg[0] if seg[0].distance_to(tgt) < seg[1].distance_to(tgt) else seg[1]
				if absf(origin.x - feet.x) < 14.0 or not _decide("beam%d" % zid):
					break
				if on_ledge:
					_ledge_block = 2.5
				_dodge_dir = 1 if origin.x > feet.x else -1
				_dodge_frames = clampi(int(absf(origin.x - feet.x) / 1.5), 6, 50)
				return ""
			for zr in _zone_rects(z):
				if not zr.grow_individual(6.0, 0.0, 6.0, 0.0).intersects(me):
					continue
				var low: bool = zr.size.x > 90.0 or zr.position.y > feet.y - 40.0
				if low or on_ledge:
					if _time_to_live(z) > 0.12 or not on_floor:
						break
					if _decide(zid):
						return "jump"
					break
				if not _decide(zid):
					break
				_sidestep(feet.x, zr.get_center().x, int((zr.size.x * 0.5 + 12.0) / 1.5) + 4, true)
				return ""
		# The boss body closing in (dashes, rolls, swoops, drops).
		var to_me := body_c - tgt
		var closing := boss_vel.dot(to_me.normalized())
		if to_me.length() < r + 22.0 + maxf(closing, 0.0) * 0.3 and closing > 60.0 and b.get_contact_damage() > 0:
			_boss_calm = 0
			if _decide("boss%d" % _boss_episode):
				if absf(boss_vel.x) > absf(boss_vel.y) and tgt.y > body_c.y - 24.0 and on_floor:
					return "jump"
				if on_floor and not on_ledge:
					if absf(boss_vel.x) > 80.0 and tgt.y < body_c.y - 24.0:
						# Diagonal dive / swoop from above: dash under it, back
						# toward where it came from.
						_sidestep(feet.x, feet.x + signf(boss_vel.x), 20)
					else:
						_sidestep(feet.x, tgt.x, 20)
		else:
			_boss_calm += 1
			if _boss_calm == 30:
				_boss_episode += 1
		return ""

	func _decide(key) -> bool:
		if not _decided.has(key):
			_decided[key] = rng.randf() < react_chance
		return _decided[key]

	## Moves away from `x` for a few frames (toward the roomier side near walls).
	func _sidestep(from_x: float, x: float, frames: int, columns := false) -> void:
		var dir := 1 if from_x >= x else -1
		if from_x + dir * 40.0 > arena.end.x - 8.0:
			dir = -1
		elif from_x + dir * 40.0 < arena.position.x + 8.0:
			dir = 1
		if columns:
			# Do not step into another marked column.
			for col in _columns():
				var cx: float = col[0]
				if (cx - from_x) * dir > 0.0 and absf(cx - (from_x + dir * frames * 1.5)) < col[1] + 6.0:
					dir = -dir
					break
		_dodge_dir = dir
		_dodge_frames = frames
		_dash_req = true
		last_action = "side %d x%d %.2f" % [dir, frames, _frame / 60.0]

	## [x, half width, key] of columns the boss has marked but not yet fired
	## (Solar Fennec pillars, Cryo Narwhal icicles, Terra Pangolin rocks,
	## Fragment inversion marks). A key stays the same while the column waits.
	func _columns() -> Array:
		var out: Array = []
		var pillars = b.get("_pillars")
		if typeof(pillars) == TYPE_ARRAY:
			for pl in pillars:
				if typeof(pl) == TYPE_OBJECT and pl.get("x") != null:
					out.append([pl.x, 13.0, "pillar%d_%d" % [int(pl.x), _col_epoch]])
		var spots = b.get("_rain_spots")
		if typeof(spots) == TYPE_ARRAY:
			for x in spots:
				out.append([float(x), 8.0, "rain%d_%d" % [int(x), _col_epoch]])
		var rocks = b.get("_rocks")
		if typeof(rocks) == TYPE_ARRAY:
			for rk in rocks:
				if typeof(rk) == TYPE_DICTIONARY:
					out.append([float(rk.x), 9.0, "rock%d_%d" % [int(rk.x), _col_epoch]])
		var marks = b.get("_marks")
		if typeof(marks) == TYPE_ARRAY:
			for x in marks:
				out.append([float(x), 11.0, "mark%d_%d" % [int(x), _col_epoch]])
		if out.is_empty() and _had_columns:
			_col_epoch += 1
		_had_columns = not out.is_empty()
		return out

	## World rects of a zone's axis-aligned shapes (live or still warning).
	func _zone_rects(z) -> Array:
		var out: Array = []
		for c in z.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				var xf: Transform2D = c.global_transform
				var rot := fmod(absf(xf.get_rotation()), PI)
				if rot > 0.05 and rot < PI - 0.05:
					continue  # rotated beams: not handled
				var size: Vector2 = c.shape.size * xf.get_scale().abs()
				out.append(Rect2(xf.origin - size * 0.5, size))
		return out

	## [end a, end b, half width] of a zone's rotated rectangle shapes.
	func _beam_segments(z) -> Array:
		var out: Array = []
		for c in z.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				var xf: Transform2D = c.global_transform
				var rot := fmod(absf(xf.get_rotation()), PI)
				if rot <= 0.05 or rot >= PI - 0.05:
					continue
				var half_len: float = c.shape.size.x * 0.5
				var ax: Vector2 = xf.x.normalized()
				out.append([xf.origin - ax * half_len, xf.origin + ax * half_len, c.shape.size.y * 0.5])
		return out

	## Seconds until a telegraphed zone turns live (0 when live or unknown).
	func _time_to_live(z) -> float:
		var t = z.get("_t")
		if t == null:
			return 0.0
		var consts: Dictionary = z.get_script().get_script_constant_map()
		var warn = z.get("warn")
		if warn == null:
			warn = consts.get("WARN_TIME", consts.get("WARN", 0.0))
		var delay = z.get("delay")
		if delay == null:
			delay = 0.0
		return float(warn) + float(delay) - float(t)
