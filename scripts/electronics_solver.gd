extends RefCounted
const LinearKernel=preload("res://scripts/electronics/MnaLinearKernel.cs")
## Double precision MNA. Backward Euler storage, piecewise-linear diodes,
## isolated CV/CC sources. No invented ground path: one reference per island.
var memory := {}
var battery_discharge := {}
var time := 0.0
var last := {}
var network_solver: RefCounted
var topology_key := []
var topology := {}
# Exact stamped matrices only; source voltages and transient history remain in RHS.
var factor_cache: Array[Dictionary] = []
var linear_kernel=LinearKernel.new()
var use_csharp:=true

func reset() -> void:
	memory.clear();battery_discharge.clear();time=0;last={};network_solver=null;factor_cache.clear();linear_kernel.Reset()

func solve(parts: Array, wires: Array = [], dt := 0.0,hold_transients := false) -> Dictionary:
	if dt==0. and hold_transients:return preload("res://scripts/electronics_buses/held_state.gd").solve(self,parts,wires)
	if parts.size()>96:return {"ok":false,"error":"Circuit exceeds 96-device solver limit."}
	var devices := {};var nonlinear_parts: Array=[];var battery_parts: Array=[]
	for part in parts:
		devices[str(part.id)]=part
		if part.kind in ["D","LED","E","current_source","supply"]:nonlinear_parts.append(part)
		if part.kind=="V" and float(part.get("capacity_ah",0.0))>0.0:battery_parts.append(part)
	var layout := _layout(parts,wires,dt>0.0)
	var net: Dictionary=layout.net
	var groups: Dictionary=layout.groups
	var idx: Dictionary=layout.idx
	var branches: Dictionary=layout.branches
	var count: int=idx.size()+branches.size()
	if count==0:return {"ok":true,"v":{},"i":{},"mode":{},"islands":{},"time":time}
	var guess := PackedFloat64Array();guess.resize(count)
	var modes := {};var diode_on := {}
	var solution := PackedFloat64Array()
	var converged := false
	for iteration in range(40):
		var matrix: Array=[];var rhs := PackedFloat64Array();rhs.resize(count)
		for j in range(count):
			var row := PackedFloat64Array();row.resize(count);matrix.append(row)
		for p in parts:
			var a: int=idx.get(net[str(p.a)],-1);var b: int=idx.get(net[str(p.b)],-1)
			var id := str(p.id);var value := float(p.get("value",0))
			match str(p.kind):
				"R":conductance(matrix,a,b,1.0/maxf(value,.001))
				"C":
					if dt>0:
						var g := value/dt
						conductance(matrix,a,b,g);current(rhs,a,b,-g*float(memory.get(id,0)))
				"D","LED":
					var on: bool=diode_on.get(id,false)
					var g: float=1.0/float(p.get("ron",2.0)) if on else 1e-10
					conductance(matrix,a,b,g)
					if on:current(rhs,a,b,-g*float(p.get("vf",.65)))
				"F":
					var control: Dictionary=devices.get(str(p.get("control","")),{})
					if control.get("kind","") not in ["D","LED"]:return {"ok":false,"error":"Invalid controlled-current source"}
					var on: bool=diode_on.get(str(control.id),false)
					var g: float=float(p.get("gain",1))*(1.0/float(control.get("ron",2)) if on else 1e-10)
					var ca: int=idx.get(net[str(control.a)],-1);var cb: int=idx.get(net[str(control.b)],-1)
					add(matrix,a,ca,g);add(matrix,a,cb,-g);add(matrix,b,ca,-g);add(matrix,b,cb,g)
					if on:current(rhs,a,b,-g*float(control.get("vf",.65)))
				"T":
					var k: int=branches[id];var ratio: float=p.ratio
					var cp: int=idx.get(net[str(p.cp)],-1);var cn: int=idx.get(net[str(p.cn)],-1)
					add(matrix,a,k,1);add(matrix,b,k,-1);add(matrix,cp,k,-ratio);add(matrix,cn,k,ratio)
					add(matrix,k,a,1);add(matrix,k,b,-1);add(matrix,k,cp,-ratio);add(matrix,k,cn,ratio)
				"E":
					var k: int=branches[id]
					add(matrix,a,k,1);add(matrix,b,k,-1);add(matrix,k,a,1)
					var mode: int=modes.get(id,0)
					add(matrix,k,idx.get(net[str(p.high)],-1) if mode==1 else b,-1)
					matrix[k][k]=-float(p.get("resistance",50.))
					if mode==0:
						add(matrix,k,idx.get(net[str(p.cp)],-1),-float(p.gain))
						add(matrix,k,idx.get(net[str(p.cn)],-1),float(p.gain))
				"I":current(rhs,a,b,value)
				"current_source":
					var k: int=branches[id]
					# Finite 1 GΩ output resistance keeps an open output solvable.
					conductance(matrix,a,b,1./float(p.get("rout",1e9)))
					add(matrix,a,k,1);add(matrix,b,k,-1)
					var mode: int=modes.get(id,0)
					if mode==0:matrix[k][k]=1;rhs[k]=-value
					else:
						add(matrix,k,a,1);add(matrix,k,b,-1)
						matrix[k][k]=-float(p.get("resistance",.01));rhs[k]=float(mode)*float(p.compliance)
				"V","L","supply":
					var k: int=branches[id]
					add(matrix,a,k,1);add(matrix,b,k,-1)
					if p.kind=="supply" and modes.get(id,0)!=0:
						matrix[k][k]=1;rhs[k]=float(modes[id])*float(p.get("limit",1))
					else:
						add(matrix,k,a,1);add(matrix,k,b,-1)
						if p.kind=="L":
							var z := value/dt if dt>0 else .001
							matrix[k][k]=-z-float(p.get("resistance",0))
							rhs[k]=-z*float(memory.get(id,0)) if dt>0 else 0
							var coupled := str(p.get("coupled",""))
							if dt>0 and branches.has(coupled):
								var coupling := float(p.get("mutual",0))/dt
								add(matrix,k,int(branches[coupled]),-coupling)
								rhs[k]-=coupling*float(memory.get(coupled,0))
						else:
							var remaining := _battery_remaining(p)
							var emf := value
							var resistance := float(p.get("resistance",.01))
							if remaining >= 0.0:
								emf = value * smoothstep(0.0, .2, remaining)
								if remaining == 0.0: resistance = 1e7
							matrix[k][k] = -resistance
							rhs[k] = emf
				_:return {"ok":false,"error":"Unsupported model: "+str(p.kind)}
		var solved := _solve_cached(matrix,rhs)
		if not solved.ok:return {"ok":false,"error":"Singular circuit: conflicting ideal sources or an open measurement path."}
		solution=solved.x
		var changed := false
		for p in nonlinear_parts:
			var a: int=idx.get(net[str(p.a)],-1);var b: int=idx.get(net[str(p.b)],-1)
			var v := (solution[a] if a>=0 else 0.0)-(solution[b] if b>=0 else 0.0)
			var id := str(p.id)
			if p.kind in ["D","LED"]:
				var on: bool=v>float(p.get("vf",.65))
				if on!=diode_on.get(id,false):diode_on[id]=on;changed=true
			if p.kind=="E":
				var cp: int=idx.get(net[str(p.cp)],-1);var cn: int=idx.get(net[str(p.cn)],-1);var hi: int=idx.get(net[str(p.high)],-1)
				var demand: float=float(p.gain)*((solution[cp] if cp>=0 else 0.)-(solution[cn] if cn>=0 else 0.))
				var ceiling: float=maxf(0.,(solution[hi] if hi>=0 else 0.)-(solution[b] if b>=0 else 0.))
				var mode: int=modes.get(id,0)
				var next: int=1 if demand>ceiling+1e-7 else -1 if demand< -1e-7 else 0
				if mode!=next:modes[id]=next;changed=true
			if p.kind=="current_source":
				var mode: int=modes.get(id,0);var ceiling: float=p.compliance;var branch: float=solution[branches[id]]
				if mode==0 and absf(v)>ceiling+1e-6:modes[id]=1 if v>0 else -1;changed=true
				elif mode==1 and branch< -float(p.value)-1e-7:modes[id]=0;changed=true
				elif mode==-1 and branch> -float(p.value)+1e-7:modes[id]=0;changed=true
			if p.kind=="supply":
				var i: float=solution[branches[id]];var limit: float=p.get("limit",1)
				var mode: int=modes.get(id,0)
				if mode==0 and absf(i)>limit+1e-7:modes[id]=1 if i>0 else -1;changed=true
				elif mode==-1 and v>float(p.value)+1e-6:modes[id]=0;changed=true
				elif mode==1 and v<float(p.value)-1e-6:modes[id]=0;changed=true
		if not changed:converged=true;break
		guess=solution
	if not converged:return {"ok":false,"error":"Nonlinear operating point did not converge."}
	var voltages := {};var islands := {};var currents := {};var drops := {};var states := {}
	for pin in net:
		var n: int=idx.get(net[pin],-1)
		voltages[pin]=solution[n] if n>=0 else 0.0;islands[pin]=root(groups,net[pin])
	for p in parts:
		var id := str(p.id);var v: float=voltages[str(p.a)]-voltages[str(p.b)]
		var i := 0.0
		match str(p.kind):
			"R":i=v/maxf(float(p.value),.001)
			"C":
				if dt>0:i=float(p.value)/dt*(v-float(memory.get(id,0)));memory[id]=v
			"D","LED":i=(v-float(p.get("vf",.65)))/float(p.get("ron",2)) if diode_on.get(id,false) else v*1e-10
			"F":
				var control: Dictionary=devices[str(p.control)]
				var cv: float=voltages[str(control.a)]-voltages[str(control.b)]
				i=float(p.get("gain",1))*((cv-float(control.get("vf",.65)))/float(control.get("ron",2)) if diode_on.get(str(control.id),false) else cv*1e-10)
			"I":i=float(p.value)
			"V","L","supply","current_source":
				i=solution[branches[id]]
				if p.kind=="L" and dt>0:memory[id]=i
		currents[id]=i;drops[id]=v
		if p.kind=="current_source":states[id]="CC" if modes.get(id,0)==0 else "COMPLIANCE"
		if p.kind=="supply":states[id]="CC" if modes.get(id,0)!=0 else "CV"
	var charge := {}
	for part in battery_parts:
		var remaining := _battery_remaining(part)
		if remaining < 0.0:continue
		remaining=_drain_battery(part,float(currents[part.id]),dt,remaining)
		charge[part.id]=remaining
		states[part.id]="DEPLETED" if remaining==0.0 else "BATTERY"
	if dt>0:time+=dt
	last={"ok":true,"v":voltages,"i":currents,"drop":drops,"mode":states,"charge":charge,"islands":islands,"time":time}
	return last

