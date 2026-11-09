extends SceneTree
func _initialize():
 var S=load("res://scripts/electronics_solver.gd").new();var D=load("res://scripts/device_models.gd")
 var parts=D.expand({"kind":"opamp"},"amp",["in","feedback","supply","g","out"],{})
 parts.append_array([{"id":"s","kind":"V","a":"supply","b":"g","value":5.,"resistance":.001},{"id":"signal","kind":"V","a":"in","b":"g","value":1.,"resistance":.001},{"id":"load","kind":"R","a":"out","b":"g","value":1000.}])
 var result=S.solve(parts,[["out","feedback"]]);assert(result.ok);assert(abs(result.drop.load-1.)<.0001)
 parts.append_array([{"id":"top","kind":"R","a":"out","b":"feedback","value":10000.},{"id":"bottom","kind":"R","a":"feedback","b":"g","value":10000.}])
 result=S.solve(parts);assert(result.ok);assert(abs(result.drop.load-2.001)<.0001)
 for p in parts:
  if p.id=="signal":p.value=4.
 result=S.solve(parts);assert(result.ok);assert(result.drop.load<5. and result.drop.load>4.7)
 for p in parts:
  if p.id=="signal":p.value=-1.
 result=S.solve(parts);assert(result.ok);assert(abs(result.drop.load)<.0001)
 print("PASS: op-amp follower, gain-two feedback, upper/lower saturation with real load")
 quit()

