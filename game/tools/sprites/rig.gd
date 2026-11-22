extends RefCounted
## 2D skeleton shared by all three characters (side view, facing right, y down,
## origin = between the feet on the ground). A pose is a Dictionary of angles in
## radians; missing keys use the standing pose. Limb angles: 0 = straight down,
## positive = swung forward.
##   root  Vector2   pelvis offset            lean  torso tilt (+ forward)
##   head  head tilt on top of lean
##   nh nk nf   near hip / knee bend / foot tilt (world, + toe up)
##   fh fk ff   far leg
##   ns ne      near shoulder / elbow bend      fs fe   far arm
##   wing       0..1 wing spread (Aero / Ultimate body)

const THIGH := 5.5
const SHIN := 5.5
const ANKLE := 5.0   # ankle height above the sole
const TORSO := 8.5
const NECK := 4.2
const UPPER := 4.5
const FORE := 4.5
const PELVIS_Y := -16.5

## Body scale per character (ECHO is smaller).
var scale := 1.0


static func limb_dir(a: float) -> Vector2:
	return Vector2(sin(a), cos(a))


func joints(pose: Dictionary, origin: Vector2) -> Dictionary:
	var s := scale
	var j := {}
	var lean: float = pose.get("lean", 0.0)
	j.lean = lean
	j.head_angle = lean + pose.get("head", 0.0)
	j.pelvis = origin + (Vector2(0, PELVIS_Y) * s) + pose.get("root", Vector2.ZERO)
	var up := Vector2(0, -1).rotated(lean)
	j.up = up
	j.neck = j.pelvis + up * TORSO * s
	j.head = j.neck + Vector2(0, -1).rotated(j.head_angle) * NECK * s
	for side in ["n", "f"]:
		var hx := 0.6 if side == "n" else -0.6
		var hip: Vector2 = j.pelvis + Vector2(hx, 0.5) * s
		var knee: Vector2
		var ankle: Vector2
		var ka: float
		if pose.has(side + "a"):
			# IK: ankle target (relative to the origin), knee bends forward.
			var target: Vector2 = origin + pose[side + "a"] * s
			var a := THIGH * s
			var b := SHIN * s
			var to := target - hip
			var d := clampf(to.length(), 0.5, a + b - 0.05)
			var cos_h := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
			var base := to.normalized()
			var t1 := base.rotated(acos(cos_h))
			var t2 := base.rotated(-acos(cos_h))
			var thigh := t1 if t1.x > t2.x else t2
			knee = hip + thigh * a
			ankle = hip + base * d
			var sd := (ankle - knee).normalized()
			ka = atan2(sd.x, sd.y)
		else:
			var ha: float = pose.get(side + "h", 0.0)
			ka = ha - pose.get(side + "k", 0.0)
			knee = hip + limb_dir(ha) * THIGH * s
			ankle = knee + limb_dir(ka) * SHIN * s
		j[side + "_hip"] = hip
		j[side + "_knee"] = knee
		j[side + "_ankle"] = ankle
		j[side + "_shin_angle"] = ka
		j[side + "_foot"] = pose.get(side + "f", 0.0)
		var sx := 0.8 if side == "n" else -1.2
		var shoulder: Vector2 = j.pelvis + (up * (TORSO - 2.2) + up.orthogonal() * -sx) * s
		var sa: float = lean + pose.get(side + "s", 0.0)
		var ea: float = sa + pose.get(side + "e", 0.0)
		var elbow := shoulder + limb_dir(sa) * UPPER * s
		var hand := elbow + limb_dir(ea) * FORE * s
		j[side + "_shoulder"] = shoulder
		j[side + "_elbow"] = elbow
		j[side + "_hand"] = hand
		j[side + "_fore_angle"] = ea
	j.wing = pose.get("wing", 0.0)
	j.scale = s
	return j
