extends RefCounted
## Runs one mounted PCB through the same circuit and firmware station as a
## standalone board. The host alone owns this runtime and publishes voltages.
const Board=preload("res://scripts/breadboard_model.gd")
const Station=preload("res://scripts/dc_station.gd")
const IO=preload("res://scripts/io_devices/controls.gd")
var station: RefCounted
var pin_map: Dictionary={}
var inputs: Array=[]

func configure(id: String,definitions: Dictionary,mapping: Dictionary) -> bool:
	var board: Dictionary=Board.standalone(id,definitions)
	if board.is_empty():return false
	station=Station.new()
	station.board=board
	station.board_epoch=1
	station.master=true
	station.channels[0].enabled=true
	station.channels[0].voltage=5.0
	station.channels[0].limit=.5
	station.wires=[["CH1+","X%d"%(int(mapping.power)+1)],["CH1-","X%d"%(int(mapping.ground)+1)]]
	pin_map=mapping.duplicate(true)
	inputs.clear()
	for device in Board.devices(board):
		var kind: String=Board.manual_input_type(str(device.part.type))
		if kind.is_empty() and not IO.defaults(str(device.part.type)).is_empty():kind=str(device.part.type)
		if kind.is_empty():continue
		inputs.append({"id":str(device.id),"name":str(device.part.get("type","Input"))+" · "+str(device.id).get_file(),"kind":kind})
	return true

func tick(dt: float) -> Dictionary:
	if not is_instance_valid(station):return {"A":0.0,"B":0.0,"ok":false}
	station.step(clampf(dt,.001,.05))
	var result: Dictionary={"ok":bool(station.result.get("ok",false)),"error":str(station.result.get("error","")),"A":0.0,"B":0.0}
	if not result.ok:return result
	var ground: String="X%d"%(int(pin_map.ground)+1)
	for control in ["A","B"]:
		if int(pin_map[control])>=0:result[control]=station.difference("X%d"%(int(pin_map[control])+1),ground)
	return result

func input(id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> bool:
	if not is_instance_valid(station):return false
	var kind: String=""
	for entry in inputs:
		if entry.id==id:kind=str(entry.kind);break
	if kind.is_empty():return false
	var action: Dictionary={"op":"input","id":id,"pressed":pressed,"hold":true,"reverse":reverse}
	if not IO.defaults(kind).is_empty():
		var current: Dictionary=station.board.get("io_controls",{}).get(id,IO.defaults(kind))
		var submitted: Dictionary=command.duplicate(true)
		submitted.revision=int(current.get("revision",0))
		action.command=submitted
	return station.apply(action)==""
