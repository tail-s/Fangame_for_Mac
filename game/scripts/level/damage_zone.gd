extends Area2D
## Area that hurts the player on contact (player checks group "damaging").

var damage := 3


func _ready() -> void:
	add_to_group("damaging")
	monitoring = false
