extends RefCounted
## Zero-time companion-netlist adapter for the EXISTING MNA solver.
## Capacitor voltage and inductor current stay at their committed memory values.
## No fictitious epsilon timestep and no second numerical solver.
static func solve(solver: RefCounted,parts: Array,wires: Array=[]) -> Dictionary:
 var held: Array=[]
 for source in parts:
  var part: Dictionary=source.duplicate(true)
  if part.kind=="C":
   part.kind="V";part.value=float(solver.memory.get(str(part.id),0.));part.resistance=0.
  elif part.kind=="L":
   part.kind="I";part.value=float(solver.memory.get(str(part.id),0.))
  held.append(part)
 # Fourth argument is deliberately omitted: the core solve hook uses a default
 # false hold flag, so conversion delegates back to the ordinary MNA path.
 return solver.solve(held,wires,0.)
