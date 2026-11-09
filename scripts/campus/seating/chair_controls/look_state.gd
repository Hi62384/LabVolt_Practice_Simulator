extends RefCounted
## Local seated view yaw is measured from the chair's live swivel angle.

const HEAD_LIMIT := PI * 0.5

var head_yaw := 0.0
var chair_turn := 0.0

func enter(chair_yaw: float) -> void:
	head_yaw = 0.0
	chair_turn = chair_yaw

func look(horizontal_radians: float, swivel_mode: bool) -> void:
	if swivel_mode:
		chair_turn += horizontal_radians
	else:
		head_yaw = clampf(head_yaw + horizontal_radians, -HEAD_LIMIT, HEAD_LIMIT)

func world_yaw(chair_yaw: float) -> float:
	return chair_yaw + head_yaw

func leave(chair_yaw: float) -> float:
	var result := world_yaw(chair_yaw)
	head_yaw = 0.0
	chair_turn = result
	return result
