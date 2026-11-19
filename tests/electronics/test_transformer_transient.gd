extends SceneTree
func _initialize():
 var S=load("res://scripts/electronics_solver.gd").new()
 var parts=[{"id":"s","kind":"V","a":"p","b":"g","value":12.,"resistance":.001},{"id":"mag","kind":"R","a":"p","b":"g","value":10000.},{"id":"t","kind":"T","a":"a","b":"b","cp":"p","cn":"g","ratio":.5},{"id":"load","kind":"R","a":"a","b":"b","value":100.}]
 var result=S.solve(parts);assert(result.ok)
 assert(abs(result.drop.load-6.)<.001)
 assert(abs(result.i.s+.5*result.i.load+result.i.mag)<.000001)
 assert(result.islands.p!=result.islands.a)
 assert(abs(result.drop.s*result.i.s+result.drop.load*result.i.load+result.drop.mag*result.i.mag)<.000001)
 assert(absf(result.i.t+result.i.load)<1e-9)
 assert(absf(result.winding_currents.t.primary-.5*result.i.load)<1e-9)
 assert(absf(result.winding_currents.t.secondary-result.i.t)<1e-9)
 var load_part: Dictionary=parts.pop_back()
 result=S.solve(parts)
 assert(result.ok and absf(result.i.t)<1e-9 and absf(result.drop.t-6.0)<.001)
 parts.append(load_part)
 parts[2].cp="g"
 parts[2].cn="p"
 result=S.solve(parts)
 assert(result.ok and absf(result.drop.load+6.0)<.001)
 assert(absf(result.i.t+result.i.load)<1e-9)
 assert(absf(result.i.s-.5*result.i.load+result.i.mag)<1e-9)
 print("PASS: transformer branch currents, loaded/open/reversed windings, isolation and power conservation")
 quit()