func _layout(parts: Array, wires: Array, transient: bool) -> Dictionary:
	# Only node names, device kinds and ideal leads determine matrix positions.
	# All numerical stamps and history are still evaluated on each solve.
	var pins := []
	for part in parts:pins.append([part.id,part.kind,part.a,part.b])
	var key := [pins,wires,transient]
	if key==topology_key:return topology
	var parent := {}
	for p in parts:
		for pin in [p.a,p.b]:parent[str(pin)]=str(pin)
	for w in wires:
		for pin in w:parent[str(pin)]=str(pin)
	for w in wires:parent[root(parent,str(w[0]))]=root(parent,str(w[1]))
	var net := {}
	for pin in parent:net[pin]=root(parent,pin)
	var groups := {}
	for n in net.values():groups[n]=n
	for p in parts:
		if str(p.kind)=="C" and not transient:continue
		groups[root(groups,net[str(p.a)])]=root(groups,net[str(p.b)])
	var refs := {}
	for n in groups:refs[root(groups,n)]=n
	var idx := {}
	for n in groups:
		if n not in refs.values():idx[n]=idx.size()
	var branches := {}
	for p in parts:
		if p.kind in ["V","L","supply","current_source","E","T"]:branches[str(p.id)]=idx.size()+branches.size()
	topology_key=[pins,wires.duplicate(true),transient]
	topology={"net":net,"groups":groups,"idx":idx,"branches":branches}
	return topology

