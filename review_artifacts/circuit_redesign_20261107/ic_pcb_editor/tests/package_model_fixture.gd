extends SceneTree
const Model=preload("res://review_artifacts/circuit_redesign_20261107/ic_pcb_editor/modules/package_pin_model.gd")
const Board=preload("res://scripts/breadboard_model.gd")
class MemoryProfile:
	extends RefCounted
	var data: Dictionary={"pending_trade":{},"blueprints":{},"kits":{"test":{"board":{}}},"equipped":"test"}
	func save() -> Error:return OK

func _init() -> void:
	var board:=Board.empty();var model=Model.new()
	var original:={"package":"IC","name":"Fixture","footprint":{"width":8,"height":6,"color":"24775b"},"pins":[{"id":"stable_input","name":"IN","node":"L1","role":"input","connector":"female_header","position":{"x":0,"y":0}},{"id":"stable_output","name":"OUT","node":"R1","role":"output","connector":"test_point","position":{"x":7,"y":5}}]}
	model.open(board,original,"IC")
	assert(model.pins[0].id=="stable_input" and model.pins[0].hole=="A1")
	assert(model.pins[1].id=="stable_output" and model.pins[1].hole=="F1")
	assert(model.set_pin(0,{"position":{"x":1,"y":1}}))
	assert(not model.set_pin(1,{"position":{"x":1,"y":1}}))
	assert(model.rotate())
	assert(model.pins[0].id=="stable_input" and model.pins[0].hole=="A1")
	assert(model.pins[0].connector=="female_header")
	assert(model.draft.footprint.width==6 and model.draft.footprint.height==8)
	var profile:=MemoryProfile.new();profile.data.kits.test.board=board
	var result:=model.save(profile)
	assert(result.begins_with("Blueprint saved:"),result)
	var saved: Dictionary=profile.data.blueprints.values()[0]
	assert(saved.pins[0].id=="stable_input" and saved.pins[0].node=="L1")
	assert(saved.pins[1].id=="stable_output" and saved.pins[1].connector=="test_point")
	print("PACKAGE_MODEL_FIXTURE_OK")
	quit()
