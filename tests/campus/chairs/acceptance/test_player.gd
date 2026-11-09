extends "res://scripts/first_person.gd"
## Test input seam: headless synthetic key events do not reliably update
## Input.is_physical_key_pressed(), which production down() polls directly.
var test_ctrl_pressed := false

func down(action: String) -> bool:
	if action == "crouch":
		return test_ctrl_pressed
	return super.down(action)
