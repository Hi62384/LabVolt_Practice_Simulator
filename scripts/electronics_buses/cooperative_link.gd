extends RefCounted
## Optional integrator adapter around the SAME NativeRuntime, not a second CPU.
## One link per native CPU. Core must synchronize coupled links before advancing
## electrical time; do not independently run this on multiplayer clients.
const Replay=preload("res://scripts/electronics_buses/edge_replay.gd")
var runtime: RefCounted
var board_epoch := -1
var before := {}
var waiting := false
var request_seconds := 0.
func bind(native_runtime: RefCounted,epoch: int) -> void:
 runtime=native_runtime;runtime.electrical_bus=true;board_epoch=epoch;before={};waiting=false
func begin(epoch: int,nodes: Array,voltages: Dictionary,dt: float,run: bool,controls: Dictionary={}) -> bool:
 if runtime==null or epoch!=board_epoch or waiting:return false
 before=runtime.state.duplicate(true);request_seconds=dt
 waiting=runtime.begin_step(nodes,voltages,dt,run,controls)
 return waiting
func poll(epoch: int,solve: Callable) -> Dictionary:
 if runtime==null or epoch!=board_epoch:return {"ready":true,"ok":false,"error":"Native bus board epoch changed"}
 if not waiting:return {"ready":false}
 var packet: Dictionary=runtime.poll_step()
 if not packet.get("ready",false):return packet
 waiting=false
 if not packet.get("ok",false):return packet
 var state: Dictionary=packet.state
 var hz := 16000000. if state.get("board") in ["uno","nano"] else 125000000.
 var result := Replay.replay(before,state,hz,solve)
 result.ready=true;result.state=state;result.remaining=maxf(0.,request_seconds-float(result.get("elapsed",0.)))
 return result
func invalidate() -> void:
 board_epoch=-1;waiting=false;before={}
 if runtime!=null:runtime.electrical_bus=false
 runtime=null
