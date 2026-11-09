extends RefCounted
## Guarded-runtime only: instantiate real authored models and route real station actions.
const Model = preload("res://review_artifacts/m103_dc_rebuild_20261107/physical_models/fixture.gd")
const Binding = preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/physical_binding.gd")
const Station = preload("res://scripts/dc_station.gd")

class Harness extends Node:
	var benches: Array=[]
	var calls: Array=[]
	func request(index: int,action: Dictionary) -> void:
		calls.append({"index":index,"action":action.duplicate(true)})
		assert(benches[index].apply(action)=="")

static func run(tree_parent: Node3D) -> void:
	var harness := Harness.new();tree_parent.add_child(harness)
	harness.benches=[Station.new(),Station.new(),Station.new()]
	var fixtures: Array=[]
	for index in 3:
		var origin := Node3D.new();tree_parent.add_child(origin)
		origin.position=Vector3((index-1)*6,0,8.8);origin.rotation.y=PI
		var model := Model.new();origin.add_child(model);model.build(index)
		var bound := Binding.new();origin.add_child(bound);bound.bind(harness,index,model)
		fixtures.append(bound)
		assert(bound.port_positions().size()==34)
		assert(model.control_mounts.size()==27)
		for id in model.port_targets:
			var anchor: Vector3=bound.port_positions()[id]
			assert(anchor.is_equal_approx(model.socket_surface_position(id)))
			var opening: Marker3D=bound.binding.sockets.openings[id]
			var pick: StaticBody3D=opening.get_child(0)
			assert(pick.global_position.is_equal_approx(anchor))
			assert(pick.get_meta("dc_port")==id and pick.get_meta("dc_station")==index)
		for id in model.control_mounts:
			harness.benches[index]=Station.new()
			var target: Node=model.control_mounts[id]
			var action: Dictionary=bound.action_for(target,false,harness.benches[index].snapshot())
			assert(not action.is_empty())
			bound.binding.activate(target,false,harness.benches[index].snapshot())
			assert(harness.calls.back().index==index)
			assert(bound.action_for(target,true,harness.benches[index].snapshot()).has("op"))
		var initial: Vector3=bound.port_positions()["CH1+"]
		model.position.x+=.25
		assert(not bound.port_positions()["CH1+"].is_equal_approx(initial))
		assert(bound.port_positions()["CH1+"].is_equal_approx(model.socket_surface_position("CH1+")))
		model.position.x-=.25
	assert(fixtures[0].port_positions()["COM"].distance_to(fixtures[1].port_positions()["COM"])>5.9)
	assert(fixtures[1].port_positions()["COM"].distance_to(fixtures[2].port_positions()["COM"])>5.9)
