extends RefCounted
## Authoritative deployment epochs and momentary-I/O leases. No electrical state.
var epochs := [0,0,0]
var leases := {}
var next_request := 0
func advance(station: int) -> int:
 if station<0 or station>=epochs.size():return -1
 epochs[station]+=1
 return epochs[station]
func check(peer: int,station: int,epoch: Variant,id: String,kind: String,command: Dictionary,view := "") -> String:
 if peer<=0 or station<0 or station>=epochs.size():return "Invalid input actor/station"
 if not epoch is int or epoch!=epochs[station]:return "Board changed; refresh the input"
 if not id.begins_with("board/") or id.length()>256 or view.length()>96 or var_to_bytes(command).size()>1024:return "Invalid input payload"
 var key := str(station)+":"+id
 if leases.has(key) and int(leases[key].peer)!=peer:return "Another player is using this control"
 if leases.has(key) and str(leases[key].get("view",""))!=view:return "Another view is holding this control"
 if leases.has(key) and (leases[key].epoch!=epoch or leases[key].kind!=kind):return "Control changed; refresh the input"
 return ""
static func release_command(kind: String,command: Dictionary) -> bool:
 if kind=="io_keypad":return command.get("op")=="release" or (command.get("op")=="key" and command.get("pressed") is bool and not command.pressed)
 if kind=="xpt2046":return command.get("op")=="release" or (command.get("op")=="touch" and command.get("pressed") is bool and not command.pressed)
 return kind=="io_joystick" and (command.get("op")=="release" or (command.get("op")=="press" and command.get("pressed") is bool and not command.pressed))
func commit(peer: int,station: int,id: String,kind: String,state: Dictionary,view := "") -> void:
 var key := str(station)+":"+id
 var held := kind=="io_keypad" and int(state.get("keys",0))!=0
 if kind=="io_joystick":held=bool(state.get("pressed",false)) or absf(float(state.get("x",.5))-.5)>.000001 or absf(float(state.get("y",.5))-.5)>.000001
 if kind=="xpt2046":held=bool(state.get("pressed",false))
 if held:leases[key]={"peer":peer,"station":station,"id":id,"kind":kind,"epoch":epochs[station],"view":view}
 else:leases.erase(key)
func take_peer(peer: int) -> Array:
 var result: Array=[]
 for key in leases.keys():
  if int(leases[key].peer)==peer:result.append(leases[key]);leases.erase(key)
 return result
func take_station(station: int) -> Array:
 var result: Array=[]
 for key in leases.keys():
  if int(leases[key].station)==station:result.append(leases[key]);leases.erase(key)
 return result

func capture(station: int,id: String,kind: String,command: Dictionary) -> Dictionary:
 if station<0 or station>=epochs.size():return {}
 next_request+=1
 return {"station":station,"id":id,"kind":kind,"board_epoch":epochs[station],"request_id":next_request,"command":command.duplicate(true)}
static func matches_ack(captured: Dictionary,ack: Dictionary) -> bool:
 for key in ["station","id","board_epoch","request_id"]:
  if not captured.has(key) or not ack.has(key) or captured[key]!=ack[key]:return false
 return true
