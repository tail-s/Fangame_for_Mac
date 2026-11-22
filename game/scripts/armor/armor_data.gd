## Armor parts (GDD v0.2 §4) and stat computation for a loadout.
## A loadout is {"head": armor, "body": armor, "arm": armor, "leg": armor}
## where armor is "neutral", "vanguard" or "aero" -> 3^4 = 81 combinations.

const SLOTS := ["head", "body", "arm", "leg"]
const ARMORS := ["neutral", "vanguard", "aero"]
const SLOT_LABEL := {"head": "HEAD", "body": "BODY", "arm": "ARM", "leg": "LEG"}

const ARMOR_NAME := {"neutral": "NEUTRAL", "vanguard": "VANGUARD", "aero": "AERO", "ultimate": "ULTIMATE"}
const ARMOR_COLOR := {
	"neutral": Color("d7edf3"),
	"vanguard": Color("3179e3"),
	"aero": Color("71dedf"),
	"ultimate": Color("8a63d2"),
}

## Ultimate Armor IX (GDD v0.2 §4-5): complete frame, no part mixing.
const ULTIMATE_DESC := "ULTIMATE ARMOR IX — 노바 스트라이크 IX(V, 코어 100), 플라즈마 차지샷, 공중 대시·호버. 탐험 능력(균열벽·활공·비행) 없음"
const ULTIMATE_LOADOUT := {"head": "ultimate", "body": "ultimate", "arm": "ultimate", "leg": "ultimate"}

const PART_DESC := {
	"neutral_head": "기본 헬멧",
	"neutral_body": "기본 프레임",
	"neutral_arm": "기본 버스터",
	"neutral_leg": "기본 레그",
	"vanguard_head": "균열벽·가짜 발판 표시, 일반탄이 가까운 적을 살짝 유도",
	"vanguard_body": "대시 중 받는 피해 50% 감소, 피격 시 넉백 없음",
	"vanguard_arm": "차지샷이 균열벽을 부숨, 풀차지는 모든 적을 관통",
	"vanguard_leg": "대시 중 다시 눌러 2연속 대시, 대시 몸통 공격",
	"aero_head": "공중에서도 코어 게이지 회복",
	"aero_body": "낙하 중 점프 유지로 활공, 공중 피해 25% 감소",
	"aero_arm": "차지샷이 3갈래 확산탄으로 발사",
	"aero_leg": "공중 대시 1회, 공중에서 점프를 다시 눌러 단거리 비행",
}

const SET_DESC := {
	"vanguard2": "뱅가드 2파츠 — 대시 거리 +15%",
	"aero2": "에어로 2파츠 — 코어 회복 +50%",
	"hybrid": "하이브리드 2+2 — 듀얼 코어: 대시 점프 후 공중 대시 +1",
	"vanguard4": "뱅가드 풀세트 — 필살기 OVERDRIVE RUSH (코어 100, V키)",
	"aero4": "에어로 풀세트 — 필살기 SKY BREAKER (코어 100, V키)",
}

## Capsule digits in stage maps -> part id.
const CAPSULE_CODES := {
	"1": "vanguard_head", "2": "vanguard_body", "3": "vanguard_arm", "4": "vanguard_leg",
	"5": "aero_head", "6": "aero_body", "7": "aero_arm", "8": "aero_leg",
}

const BASE := {
	"walk_speed": 90.0,
	"dash_speed": 210.0,
	"dash_time": 0.36,
	"dash_chain": 1,
	"dash_commit": false,
	"dash_attack": 0,
	"dash_damage_mult": 1.0,
	"knockback": true,
	"reveal": false,
	"homing": false,
	"breaker": false,
	"pierce_all": false,
	"spread": false,
	"core_regen_ground": 20.0,
	"core_regen_air": 0.0,
	"glide": false,
	"air_damage_mult": 1.0,
	"air_dashes": 0,
	"flight": false,
	"dual_core": false,
	"special": "",
	"hover": 0.0,
	"plasma": false,
}


