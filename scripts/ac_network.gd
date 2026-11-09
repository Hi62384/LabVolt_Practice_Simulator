extends RefCounted
## RMS linear AC modified nodal analysis. Impedances and source values are phasors.
## Real block matrix uses float64; no artificial conductance to earth.

func solve(nodes: Array, branches: Array) -> Dictionary:
	var index := {}
	for id in nodes:
		if str(id) != "0" and not index.has(str(id)):
			index[str(id)] = index.size()
	var sources: Array = []
	var adjacency := {"0": []}
	for id in index:
		adjacency[id] = []
	for b in branches:
		if not adjacency.has(b.a) or not adjacency.has(b.b):
			return {"fault": "Unknown branch terminal", "voltages": {}, "currents": {}}
		adjacency[b.a].append(b.b)
		adjacency[b.b].append(b.a)
		if b.type in ["voltage","transformer"]:
			sources.append(b)
	# Floating passive islands have a free common-mode potential. Choose a local
	# reference, explicitly report it, and preserve their differential solution.
	var seen := {}
	var references: Array = []
	for start in adjacency:
		if seen.has(start):
			continue
		var queue: Array = [start]
		var island: Array = []
		while not queue.is_empty():
			var id = queue.pop_back()
			if seen.has(id):
				continue
			seen[id] = true
			island.append(id)
			queue.append_array(adjacency[id])
		if not island.has("0"):
			references.append(island[0])
			sources.append({"a": island[0], "b": "0", "type": "voltage", "value": Vector2.ZERO, "id": "reference_" + str(island[0])})
	var n: int = index.size() + sources.size()
	var size := n * 2
	var matrix: Array[PackedFloat64Array] = []
	var rhs := PackedFloat64Array()
	rhs.resize(size)
	for i in range(size):
		var row := PackedFloat64Array()
		row.resize(size)
		matrix.append(row)
	for b in branches:
		if b.type != "impedance":
			continue
		var z: Vector2 = b.value
		if z.length_squared() < 1e-20:
			return {"fault": "Zero impedance: use a voltage source of zero volts", "voltages": {}, "currents": {}}
		var den: float = float(z.x) * z.x + float(z.y) * z.y
		var g: float = z.x / den
		var h: float = -z.y / den
		var a: int = index.get(b.a, -1)
		var c: int = index.get(b.b, -1)
		stamp(matrix, a, a, g, h, n)
		stamp(matrix, c, c, g, h, n)
		stamp(matrix, a, c, -g, -h, n)
		stamp(matrix, c, a, -g, -h, n)
	for k in range(sources.size()):
		var b: Dictionary = sources[k]
		var j: int = index.size() + k
		var a: int = index.get(b.a, -1)
		var c: int = index.get(b.b, -1)
		stamp(matrix, a, j, 1, 0, n)
		stamp(matrix, j, a, 1, 0, n)
		stamp(matrix, c, j, -1, 0, n)
		stamp(matrix, j, c, -1, 0, n)
		if b.type=="transformer":
			var primary_a: int=index.get(b.c,-1)
			var primary_b: int=index.get(b.d,-1)
			stamp(matrix,primary_a,j,-b.ratio,0,n)
			stamp(matrix,primary_b,j,b.ratio,0,n)
			stamp(matrix,j,primary_a,-b.ratio,0,n)
			stamp(matrix,j,primary_b,b.ratio,0,n)
		rhs[j] = b.value.x
		rhs[j+n] = b.value.y
	for col in range(size):
		var pivot := col
		for row in range(col+1, size):
			if absf(matrix[row][col]) > absf(matrix[pivot][col]):
				pivot = row
		if absf(matrix[pivot][col]) < 1e-12:
			return {"fault": "Singular or conflicting ideal source circuit", "voltages": {}, "currents": {}}
		var swap = matrix[col]
		matrix[col] = matrix[pivot]
		matrix[pivot] = swap
		var temp := rhs[col]
		rhs[col] = rhs[pivot]
		rhs[pivot] = temp
		for row in range(col+1, size):
			var factor: float = matrix[row][col] / matrix[col][col]
			if factor == 0:
				continue
			for j in range(col, size):
				matrix[row][j] -= factor * matrix[col][j]
			rhs[row] -= factor * rhs[col]
	var x := PackedFloat64Array()
	x.resize(size)
	for i in range(size-1, -1, -1):
		var value := rhs[i]
		for j in range(i+1, size):
			value -= matrix[i][j] * x[j]
		x[i] = value / matrix[i][i]
	var volts := {"0": Vector2.ZERO}
	for id in index:
		var i: int = index[id]
		volts[id] = Vector2(x[i], x[i+n])
	var currents := {}
	for b in branches:
		if b.type == "impedance":
			# Subtract before converting to Vector2: current-coil millivolt drops
			# must retain float64 precision even on a 120 V common-mode signal.
			var a: int = index.get(b.a,-1)
			var c: int = index.get(b.b,-1)
			var vr: float = (x[a] if a>=0 else 0.0)-(x[c] if c>=0 else 0.0)
			var vi: float = (x[a+n] if a>=0 else 0.0)-(x[c+n] if c>=0 else 0.0)
			var z: Vector2 = b.value
			var den: float = float(z.x)*z.x+float(z.y)*z.y
			currents[b.id] = Vector2((vr*z.x+vi*z.y)/den,(vi*z.x-vr*z.y)/den)
	for k in range(sources.size()):
		currents[sources[k].id] = Vector2(x[index.size()+k], x[index.size()+k+n])
	return {"fault": "", "voltages": volts, "currents": currents, "floating_references": references}

func stamp(m: Array[PackedFloat64Array], a: int, b: int, g: float, h: float, n: int) -> void:
	if a < 0 or b < 0:
		return
	m[a][b] += g
	m[a][b+n] -= h
	m[a+n][b] += h
	m[a+n][b+n] += g

func divide(a: Vector2, b: Vector2) -> Vector2:
	var d: float = float(b.x)*b.x + float(b.y)*b.y
	return Vector2((float(a.x)*b.x + float(a.y)*b.y)/d, (float(a.y)*b.x-float(a.x)*b.y)/d)
