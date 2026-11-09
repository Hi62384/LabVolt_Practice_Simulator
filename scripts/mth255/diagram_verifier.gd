extends RefCounted
## Cross-check rendered givens against the already-verified mathematical definition.
const C=preload("res://scripts/mth255/complex_domain.gd")
static func near(a: float,b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b)<=0.000001*maxf(1,absf(b))
static func verify(p: Dictionary) -> bool:
	var diagram=p.get("diagram",{});var q=p.parameters;var topic=p.generator_id
	if diagram.is_empty():return true
	if topic in ["impedance","impedance_network"]:
		var expected=[q.z,q.w] if topic=="impedance" else [q.z1,q.z2,q.z3]
		if diagram.get("components",[]).size()!=expected.size():return false
		for i in range(expected.size()):
			if not C.near(C.decode(diagram.components[i]),C.decode(expected[i])):return false
		return near(diagram.get("source",{}).get("rms_volts",NAN),q.v if topic=="impedance" else q.voltage)
	if topic=="statistics":
		if diagram.rows.size()!=q.data.size():return false
		for i in range(q.data.size()):
			if not near(diagram.rows[i][0],q.data[i]):return false
		return true
	if topic=="frequency":
		if q.get("construct_table",false):
			if diagram.rows.size()!=q.observations.size():return false
			for i in range(q.observations.size()):
				if not near(diagram.rows[i][0],q.observations[i]):return false
			return true
		if diagram.rows.size()!=q.rows.size():return false
		for i in range(q.rows.size()):
			if not near(diagram.rows[i][0],q.rows[i][0]):return false
			if i==q.get("missing_index",-1):
				if str(diagram.rows[i][1])!="?":return false
			elif not near(diagram.rows[i][1],q.rows[i][1]):return false
		return true
	if topic=="complex_convert":
		if diagram.points.size()!=1:return false
		return C.near(Vector2(diagram.points[0].x,diagram.points[0].y),C.decode(q.z))
	if topic=="exact_trig":
		return diagram.points.size()==1 and near(diagram.points[0].x,cos(deg_to_rad(q.degrees))) and near(diagram.points[0].y,sin(deg_to_rad(q.degrees)))
	if diagram.has("function"):
		var f=diagram.function
		match topic:
			"waveform":return f.kind=="sin" and near(f.amplitude,q.amplitude) and near(f.period,1.0/q.frequency) and near(f.phase,-q.phase/(TAU*q.frequency)) and near(f.offset,0)
			"wave_from_graph":return f.kind=="sin" and near(f.amplitude,q.amplitude) and near(f.period,q.period) and near(f.phase,q.shift) and near(f.offset,q.offset)
			"quadratic_vertex":return f.kind=="quadratic" and near(f.a,q.a) and near(f.b,q.b) and near(f.c,q.c)
			"log_evaluate":return f.kind=="log" and near(f.base,q.base) and near(f.rate,1) and near(f.phase,0) and near(f.amplitude,1) and near(f.offset,0)
			"exponential":return f.kind=="exponential" and near(f.amplitude,q.initial) and near(f.rate,q.rate) and near(f.offset,0)
			"rc_model":return f.kind=="exponential" and near(f.rate,-1.0/(q.resistance*q.capacitance)) and near(f.amplitude,-q.voltage if q.charging else q.voltage) and near(f.offset,q.voltage if q.charging else 0)
		return false
	if diagram.get("kind","")=="probability" and diagram.get("outcomes",[]).size()>0:
		var total=0;var favorable=0
		for outcome in diagram.outcomes:
			total+=int(outcome.weight)
			if outcome.get("favorable",false):favorable+=int(outcome.weight)
		var fraction=str(p.answer.probability).split("/")
		return fraction.size()==2 and total>0 and favorable*int(fraction[1])==total*int(fraction[0])
	return true
