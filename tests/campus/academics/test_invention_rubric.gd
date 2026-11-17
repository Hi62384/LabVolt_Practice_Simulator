extends SceneTree
const Rubric=preload("res://scripts/campus/academics/invention_rubric.gd")
class Station extends RefCounted:
	var board: Dictionary={"parts":[]}
	var board_held:=false
	var board_stowed:=false
	var linked:=false
	var master:=true
	var board_epoch:=2
	var solved_board_epoch:=2
	var revision:=3
	var solved_revision:=3
	var result: Dictionary={"ok":true,"i":{"board/led":.012},"resistor_ratings":{"r":{"overloaded":false}}}
	func board_simulating() -> bool:return true
	func netlist() -> Array:return [{"kind":"LED","id":"board/led"}]

func _initialize() -> void:
	var station:=Station.new()
	assert(Rubric.evaluate_led(station).passed)
	station.result.i["board/led"]=.04
	assert(not Rubric.evaluate_led(station).passed)
	station.result.i["board/led"]=.012
	station.solved_revision=2
	assert(not Rubric.evaluate_led(station).passed)
	station.solved_revision=3
	station.result.resistor_ratings.r.overloaded=true
	assert(not Rubric.evaluate_led(station).passed)
	print("INVENTION_RUBRIC PASS")
	quit()