static func part_id(armor: String, slot: String) -> String:
	return armor + "_" + slot


static func part_name(id: String) -> String:
	var bits := id.split("_")
	return "%s %s" % [ARMOR_NAME[bits[0]], SLOT_LABEL[bits[1]]]


static func part_armor(id: String) -> String:
	return id.split("_")[0]


static func part_slot(id: String) -> String:
	return id.split("_")[1]


static func neutral_loadout() -> Dictionary:
	return {"head": "neutral", "body": "neutral", "arm": "neutral", "leg": "neutral"}


static func is_valid_loadout(loadout) -> bool:
	if typeof(loadout) != TYPE_DICTIONARY:
		return false
	for slot in SLOTS:
		if not loadout.has(slot) or not ARMORS.has(loadout[slot]):
			return false
	return true


## Every combination of the three armors over four slots (81 loadouts).
static func all_loadouts() -> Array:
	var out := []
	for h in ARMORS:
		for b in ARMORS:
			for a in ARMORS:
				for l in ARMORS:
					out.append({"head": h, "body": b, "arm": a, "leg": l})
	return out


static func count(loadout: Dictionary, armor: String) -> int:
	var n := 0
	for slot in SLOTS:
		if loadout[slot] == armor:
			n += 1
	return n


## Active set bonuses, in display order.
static func sets_for(loadout: Dictionary) -> Array:
	var v := count(loadout, "vanguard")
	var a := count(loadout, "aero")
	var out := []
	if v >= 2:
		out.append("vanguard2")
	if a >= 2:
		out.append("aero2")
	if v == 2 and a == 2:
		out.append("hybrid")
	if v == 4:
		out.append("vanguard4")
	if a == 4:
		out.append("aero4")
	return out


## Stats of the Ultimate Armor IX complete frame.
static func compute_ultimate() -> Dictionary:
	var s := BASE.duplicate()
	s["dash_time"] = 0.4
	s["core_regen_ground"] = 30.0
	s["core_regen_air"] = 10.0
	s["air_dashes"] = 1
	s["hover"] = 0.5
	s["plasma"] = true
	s["pierce_all"] = true
	s["special"] = "nova"
	s["sets"] = []
	s["vanguard"] = 0
	s["aero"] = 0
	return s


static func compute(loadout: Dictionary) -> Dictionary:
	var s := BASE.duplicate()
	if loadout.head == "vanguard":
		s["reveal"] = true
		s["homing"] = true
	if loadout.body == "vanguard":
		s["dash_damage_mult"] = 0.5
		s["knockback"] = false
	if loadout.arm == "vanguard":
		s["breaker"] = true
		s["pierce_all"] = true
	if loadout.leg == "vanguard":
		s["dash_chain"] = 2
		s["dash_commit"] = true
		s["dash_attack"] = 2
	if loadout.head == "aero":
		s["core_regen_air"] = 20.0
	if loadout.body == "aero":
		s["glide"] = true
		s["air_damage_mult"] = 0.75
	if loadout.arm == "aero":
		s["spread"] = true
	if loadout.leg == "aero":
		s["air_dashes"] = 1
		s["flight"] = true

	var sets := sets_for(loadout)
	if sets.has("vanguard2"):
		s["dash_time"] = s["dash_time"] * 1.15
	if sets.has("aero2"):
		s["core_regen_ground"] = s["core_regen_ground"] * 1.5
		s["core_regen_air"] = s["core_regen_air"] * 1.5
	if sets.has("hybrid"):
		s["dual_core"] = true
	if sets.has("vanguard4"):
		s["special"] = "overdrive"
	if sets.has("aero4"):
		s["special"] = "skybreaker"
	s["sets"] = sets
	s["vanguard"] = count(loadout, "vanguard")
	s["aero"] = count(loadout, "aero")
	return s