func reuse_flat_solution(batteries: Array, dt: float) -> bool:
	if not last.get("ok",false):return false
	for part in batteries:
		if _battery_remaining(part)<.2:return false
	for part in batteries:
		var id := str(part.id)
		last.charge[id]=_drain_battery(part,float(last.i[id]),dt,_battery_remaining(part))
		last.mode[id]="DEPLETED" if last.charge[id]==0.0 else "BATTERY"
	time+=dt
	last.time=time
	return true

func _drain_battery(part: Dictionary, amps: float, dt: float, remaining: float) -> float:
	if dt<=0.0 or remaining<=0.0:return remaining
	var capacity := float(part.capacity_ah)*3600.0
	var drain := maxf(0.0,-signf(float(part.value))*amps)
	var key := _battery_key(part)
	battery_discharge[key]=minf(capacity,float(battery_discharge.get(key,0.0))+drain*dt)
	remaining=_battery_remaining(part)
	if remaining>=.02:return remaining
	battery_discharge[key]=capacity
	return 0.0

func _battery_key(part: Dictionary) -> String:
	return str(part.id) + "|" + str(part.value)

func _battery_remaining(part: Dictionary) -> float:
	var capacity := float(part.get("capacity_ah",0.0)) * 3600.0
	if part.kind != "V" or capacity <= 0.0: return -1.0
	return clampf(1.0 - float(battery_discharge.get(_battery_key(part),0.0)) / capacity, 0.0, 1.0)

