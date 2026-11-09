extends RefCounted
## Optional reference host adapter, independent of gameplay. Call once per host step.
const Library = preload("res://scripts/component_models/library.gd")
var solver = preload("res://scripts/electronics_solver.gd").new()
var states := {}
var last := {}

func step(devices: Array, external: Array, wires: Array, dt: float) -> Dictionary:
	if dt<=0. or not is_finite(dt):return {"ok":false,"error":"A positive finite host timestep is required"}
	var parts := external.duplicate(true)
	for device in devices:
		if device.nodes.size()!=device.model.pins.size():return {"ok":false,"error":"Pin count mismatch: "+str(device.id)}
		var expanded := Library.expand(device.model,device.id,device.nodes,{},last.get("v",{}),states)
		parts.append_array(expanded.filter(func(p):return p.kind!="stateful"))
	var solved: Dictionary=solver.solve(parts,wires,dt)
	if not solved.get("ok",false):return solved
	for device in devices:
		states[device.id]=Library.tick(device.model,device.nodes,solved.v,states.get(device.id,{}),dt,solved.i,device.id)
	last=solved
	return solved

func snapshot() -> Dictionary:
	return states.duplicate(true)

func restore(saved: Dictionary) -> void:
	states=saved.duplicate(true)
