extends RefCounted
## Stand-in "player" for PlayerVisual in menus (armor lab preview).
## Exposes the same fields / methods the visual reads.

var invuln_timer := 0.0
var anim_time := 0.0
var shoot_pose_timer := 1.0
var velocity := Vector2.ZERO
var air_dashing := false
var flying := false
var gliding := false
var special_kind := ""
var special_phase := 0
var facing := 1


func visual_facing() -> int:
	return facing


func is_on_floor() -> bool:
	return true


func is_dashing() -> bool:
	return false


func is_wall_sliding() -> bool:
	return false


func is_hurt() -> bool:
	return false


func charge_level() -> int:
	return 0
