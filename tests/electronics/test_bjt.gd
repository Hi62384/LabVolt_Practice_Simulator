extends SceneTree
func _initialize():
 var S=load("res://scripts/electronics_solver.gd");var D=load("res://scripts/device_models.gd");var catalog=load("res://scripts/electronics_catalog.gd").all()
 for polarity in ["npn","pnp"]:
  var inverted=polarity=="pnp"
  for rb in [1000000.,1000.]:

   var parts=[{"id":"v","kind":"V","a":"v","b":"g","value":5.,"resistance":.01},{"id":"rb","kind":"R","a":"b","b":"g" if inverted else "v","value":rb},{"id":"rc","kind":"R","a":"c","b":"g" if inverted else "v","value":1000.}]
   parts.append_array(D.expand(catalog[polarity],"q",["c","b","v" if inverted else "g"],{}))
   var result=S.new().solve(parts)
   assert(result.ok)
   var ib=abs(float(result.i.rb));var ic=abs(float(result.i.rc))
   if rb>10000:assert(abs(ic/ib-99)<.1)
   else:assert(ic>.004 and ic<.0051)
  var off=[{"id":"v","kind":"V","a":"v","b":"g","value":5.,"resistance":.01},{"id":"rb","kind":"R","a":"b","b":"v" if inverted else "g","value":1000.},{"id":"rc","kind":"R","a":"c","b":"g" if inverted else "v","value":1000.}]
  off.append_array(D.expand(catalog[polarity],"q",["c","b","v" if inverted else "g"],{}))
  var result=S.new().solve(off);assert(result.ok);assert(abs(float(result.i.rc))<.000001)
 print("PASS: NPN and PNP forward-active gain, saturated load current, cutoff")
 quit()

