extends RefCounted
const Adapter = preload("res://scripts/campus/dc_lab/bindings/control_adapter.gd")
const Sockets = preload("res://scripts/campus/dc_lab/bindings/socket_registry.gd")
var lab: Node
var station := -1
var sockets := Sockets.new()
var displays := {}
var poses: Array = []
var elapsed := 0.0
var last_values := {}

func configure(owner: Node,index: int) -> void:
	assert(index>=0 and index<3)
	lab=owner;station=index;sockets.configure(index)

func bind_control(target: CollisionObject3D,spec: Dictionary) -> void:
	target.set_meta("role","dc_instrument_control")
	target.set_meta("dc_station",station)
	target.set_meta("action",spec.duplicate(true))

func action_for(target: Node,reverse: bool,state: Dictionary) -> Dictionary:
	if int(target.get_meta("dc_station",-1))!=station:return {}
	return Adapter.action(target.get_meta("action",{}),state,reverse)

func activate(target: Node,reverse: bool,state: Dictionary) -> void:
	var action := action_for(target,reverse,state)
	if not action.is_empty():lab.request(station,action)

func bind_display(id: String,update: Callable) -> void:
	assert(update.is_valid())
	displays[id]=update

func bind_knob(node: Node3D,path: Array,minimum: float,maximum: float) -> void:
	assert(maximum>minimum)
	poses.append({"node":node,"path":path,"minimum":minimum,"maximum":maximum,"rest":node.quaternion})

func port_positions() -> Dictionary:
	return sockets.port_positions()

func observe(state: Dictionary,delta: float,relevant: bool) -> void:
	if not relevant:return
	elapsed+=maxf(delta,0)
	if elapsed<.1:return
	elapsed=0
	var values := Adapter.readings(state)
	for id in displays:
		if not values.has(id):continue
		if last_values.get(id)!=values[id]:displays[id].call(values[id])
	for pose in poses:
		if not is_instance_valid(pose.node):continue
		var value: Variant=state
		for key in pose.path:value=value[key]
		var fraction := clampf((float(value)-float(pose.minimum))/(float(pose.maximum)-float(pose.minimum)),0,1)
		pose.node.quaternion=pose.rest*Quaternion(Vector3.FORWARD,lerpf(-2.35,2.35,fraction))
	last_values=values.duplicate(true)
