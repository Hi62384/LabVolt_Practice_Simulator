extends RefCounted
## Runs one mounted PCB through the same circuit and firmware station as a
## standalone board. The host alone owns this runtime and publishes voltages.
const Board=preload("res://scripts/breadboard_model.gd")
const Station=preload("res://scripts/dc_station.gd")
const IO=preload("res://scripts/io_devices/controls.gd")
# World actuators update at 20 Hz, but internal RLC and digital circuits need
# much finer integration to preserve their 0.5-1 ms component timings.
const INTERNAL_STEP := 0.0005
const MAX_INTERNAL_STEPS := 100
# Allow a bounded multi-slice call without silently losing simulation time.
const MAX_TICK_SECONDS := 0.2
var station: RefCounted
var pin_map: Dictionary={}
var inputs: Array=[]
const NativeHost=preload("res://scripts/native_circuit_host.gd")
var native_host=NativeHost.new()
var native_backlog:=0.0

func configure(id: String,definitions: Dictionary,mapping: Dictionary) -> bool:
	# A rejected reconfiguration must not leave the previous powered circuit
	# or its input controls available under a stale pin map.
	native_host.close()
	native_backlog=0.0
	station=null
	pin_map.clear()
	inputs.clear()
	var board: Dictionary=Board.standalone(id,definitions)
	if board.is_empty():return false
	# Do not let a malformed mapping crash the station or short its supply.
	# Match invention validation before creating a live circuit instance.
	if preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd").validate_pcb_pin_map(definitions[id],mapping)!="":return false
	station=Station.new()
	station.board=board
	station.board_epoch=1
	station.master=true
	station.channels[0].enabled=true
	station.channels[0].voltage=5.0
	station.channels[0].limit=.5
	station.wires=[["CH1+","X%d"%(int(mapping.power)+1)],["CH1-","X%d"%(int(mapping.ground)+1)]]
	pin_map=mapping.duplicate(true)
	for device in Board.devices(board):
		var kind: String=Board.manual_input_type(str(device.part.type))
		if kind.is_empty() and not IO.defaults(str(device.part.type)).is_empty():kind=str(device.part.type)
		if kind.is_empty():continue
		inputs.append({"id":str(device.id),"name":str(device.part.get("type","Input"))+" · "+str(device.id).get_file(),"kind":kind})
	return true

func input_states() -> Dictionary:
	# Publish only small manual-control values, never firmware or nonvolatile
	# memory. These states let every observer see the real positions of inputs.
	if not is_instance_valid(station):return {}
	var by_id: Dictionary={}
	for device in Board.devices(station.board):by_id[str(device.id)]=device.part
	var manual: Dictionary=station.board.get("controls",{})
	var io: Dictionary=Board.io_inputs(station.board)
	var states: Dictionary={}
	for input in inputs:
		var id: String=str(input.id)
		var kind: String=str(input.kind)
		var initial: Dictionary=by_id.get(id,{})
		var state: Dictionary={}
		if not IO.defaults(kind).is_empty():
			state=io.get(id,IO.defaults(kind)).duplicate(true)
		else:
			for field in ["pressed","setting","source_voltage","source_frequency","source_wave"]:
				if initial.has(field):state[field]=initial[field]
			state.merge(manual.get(id,{}),true)
			if kind in ["battery_adjustable","battery_generator","battery_generator_adjustable"]:
				var source: Dictionary=preload("res://scripts/electronics_catalog.gd").simulation_entry(str(initial.get("type","")))
				if not source.is_empty():
					if not state.has("source_voltage"):state.source_voltage=float(source.get("value",5.0))
					if not state.has("source_frequency"):state.source_frequency=float(source.get("frequency",60.0))
					if not state.has("source_wave"):state.source_wave=0
		states[id]=state
	return states

func close() -> void:
	# RefCounted predelete can run after member references have been released.
	# Closing an unconfigured/partially constructed PCB must be idempotent.
	if is_instance_valid(native_host):native_host.close()
	native_backlog=0.0

func tick(dt: float) -> Dictionary:
	if not is_instance_valid(station):return {"A":0.0,"B":0.0,"ok":false}
	if not is_finite(dt) or dt<=0.0:return {"A":0.0,"B":0.0,"ok":false,"error":"Invalid PCB simulation step."}
	if dt>MAX_TICK_SECONDS:return {"A":0.0,"B":0.0,"ok":false,"error":"PCB simulation step exceeds 200 ms; split it into smaller steps."}
	# A single 50 ms backward-Euler step badly underestimates RC charging and
	# can skip switch edges, firmware updates and short pulses altogether.
	# Keep the same <= 1 ms integrations while consuming the *entire* supplied
	# timestep. Previously dt > 50 ms silently discarded elapsed simulation time.
	native_host.refresh([station])
	if not native_host.fault.is_empty():
		return {"ok":false,"error":native_host.fault,"A":0.0,"B":0.0}
	if native_host.active:
		# Compiled Uno/Nano/Pico programs require the same host-owned electrical
		# barrier as physical DC benches; a plain DcStation never executes them.
		# Keep unconsumed time while the Node sidecar replies asynchronously.
		native_backlog+=dt
		if not station.result.get("ok",false):
			station.step(INTERNAL_STEP)
			native_backlog=maxf(0.0,native_backlog-INTERNAL_STEP)
		var advances:=0
		while native_backlog+1e-10>=INTERNAL_STEP and advances<MAX_INTERNAL_STEPS*4:
			advances+=1
			if not native_host.advance([station],[],INTERNAL_STEP,false):break
			native_backlog=maxf(0.0,native_backlog-INTERNAL_STEP)
		if not native_host.fault.is_empty():
			return {"ok":false,"error":native_host.fault,"A":0.0,"B":0.0}
	else:
		var slices: int=clampi(ceili(dt/0.05),1,4)
		var duration: float=dt/float(slices)
		var steps: int=clampi(ceili(duration/INTERNAL_STEP),1,MAX_INTERNAL_STEPS)
		var step_duration: float=duration/float(steps)
		for slice in slices:
			for index in steps:
				station.step(step_duration)
				if not bool(station.result.get("ok",false)):break
			if not bool(station.result.get("ok",false)):break
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
	# Portable sources need an explicit adjustment target. Without this field
	# the station accepts the command but never changes the source output.
	if kind in ["battery_adjustable","battery_generator","battery_generator_adjustable"]:
		var settings: Array=["wave"] if kind=="battery_generator" else ["voltage"] if kind=="battery_adjustable" else ["voltage","frequency","wave"]
		var setting: Variant=command.get("source_adjust",settings[0])
		if not setting is String or setting not in settings:return false
		action.source_adjust=setting
	if not IO.defaults(kind).is_empty():
		var current: Dictionary=station.board.get("io_controls",{}).get(id,IO.defaults(kind))
		var submitted: Dictionary=command.duplicate(true)
		submitted.revision=int(current.get("revision",0))
		action.command=submitted
	return station.apply(action)==""

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:close()
