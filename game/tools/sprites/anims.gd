extends RefCounted
## Pose tables for the shared character skeleton (see rig.gd for the keys).
## build() returns {"frames": [pose, ...], "anims": {name: {frames, fps, loop}}}.
## Standing feet are planted with IK ("na" / "fa" = ankle targets).

const ANKLE_Y := -5.0


static func stand(extra := {}) -> Dictionary:
	var p := {"na": Vector2(2.0, ANKLE_Y), "fa": Vector2(-2.2, ANKLE_Y),
			"ns": -0.12, "ne": 0.45, "fs": 0.18, "fe": 0.35}
	p.merge(extra, true)
	return p


static func build() -> Dictionary:
	var frames: Array = []
	var anims := {}
	var add := func(name: String, poses: Array, fps: float, loop: bool) -> void:
		var idx := []
		for p in poses:
			idx.append(frames.size())
			frames.append(p)
		anims[name] = {"frames": idx, "fps": fps, "loop": loop}

	# Idle: slow breathing (pelvis dips, shoulders follow).
	var idle := []
	for k in 4:
		var dip: float = [0.0, 0.5, 1.0, 0.5][k]
		idle.append(stand({"root": Vector2(0, dip), "ns": -0.12 - dip * 0.05, "fs": 0.18 + dip * 0.05}))
	add.call("idle", idle, 4.0, true)

	# Run: 10-frame cycle. Each foot spends ~40% of the cycle on the ground
	# sliding back, then swings forward lifted (heel kicks up early in the swing).
	var run := []
	for k in 10:
		var ph := float(k) / 10.0
		var p := {"lean": 0.16, "head": -0.06}
		for side in ["n", "f"]:
			var q := fmod(ph + (0.0 if side == "n" else 0.5), 1.0)
			var x: float
			var y := ANKLE_Y
			var foot := 0.0
			if q < 0.4:
				var u := q / 0.4
				x = lerpf(5.5, -5.0, u)
			else:
				var u := (q - 0.4) / 0.6
				x = lerpf(-5.0, 5.5, (1.0 - cos(u * PI)) * 0.5)
				y = ANKLE_Y - sin(u * PI) * 4.5 - (1.0 - u) * 1.2
				foot = -0.7 * (1.0 - u) + 0.2 * u
			p[side + "a"] = Vector2(x, y)
			p[side + "f"] = foot
		# Pelvis: lowest at contact, highest in the flight phase.
		var bob := cos(ph * TAU * 2.0)
		p["root"] = Vector2(0.5, 0.6 + bob * 0.9)
		# Arms swing against the legs.
		var swing := sin(ph * TAU)
		p["ns"] = -0.15 - swing * 0.75
		p["ne"] = 0.9 + swing * 0.2
		p["fs"] = -0.15 + swing * 0.75
		p["fe"] = 0.9 - swing * 0.2
		run.append(p)
	add.call("run", run, 16.0, true)

	# Jump: take-off, rise, apex (tucked), fall (legs reaching down).
	add.call("jump", [
		{"nh": 0.95, "nk": 1.5, "nf": 0.1, "fh": -0.05, "fk": 0.35, "ff": -0.5, "ns": -0.9, "ne": 0.9,
				"fs": 0.5, "fe": 0.4, "root": Vector2(0, -1), "lean": 0.05},
		{"nh": 0.85, "nk": 1.3, "nf": 0.0, "fh": 0.15, "fk": 0.6, "ff": -0.4, "ns": -0.7, "ne": 1.1,
				"fs": 0.3, "fe": 0.6, "root": Vector2(0, -1.5)},
	], 10.0, false)
	add.call("apex", [
		{"nh": 0.8, "nk": 1.4, "fh": 0.45, "fk": 1.2, "ff": -0.2, "ns": -0.5, "ne": 1.2,
				"fs": 0.2, "fe": 0.9, "root": Vector2(0, -2)},
	], 8.0, false)
	add.call("fall", [
		{"nh": 0.35, "nk": 0.5, "nf": -0.15, "fh": -0.1, "fk": 0.7, "ff": -0.3, "ns": -1.0, "ne": 0.7,
				"fs": 0.7, "fe": 0.3, "root": Vector2(0, -1)},
		{"nh": 0.32, "nk": 0.45, "nf": -0.15, "fh": -0.12, "fk": 0.65, "ff": -0.3, "ns": -1.1, "ne": 0.7,
				"fs": 0.75, "fe": 0.3, "root": Vector2(0, -1.5)},
	], 8.0, true)
	add.call("land", [
		stand({"na": Vector2(3.0, ANKLE_Y), "fa": Vector2(-3.0, ANKLE_Y), "root": Vector2(0, 3.0), "lean": 0.22,
				"ns": -0.5, "ne": 0.8, "fs": 0.5, "fe": 0.6}),
	], 12.0, false)

	# Ground dash: low, leaning, back leg stretched out.
	add.call("dash", [
		{"na": Vector2(6.5, ANKLE_Y), "fa": Vector2(-8.5, ANKLE_Y + 0.5), "ff": -0.5, "lean": 0.5,
				"root": Vector2(0, 3.0), "ns": -1.2, "ne": 0.5, "fs": 1.0, "fe": 0.3, "head": -0.25},
		{"na": Vector2(6.5, ANKLE_Y), "fa": Vector2(-8.5, ANKLE_Y), "ff": -0.45, "lean": 0.48,
				"root": Vector2(0, 2.6), "ns": -1.25, "ne": 0.5, "fs": 1.05, "fe": 0.3, "head": -0.25},
	], 12.0, true)
	add.call("air_dash", [
		{"nh": 0.1, "nk": 0.9, "nf": -0.4, "fh": -0.55, "fk": 0.5, "ff": -0.6, "lean": 0.42,
				"ns": -1.3, "ne": 0.4, "fs": 1.1, "fe": 0.2, "head": -0.25, "root": Vector2(0, 0)},
	], 8.0, false)

	# Wall slide: facing away from the wall (wall behind), back hand on the wall.
	add.call("wall_slide", [
		{"nh": 0.9, "nk": 1.3, "nf": 0.0, "fh": -0.15, "fk": 0.3, "ff": -0.2, "lean": -0.08,
				"ns": 0.3, "ne": 0.7, "fs": -2.4, "fe": -0.5, "root": Vector2(1.0, 0)},
		{"nh": 0.85, "nk": 1.25, "nf": 0.0, "fh": -0.15, "fk": 0.32, "ff": -0.2, "lean": -0.06,
				"ns": 0.32, "ne": 0.72, "fs": -2.4, "fe": -0.5, "root": Vector2(1.0, 0.5)},
	], 6.0, true)
	add.call("wall_kick", [
		{"nh": 1.0, "nk": 1.2, "fh": -0.75, "fk": 0.2, "ff": -0.5, "lean": 0.15, "ns": -0.9, "ne": 0.9,
				"fs": 1.2, "fe": 0.2, "root": Vector2(0, -1)},
	], 10.0, false)

	# Hurt: recoil backwards.
	add.call("hurt", [
		{"na": Vector2(4.5, ANKLE_Y - 1.0), "fa": Vector2(-3.0, ANKLE_Y), "lean": -0.4, "head": 0.2,
				"ns": 1.0, "ne": 0.9, "fs": -1.0, "fe": 0.8, "root": Vector2(-1.5, 1.0)},
		{"na": Vector2(4.0, ANKLE_Y - 0.5), "fa": Vector2(-3.5, ANKLE_Y), "lean": -0.3, "head": 0.15,
				"ns": 0.8, "ne": 1.0, "fs": -0.8, "fe": 0.9, "root": Vector2(-1.0, 1.5)},
	], 12.0, true)

	# Flight (Aero LEG / hover): upright, legs hanging with pointed toes, wings open.
	add.call("fly", [
		{"nh": 0.25, "nk": 0.5, "nf": -0.6, "fh": -0.1, "fk": 0.4, "ff": -0.7, "lean": 0.12, "wing": 1.0,
				"ns": -0.4, "ne": 0.7, "fs": 0.4, "fe": 0.5, "root": Vector2(0, -1)},
		{"nh": 0.22, "nk": 0.45, "nf": -0.65, "fh": -0.12, "fk": 0.38, "ff": -0.75, "lean": 0.12, "wing": 0.85,
				"ns": -0.45, "ne": 0.7, "fs": 0.45, "fe": 0.5, "root": Vector2(0, -0.2)},
	], 10.0, true)
	add.call("glide", [
		{"nh": -0.15, "nk": 0.5, "nf": -0.6, "fh": -0.45, "fk": 0.4, "ff": -0.7, "lean": 0.35, "wing": 1.0,
				"ns": 0.9, "ne": 0.3, "fs": 1.2, "fe": 0.2, "head": -0.2},
	], 8.0, false)

	# Specials: shoulder-first rush, Sky Breaker rise and dive.
	add.call("rush", [
		{"nh": 0.2, "nk": 1.0, "nf": -0.4, "fh": -0.7, "fk": 0.4, "ff": -0.7, "lean": 0.75,
				"ns": -1.5, "ne": 0.2, "fs": 1.3, "fe": 0.2, "head": -0.45, "wing": 0.6},
	], 8.0, false)
	add.call("dive_rise", [
		{"nh": 1.0, "nk": 1.6, "fh": 0.7, "fk": 1.5, "lean": 0.0, "ns": -2.7, "ne": 0.2, "fs": -2.5,
				"fe": 0.3, "root": Vector2(0, -2), "wing": 1.0},
	], 8.0, false)
	add.call("dive", [
		{"nh": 0.05, "nk": 0.15, "nf": -0.9, "fh": -0.05, "fk": 0.2, "ff": -0.9, "lean": 0.1,
				"ns": 0.4, "ne": 0.2, "fs": 0.6, "fe": 0.2, "wing": 0.2},
	], 8.0, false)
	return {"frames": frames, "anims": anims}
