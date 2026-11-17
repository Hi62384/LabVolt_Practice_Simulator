extends RefCounted
## Shared product definitions used by the shop and authoritative purchase validator.
static func guaranteed() -> Array:
 return [
  {"name":"Resistor box","items":{"r1000":10,"r220":10,"r10000":10}},
  {"name":"Capacitor box","items":{"c0.1":4,"c1.0":4,"c10.0":4}},
  {"name":"Semiconductor starter","items":{"diode":6,"led":6}},
  {"name":"ETY155 lab kit","kit_tier":"large","items":{"r100":4,"r220":4,"r330":4,"r470":4,"r1000":4,"r2200":4,"r4700":4,"r10000":4,"r47000":3,"r100000":3,"pot10k":1,"led":3,"diode":3,"button":2,"toggle":2,"c0.1":2,"c1.0":2,"c10.0":2}},
  {"name":"DGS266 digital lab kit","kit_tier":"large","items":{"r220":6,"r330":6,"r1000":4,"r10000":4,"led":4,"led_green":4,"button":4,"toggle":4,"hc00":2,"hc02":1,"hc04":1,"hc08":1,"hc32":1,"hc86":1,"flip74":1,"seven_segment_ca":1,"ls47":1}}
 ]
static func find(items: Dictionary) -> Dictionary:
 for bundle in guaranteed():
  if bundle.items==items:return bundle
 return {}