static func root(parent: Dictionary,node: String) -> String:
	var cursor := node
	while parent.get(cursor,cursor)!=cursor:cursor=parent[cursor]
	return cursor
static func add(m: Array,a: int,b: int,v: float) -> void:
	if a>=0 and b>=0:m[a][b]+=v
static func conductance(m: Array,a: int,b: int,g: float) -> void:
	add(m,a,a,g);add(m,b,b,g);add(m,a,b,-g);add(m,b,a,-g)
static func current(rhs: PackedFloat64Array,a: int,b: int,i: float) -> void:
	if a>=0:rhs[a]-=i
	if b>=0:rhs[b]+=i
func _solve_cached(matrix: Array, rhs: PackedFloat64Array) -> Dictionary:
	if not use_csharp:return _solve_cached_gd(matrix,rhs)
	var key:=hash(matrix)
	for entry in factor_cache:
		if entry.key==key and entry.matrix==matrix:return _solve_factor(entry,rhs)
	var factor: Dictionary=linear_kernel.Factorize(matrix)
	if not factor.get("ok",false):return {"ok":false}
	factor["key"]=key;factor["matrix"]=matrix.duplicate(true)
	factor_cache.push_front(factor)
	if factor_cache.size()>4:factor_cache.pop_back()
	return _solve_factor(factor,rhs)

func _solve_cached_gd(matrix: Array, rhs: PackedFloat64Array) -> Dictionary:
	# Only bit-identical stamps are reusable: switches, timestep, device modes,
	# resistance and coupling all invalidate automatically when their stamps change.
	var key := hash(matrix)
	for entry in factor_cache:
		if entry.key==key and entry.matrix==matrix:
			return _solve_factor(entry,rhs)
	var n := rhs.size()
	var lu: Array=matrix.duplicate(true)
	var permutation := PackedInt32Array();permutation.resize(n)
	for i in n:permutation[i]=i
	for k in n:
		var pivot := k
		for j in range(k+1,n):
			if absf(lu[j][k])>absf(lu[pivot][k]):pivot=j
		if absf(lu[pivot][k])<1e-14:return {"ok":false}
		var row=lu[k];lu[k]=lu[pivot];lu[pivot]=row
		var swap := permutation[k];permutation[k]=permutation[pivot];permutation[pivot]=swap
		for j in range(k+1,n):
			var factor: float=lu[j][k]/lu[k][k]
			lu[j][k]=factor
			if factor==0.0:continue
			for column in range(k+1,n):lu[j][column]-=factor*lu[k][column]
	var lower: Array=[];var upper: Array=[];var diagonal:=PackedFloat64Array();diagonal.resize(n)
	for i in n:
		var l: Array=[];var u: Array=[]
		for j in i:
			if lu[i][j]!=0.0:l.append([j,lu[i][j]])
		for j in range(i+1,n):
			if lu[i][j]!=0.0:u.append([j,lu[i][j]])
		lower.append(l);upper.append(u);diagonal[i]=lu[i][i]
	var entry := {"key":key,"matrix":matrix.duplicate(true),"lower":lower,"upper":upper,"diagonal":diagonal,"permutation":permutation}
	factor_cache.push_front(entry)
	if factor_cache.size()>4:factor_cache.pop_back()
	return _solve_factor(entry,rhs)

