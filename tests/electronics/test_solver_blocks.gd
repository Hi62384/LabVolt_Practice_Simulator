extends SceneTree
const Solver=preload("res://scripts/electronics_solver.gd")
func _initialize() -> void:
 var rng=RandomNumberGenerator.new();rng.seed=874213
 var cached_solver=Solver.new()
 for trial in 80:
  var n=20
  var order=[]
  for i in n:order.append(i)
  for i in range(n-1,0,-1):
   var j=rng.randi_range(0,i);var value=order[i];order[i]=order[j];order[j]=value
  var m=[];var b=PackedFloat64Array();b.resize(n)
  for i in n:
   var row=PackedFloat64Array();row.resize(n);m.append(row);b[i]=rng.randf_range(-8,8)
  for i in n:
   var row_index: int=order[i];m[row_index][row_index]=rng.randf_range(4,8)
   for j in n:
    if i!=j and int(i/5)==int(j/5) and rng.randf()<.35:
     m[row_index][order[j]]=rng.randf_range(-.4,.4)
  var dense=Solver._gaussian_dense(m.duplicate(true),b.duplicate())
  var blocked=Solver.gaussian(m.duplicate(true),b.duplicate())
  var cached=cached_solver._solve_cached(m,b)
  var cached_again=cached_solver._solve_cached(m,b)
  if not dense.ok or not blocked.ok or not cached.ok or not cached_again.ok:push_error("Nonsingular block system failed");quit(1);return
  for i in n:
   if absf(dense.x[i]-blocked.x[i])>1e-10 or absf(dense.x[i]-cached.x[i])>1e-10 or absf(dense.x[i]-cached_again.x[i])>1e-10:push_error("Block solution differs from dense solve");quit(1);return
 # Exercise multiple row pivots and changed right-hand sides on a cached matrix.
 var pivot_matrix=[PackedFloat64Array([0,2,1]),PackedFloat64Array([0,0,3]),PackedFloat64Array([4,1,2])]
 for rhs in [PackedFloat64Array([1,2,3]),PackedFloat64Array([-4,7,0])]:
  var direct=Solver._gaussian_dense(pivot_matrix.duplicate(true),rhs.duplicate())
  var reused=cached_solver._solve_cached(pivot_matrix,rhs)
  if not direct.ok or not reused.ok:push_error("Pivoted solve failed");quit(1);return
  for i in 3:
   if absf(direct.x[i]-reused.x[i])>1e-10:push_error("Pivoted cached solution differs");quit(1);return
 pivot_matrix[0][1]=5
 var changed_rhs=PackedFloat64Array([3,4,5])
 var changed=Solver._gaussian_dense(pivot_matrix.duplicate(true),changed_rhs.duplicate())
 var invalidated=cached_solver._solve_cached(pivot_matrix,changed_rhs)
 for i in 3:
  if absf(changed.x[i]-invalidated.x[i])>1e-10:push_error("Changed matrix reused stale factors");quit(1);return
 var singular=[];var zero=PackedFloat64Array();zero.resize(12)
 for i in 12:
  var row=PackedFloat64Array();row.resize(12);singular.append(row)
 if Solver.gaussian(singular,zero).ok or cached_solver._solve_cached(singular,zero).ok:push_error("Singular matrix accepted");quit(1);return
 # Invalid imported netlists must fail with a meaningful error, not overwrite
 # device branches or propagate non-finite values into the native MNA kernel.
 var invalid_parts: Array=[
  {"id":"same","kind":"R","a":"a","b":"b","value":100.0},
  {"id":"same","kind":"V","a":"b","b":"a","value":5.0}
 ]
 var bad=Solver.new().solve(invalid_parts)
 if bad.get("ok",true) or not str(bad.get("error","")).contains("Duplicate"):push_error("Duplicate component IDs were accepted");quit(1);return
 bad=Solver.new().solve([{"id":"r","kind":"R","a":"a","b":"b","value":100.0}],[],-.01)
 if bad.get("ok",true) or not str(bad.get("error","")).contains("timestep"):push_error("Negative timestep was accepted");quit(1);return
 bad=Solver.new().solve([{"id":"r","kind":"R","a":"a","b":"b","value":100.0}],[],NAN)
 if bad.get("ok",true) or not str(bad.get("error","")).contains("timestep"):push_error("Non-finite timestep was accepted");quit(1);return
 bad=Solver.new().solve([{"id":"r","a":"a","b":"b","value":100.0}])
 if bad.get("ok",true) or not str(bad.get("error","")).contains("Invalid"):push_error("Missing component kind was accepted");quit(1);return
 # Malformed imported components must return an error before any numerical
 # stamp or held-transient conversion, including C# kernel input.
 var bad_models: Array=[
  [{"id":"bad","kind":"R","a":"a","b":"b","value":NAN},"value"],
  [{"id":"bad","kind":"R","a":"a","b":"b","value":"100"},"value"],
  [{"id":"bad","kind":"R","a":"a","b":"b","value":-4.0},"value"],
  [{"id":"bad","kind":"R","a":"a","b":"b"},"value"],
  [{"id":"bad","kind":"C","a":"a","b":"b","value":INF},"value"],
  [{"id":"bad","kind":"C","a":"a","b":"b","value":-0.001},"value"],
  [{"id":"bad","kind":"L","a":"a","b":"b","value":0.1,"mutual":NAN},"mutual"],
  [{"id":"bad","kind":"D","a":"a","b":"b","ron":0.0},"ron"],
  [{"id":"bad","kind":"D","a":"a","b":"b","ron":-2.0},"ron"],
  [{"id":"bad","kind":"LED","a":"a","b":"b","vf":-0.1},"vf"],
  [{"id":"bad","kind":"V","a":"a","b":"b","value":INF},"value"],
  [{"id":"bad","kind":"V","a":"a","b":"b","value":5.0,"capacity_ah":NAN},"capacity_ah"],
  [{"id":"bad","kind":"V","a":"a","b":"b","value":5.0,"capacity_ah":-1.0},"capacity_ah"],
  [{"id":"bad","kind":"V","a":"a","b":"b","value":5.0,"resistance":-0.5},"resistance"],
  [{"id":"bad","kind":"I","a":"a","b":"b"},"value"],
  [{"id":"bad","kind":"supply","a":"a","b":"b","value":5.0,"limit":-1.0},"limit"],
  [{"id":"bad","kind":"current_source","a":"a","b":"b","value":0.01,"compliance":5.0,"rout":0.0},"rout"],
  [{"id":"bad","kind":"current_source","a":"a","b":"b","value":0.01},"compliance"],
  [{"id":"bad","kind":"T","a":"a","b":"b","cp":"c","cn":"d"},"ratio"],
  [{"id":"bad","kind":"T","a":"a","b":"b","cp":"c","cn":"d","ratio":0.0},"ratio"],
  [{"id":"bad","kind":"E","a":"a","b":"b","cp":"c","cn":"d","high":"h"},"gain"],
  [{"id":"bad","kind":"F","a":"a","b":"b","control":"diode","gain":NAN},"gain"]
 ]
 for case in bad_models:
  var invalid: Dictionary=Solver.new().solve([case[0]])
  if invalid.get("ok",true) or not str(invalid.get("error","")).contains(str(case[1])):
   push_error("Invalid "+str(case[1])+" accepted or misreported: "+str(case[0])+" => "+str(invalid))
   quit(1);return
 var held_invalid=Solver.new().solve([{"id":"invalid_storage","kind":"C","a":"a","b":"b","value":NAN}],[],0.0,true)
 if held_invalid.get("ok",true) or not str(held_invalid.get("error","")).contains("value"):
  push_error("Held transient bypassed primitive validation");quit(1);return
 var non_string_wire=Solver.new().solve([{"id":"r","kind":"R","a":"a","b":"b","value":100.0}],[[123,"b"]])
 if non_string_wire.get("ok",true) or not str(non_string_wire.get("error","")).contains("wire"):
  push_error("Wire with non-string endpoint was accepted");quit(1);return
 var signed=Solver.new().solve([
  {"id":"battery","kind":"V","a":"a","b":"b","value":-5.0,"resistance":0.0},
  {"id":"load","kind":"R","a":"a","b":"b","value":100.0}])
 if not signed.get("ok",false) or absf(float(signed.get("drop",{}).get("load",0.0))+5.0)>1e-8:
  push_error("Valid negative-voltage source changed while guarding malformed ratings");quit(1);return
 # Zero-storage and zero-output primitives must not join independent
 # reference islands, and editing a capacitance across zero must invalidate
 # the cached topology rather than reuse a singular matrix layout.
 var floating_parts: Array=[
  {"id":"left_source","kind":"V","a":"lp","b":"ln","value":5.0},
  {"id":"left_load","kind":"R","a":"lp","b":"ln","value":1000.0},
  {"id":"right_source","kind":"V","a":"rp","b":"rn","value":9.0},
  {"id":"right_load","kind":"R","a":"rp","b":"rn","value":2000.0},
  {"id":"open_cap","kind":"C","a":"ln","b":"rn","value":0.0},
  {"id":"open_current","kind":"I","a":"lp","b":"rp","value":0.0},
  {"id":"control_diode","kind":"D","a":"ln","b":"lp","vf":0.65,"ron":2.0},
  {"id":"zero_gain","kind":"F","a":"ln","b":"rn","control":"control_diode","gain":0.0}
 ]
 var island_solver=Solver.new()
 var open_result=island_solver.solve(floating_parts,[],.01)
 if not open_result.get("ok",false) or absf(float(open_result.get("drop",{}).get("left_load",0.0))-5.0)>.001 or absf(float(open_result.get("drop",{}).get("right_load",0.0))-9.0)>.001:
  push_error("Open storage/current and zero-gain output merged independent reference islands: "+str(open_result));quit(1);return
 floating_parts[4].value=.000001
 var bridged_result=island_solver.solve(floating_parts,[],.01)
 if not bridged_result.get("ok",false):push_error("Connecting a real capacitor invalidated valid islands");quit(1);return
 floating_parts[4].value=0.0
 var reopened_result=island_solver.solve(floating_parts,[],.01)
 if not reopened_result.get("ok",false) or absf(float(reopened_result.get("drop",{}).get("right_load",0.0))-9.0)>.001:
  push_error("Opening capacitor failed to invalidate cached topology: "+str(reopened_result));quit(1);return
 print("PASS: independent, asymmetric and singular matrix blocks agree with dense solver; invalid netlists rejected")
 quit()
