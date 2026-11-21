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
 print("PASS: independent, asymmetric and singular matrix blocks agree with dense solver; invalid netlists rejected")
 quit()
