extends SceneTree
const Kernel=preload("res://scripts/electronics/MnaLinearKernel.cs")
const Solver=preload("res://scripts/electronics_solver.gd")

func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var kernel=Kernel.new()
	var solver=Solver.new()
	for n in [2,3,8,16]:
		var matrix: Array=[]
		var rhs:=PackedFloat64Array()
		for i in n:
			var row:=PackedFloat64Array();row.resize(n)
			for j in n:row[j]=float(4+n) if i==j else 1.0/float(1+absi(i-j))
			matrix.append(row);rhs.append(float(i+1))
		var expected: Dictionary=solver._solve_cached_gd(matrix,rhs)
		var actual: Dictionary=kernel.SolveCached(matrix,rhs)
		assert(expected.ok and actual.ok)
		var integrated: Dictionary=solver._solve_cached(matrix,rhs)
		assert(integrated.ok)
		for i in n:assert(absf(expected.x[i]-actual.x[i])<1e-10)
		for i in n:assert(absf(expected.x[i]-integrated.x[i])<1e-10)
		var repeated: Dictionary=kernel.SolveCached(matrix,rhs)
		assert(repeated.ok and repeated.x==actual.x)
		matrix[0][0]+=.5
		var changed: Dictionary=kernel.SolveCached(matrix,rhs)
		assert(changed.ok and absf(changed.x[0]-actual.x[0])>1e-6)
	var singular: Dictionary=kernel.SolveCached([PackedFloat64Array([0.0,0.0]),PackedFloat64Array([0.0,0.0])],PackedFloat64Array([1.0,1.0]))
	assert(not singular.ok)
	var matrix: Array=[];var rhs:=PackedFloat64Array()
	for i in 16:
		var row:=PackedFloat64Array();row.resize(16)
		for j in 16:row[j]=20.0 if i==j else 1.0/float(1+absi(i-j))
		matrix.append(row);rhs.append(float(i+1))
	var started:=Time.get_ticks_usec()
	for i in 1000:solver._solve_cached_gd(matrix,rhs)
	var gd_usec:=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for i in 1000:kernel.SolveCached(matrix,rhs)
	var cs_usec:=Time.get_ticks_usec()-started
	print("cached 16x16 x1000 GDScript ",gd_usec," us; C# ",cs_usec," us")
	var bigger: Array=[];var bigger_rhs:=PackedFloat64Array()
	for i in 60:
		var row:=PackedFloat64Array();row.resize(60)
		for j in 60:row[j]=80.0 if i==j else 1.0/float(1+absi(i-j))
		bigger.append(row);bigger_rhs.append(float(i+1))
	started=Time.get_ticks_usec()
	for i in 20:
		bigger[0][0]=80.0+float(i)*.01
		solver._solve_cached_gd(bigger,bigger_rhs)
	gd_usec=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for i in 20:
		bigger[0][0]=90.0+float(i)*.01
		kernel.SolveCached(bigger,bigger_rhs)
	cs_usec=Time.get_ticks_usec()-started
	print("uncached 60x60 x20 GDScript ",gd_usec," us; C# ",cs_usec," us")
	var hybrid=Solver.new();var old=Solver.new();old.use_csharp=false
	started=Time.get_ticks_usec()
	for i in 20:
		bigger[0][0]=100.0+float(i)*.01
		old._solve_cached(bigger,bigger_rhs)
	gd_usec=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec()
	for i in 20:
		bigger[0][0]=120.0+float(i)*.01
		hybrid._solve_cached(bigger,bigger_rhs)
	cs_usec=Time.get_ticks_usec()-started
	print("hybrid uncached 60x60 x20 GDScript ",gd_usec," us; C# factor ",cs_usec," us")
	print("MNA_CSHARP_KERNEL PASS")
	quit()
