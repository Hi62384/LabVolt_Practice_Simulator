extends SceneTree
func _initialize():
 var S=load("res://scripts/electronics_solver.gd").new()
 var parts=[{"id":"s","kind":"V","a":"p","b":"g","value":12.,"resistance":.001},{"id":"mag","kind":"R","a":"p","b":"g","value":10000.},{"id":"t","kind":"T","a":"a","b":"b","cp":"p","cn":"g","ratio":.5},{"id":"load","kind":"R","a":"a","b":"b","value":100.}]
 var result=S.solve(parts);assert(result.ok)
 assert(abs(result.drop.load-6.)<.001)
 assert(abs(result.i.s+.5*result.i.load+result.i.mag)<.000001)
 assert(result.islands.p!=result.islands.a)
 assert(abs(result.drop.s*result.i.s+result.drop.load*result.i.load+result.drop.mag*result.i.mag)<.000001)
 print("PASS: transformer voltage ratio, reflected current, isolation and power conservation")
 quit()
