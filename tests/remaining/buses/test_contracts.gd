extends SceneTree
func _initialize() -> void:
 var failed := 0
 for path in ["res://scripts/electronics_buses/group_scheduler.gd","res://scripts/electronics_buses/station_adapter.gd","res://scripts/firmware_backends/native_boards.gd","res://scripts/firmware_backends/pin_metadata.gd"]:
  var script=load(path)
  if script==null or not script.can_instantiate():failed+=1;print("FAIL ",path)
  else:print("PASS ",path)
 var boards=preload("res://scripts/firmware_backends/native_boards.gd")
 var model: Dictionary=boards.catalog().native_nano
 if model.pins.size()!=30:failed+=1
 var logical: Array=boards.logical_nodes("nano","n",model.pins)
 if logical.size()!=24 or logical[0]!="5V" or logical[1]!="GND1" or logical[-2]!="A6":failed+=1
 var metadata=preload("res://scripts/firmware_backends/pin_metadata.gd").pins("nano")
 if metadata[24].role!="ADC input only" or metadata[25].role!="ADC input only":failed+=1;print("FAIL Nano analog-only header role")
 else:print("PASS Nano A6/A7 physical metadata explicitly rejects GPIO output role")
 var solver=preload("res://scripts/electronics_solver.gd").new()
 var circuit: Array=[{"id":"v","kind":"V","a":"v","b":"g","value":5.,"resistance":0.},{"id":"r","kind":"R","a":"v","b":"c","value":1000.},{"id":"c","kind":"C","a":"c","b":"g","value":.000001}]
 var charged: Dictionary=solver.solve(circuit,[],.001)
 var before: Dictionary=solver.memory.duplicate(true);var time: float=solver.time
 circuit[0].value=0.
 var held: Dictionary=preload("res://scripts/electronics_buses/held_state.gd").solve(solver,circuit)
 if not held.ok or absf(float(held.v.c)-float(held.v.g)-float(before.c))>1e-10 or solver.memory!=before or solver.time!=time:failed+=1;print("FAIL zero-time capacitor hold")
 else:print("PASS zero-time capacitor voltage/memory/time held through existing solver")
 solver.memory={"l":.0123};time=solver.time
 var inductive: Array=[{"id":"r","kind":"R","a":"x","b":"g","value":1000.},{"id":"l","kind":"L","a":"x","b":"g","value":.01}]
 held=preload("res://scripts/electronics_buses/held_state.gd").solve(solver,inductive)
 if not held.ok or absf(float(held.i.l)-.0123)>1e-12 or solver.time!=time or solver.memory.l!=.0123:failed+=1;print("FAIL zero-time inductor hold")
 else:print("PASS zero-time inductor current/memory/time held through existing solver")
 print("CONTRACT FAILURES: ",failed);quit(failed)