static func _solve_factor(entry: Dictionary,rhs: PackedFloat64Array) -> Dictionary:
	var n:=rhs.size()
	var y:=PackedFloat64Array();y.resize(n)
	for i in n:
		var value:=rhs[entry.permutation[i]]
		for term in entry.lower[i]:value-=float(term[1])*y[int(term[0])]
		y[i]=value
	var x:=PackedFloat64Array();x.resize(n)
	for i in range(n-1,-1,-1):
		var value:=y[i]
		for term in entry.upper[i]:value-=float(term[1])*x[int(term[0])]
		x[i]=value/entry.diagonal[i]
		if not is_finite(x[i]) or absf(x[i])>1e9:return {"ok":false}
	return {"ok":true,"x":x}

static func gaussian(m: Array,b: PackedFloat64Array) -> Dictionary:
	# Disconnected matrix blocks are independent even for controlled devices:
	# use actual nonzero stamps in either direction, not assumed circuit topology.
	# Solving each block separately preserves the same equations while avoiding
	# pivot and elimination work across unrelated instrument inputs.
	var n := b.size()
	if n < 12:return _gaussian_dense(m,b)
	var parent := PackedInt32Array();parent.resize(n)
	for i in n:parent[i]=i
	for i in n:
		for j in range(i+1,n):
			if m[i][j] == 0.0 and m[j][i] == 0.0:continue
			var left := i
			while parent[left]!=left:left=parent[left]
			var right := j
			while parent[right]!=right:right=parent[right]
			if left!=right:parent[right]=left
	var blocks := {}
	for i in n:
		var root_index := i
		while parent[root_index]!=root_index:root_index=parent[root_index]
		if not blocks.has(root_index):blocks[root_index]=[]
		blocks[root_index].append(i)
	if blocks.size()==1:return _gaussian_dense(m,b)
	var solution := PackedFloat64Array();solution.resize(n)
	for indices in blocks.values():
		var block: Array=[]
		var rhs := PackedFloat64Array();rhs.resize(indices.size())
		for r in indices.size():
			var row := PackedFloat64Array();row.resize(indices.size())
			for c in indices.size():row[c]=m[indices[r]][indices[c]]
			block.append(row);rhs[r]=b[indices[r]]
		var result := _gaussian_dense(block,rhs)
		if not result.ok:return result
		for r in indices.size():solution[indices[r]]=result.x[r]
	return {"ok":true,"x":solution}

static func _gaussian_dense(m: Array,b: PackedFloat64Array) -> Dictionary:
	var n := b.size()
	for k in range(n):
		var pivot := k
		for j in range(k+1,n):
			if absf(m[j][k])>absf(m[pivot][k]):pivot=j
		if absf(m[pivot][k])<1e-14:return {"ok":false}
		var temp=m[k];m[k]=m[pivot];m[pivot]=temp
		var q: float=b[k];b[k]=b[pivot];b[pivot]=q
		for j in range(k+1,n):
			var f: float=m[j][k]/m[k][k]
			if f==0.0:continue # Exact zero: this row needs no elimination; no tolerance or model change.
			for l in range(k+1,n):m[j][l]-=f*m[k][l]
			b[j]-=f*b[k]
	var x := PackedFloat64Array();x.resize(n)
	for k in range(n-1,-1,-1):
		var v: float=b[k]
		for j in range(k+1,n):v-=m[k][j]*x[j]
		x[k]=v/m[k][k]
		if not is_finite(x[k]) or absf(x[k])>1e9:return {"ok":false}
	return {"ok":true,"x":x}
