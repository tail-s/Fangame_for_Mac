extends Node
## Global state: save data (unlocked parts, loadout, presets, progress),
## the in-stage checkpoint, and the stats of the equipped loadout.

signal loadout_changed

const InputSetup = preload("res://scripts/core/input_setup.gd")
const ArmorData = preload("res://scripts/armor/armor_data.gd")
const WeaponShot = preload("res://scripts/combat/weapon_shot.gd")

const CHARACTER_IDS := ["ix", "sable", "echo"]
const DEFAULT_PARTY := ["ix", "sable"]

const SAVE_VERSION := 1
const PRESET_COUNT := 3
const BASE_HP := 16

var save_path := "user://save.json"
## Debug / test runs turn this off so they never touch the player's save file.
var save_enabled := true
var data := {}
var stats := {}

var checkpoint := Vector2.ZERO
var has_checkpoint := false
var deaths := 0


func _ready() -> void:
	InputSetup.register()
	new_game()


# --- save file ------------------------------------------------------------------

func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"unlocked": [],
		"loadout": ArmorData.neutral_loadout(),
		"presets": [null, null, null],
		"cleared": [],
		"collected": [],
		"hp_bonus": 0,
		"weapons": [],
		"party": DEFAULT_PARTY.duplicate(),
	}


func new_game() -> void:
	data = default_data()
	_refresh()


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> void:
	if not save_enabled:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))


## Loads and validates the save file. Unknown / broken fields fall back to defaults.
func load_game() -> bool:
	if not has_save():
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK:
		return false
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d := default_data()
	for key in ["unlocked", "cleared", "collected", "weapons"]:
		if typeof(parsed.get(key)) == TYPE_ARRAY:
			for v in parsed[key]:
				if typeof(v) == TYPE_STRING and not d[key].has(v):
					d[key].append(v)
	d["unlocked"] = d["unlocked"].filter(func(id): return ArmorData.PART_DESC.has(id))
	d["weapons"] = d["weapons"].filter(func(id): return WeaponShot.ORDER.has(id))
	if _valid_party(parsed.get("party")):
		d["party"] = parsed["party"].duplicate()
	d["hp_bonus"] = clampi(int(parsed.get("hp_bonus", 0)), 0, 32)
	data = d
	if typeof(parsed.get("presets")) == TYPE_ARRAY:
		for i in mini(PRESET_COUNT, parsed["presets"].size()):
			var p = parsed["presets"][i]
			if ArmorData.is_valid_loadout(p) and _loadout_unlocked(p):
				data["presets"][i] = _clean(p)
	var lo = parsed.get("loadout")
	if ArmorData.is_valid_loadout(lo) and _loadout_unlocked(lo):
		data["loadout"] = _clean(lo)
	_refresh()
	return true


# --- armor ------------------------------------------------------------------------

func is_unlocked(id: String) -> bool:
	return id.begins_with("neutral_") or data["unlocked"].has(id)


func unlock(id: String) -> void:
	if not is_unlocked(id):
		data["unlocked"].append(id)
		save_game()


func unlock_all() -> void:
	for id in ArmorData.PART_DESC:
		if not id.begins_with("neutral_") and not data["unlocked"].has(id):
			data["unlocked"].append(id)
	for id in WeaponShot.ORDER:
		if not data["weapons"].has(id):
			data["weapons"].append(id)
	save_game()


# --- weapons & party -------------------------------------------------------------

func unlock_weapon(id: String) -> void:
	if WeaponShot.ORDER.has(id) and not data["weapons"].has(id):
		data["weapons"].append(id)
		save_game()


## ["buster"] + unlocked special weapons in boss order.
func weapons_available() -> Array:
	var out := ["buster"]
	for id in WeaponShot.ORDER:
		if data["weapons"].has(id):
			out.append(id)
	return out


func party() -> Array:
	return data["party"]


func set_party(ids: Array) -> bool:
	if not _valid_party(ids):
		return false
	data["party"] = ids.duplicate()
	save_game()
	return true


func _valid_party(ids) -> bool:
	if typeof(ids) != TYPE_ARRAY or ids.is_empty() or ids.size() > 2:
		return false
	for id in ids:
		if not CHARACTER_IDS.has(id) or ids.count(id) > 1:
			return false
	return true


func unlocked_count() -> int:
	return data["unlocked"].size()


## Armors that can be equipped in `slot` (neutral + unlocked parts).
func options_for(slot: String) -> Array:
	var out := []
	for armor in ArmorData.ARMORS:
		if is_unlocked(ArmorData.part_id(armor, slot)):
			out.append(armor)
	return out


func loadout() -> Dictionary:
	return data["loadout"]


func set_slot(slot: String, armor: String) -> bool:
	if not is_unlocked(ArmorData.part_id(armor, slot)):
		return false
	data["loadout"][slot] = armor
	_refresh()
	save_game()
	return true


func save_preset(i: int) -> void:
	data["presets"][i] = _clean(data["loadout"])
	save_game()


func preset(i: int):
	return data["presets"][i]


func load_preset(i: int) -> bool:
	var p = data["presets"][i]
	if not ArmorData.is_valid_loadout(p) or not _loadout_unlocked(p):
		return false
	data["loadout"] = _clean(p)
	_refresh()
	save_game()
	return true


# --- progress -----------------------------------------------------------------------

func is_collected(id: String) -> bool:
	return data["collected"].has(id)


func collect(id: String) -> void:
	if not is_collected(id):
		data["collected"].append(id)
		save_game()


func add_hp_bonus(amount: int) -> void:
	data["hp_bonus"] = int(data["hp_bonus"]) + amount
	save_game()


func max_hp() -> int:
	return BASE_HP + int(data["hp_bonus"])


func mark_cleared(stage_id: String) -> void:
	if not data["cleared"].has(stage_id):
		data["cleared"].append(stage_id)
	save_game()


func is_cleared(stage_id: String) -> bool:
	return data["cleared"].has(stage_id)


func set_checkpoint(pos: Vector2) -> void:
	checkpoint = pos
	has_checkpoint = true


func clear_checkpoint() -> void:
	has_checkpoint = false


# --- internals ----------------------------------------------------------------------

func _refresh() -> void:
	stats = ArmorData.compute(data["loadout"])
	loadout_changed.emit()


func _loadout_unlocked(lo: Dictionary) -> bool:
	for slot in ArmorData.SLOTS:
		if not is_unlocked(ArmorData.part_id(lo[slot], slot)):
			return false
	return true


func _clean(lo: Dictionary) -> Dictionary:
	var out := {}
	for slot in ArmorData.SLOTS:
		out[slot] = lo[slot]
	return out
