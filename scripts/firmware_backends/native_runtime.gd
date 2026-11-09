extends RefCounted
## Explicit lockstep handshake for integrator-owned host circuit orchestration.
## begin_step -> poll_step; commit electrical time only when ready==true.
const Bridge=preload("res://scripts/firmware_backends/native_bridge.gd")
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
var bridge := Bridge.new()
var model: Dictionary={}
var state: Dictionary={"powered":false,"outputs":{},"modes":{},"status":"Not loaded","serial":[],"time":0.0,"line":0}
var electrical_bus := false # Host capability; never populated from player program data.
var loading := false
var failed := false

func load_program(node_executable: String,firmware: Dictionary,backend_directory := "") -> bool:
	var board := str(firmware.get("board",""))
	if not Adapter.catalog().has(board):return fail("Unsupported native board")
	model=Adapter.catalog()[board]
	if not bridge.start(node_executable,backend_directory):return fail(bridge.last_error)
	var command := {"op":"load","board":board,"image":str(firmware.get("image",""))}
	if board=="pico":command.vector_offset=int(firmware.get("vector_offset",256))
	failed=false;loading=true
	if not bridge.request(command):return fail(bridge.last_error)
	return true

func begin_step(nodes: Array,voltages: Dictionary,dt: float,run := true,controls: Dictionary={}) -> bool:
	if failed or loading or bridge.pending:return false
	if not is_finite(dt) or dt<0 or dt>.0005:return fail("Native circuit slices must be 0–0.5 ms")
	var command := Adapter.tick_request(model,nodes,voltages,dt,run)
	if command.has("error"):return fail(command.error)
	if electrical_bus:command.electrical_bus=true
	# Only emulator controls, never executable paths or host capabilities.
	for key in ["reset","step","resume","breakpoints","uart_rx","aref"]:
		if controls.has(key):command[key]=controls[key]
	return bridge.request(command)

func poll_step() -> Dictionary:
	if failed:return {"ready":true,"ok":false,"state":state}
	var reply := bridge.poll()
	if reply.is_empty():return {"ready":false}
	if not reply.get("ok",false):fail(str(reply.get("error","Native backend error")));return {"ready":true,"ok":false,"state":state}
	if int(reply.state.get("dropped_events",0))>0 or reply.state.get("status","")=="Instruction budget reached":
		fail("Native slice exceeded event/instruction budget; reduce circuit time step");return {"ready":true,"ok":false,"state":state}
	state=reply.state;loading=false
	return {"ready":true,"ok":true,"state":state}

func fail(message: String) -> bool:
	failed=true;loading=false;bridge.close()
	state={"powered":false,"outputs":{},"modes":{},"status":message,"serial":[],"time":0.0,"line":0}
	return false

func reset() -> bool:
	if failed or loading or bridge.pending:return false
	return bridge.request({"op":"reset"})

func close() -> void:
	bridge.close();state.outputs={};state.powered=false
