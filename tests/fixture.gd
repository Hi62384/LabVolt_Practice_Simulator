extends RefCounted
static func ids() -> Array:
	var result: Array = []
	for prefix in ["P_","PV_"]:
		for phase in ["A","B","C","N"]:
			result.append(prefix+phase)
	for kind in ["R","L","C"]:
		for i in range(3):
			result.append("%s%d_P"%[kind,i])
			result.append("%s%d_N"%[kind,i])
	for i in range(3):
		for suffix in ["IN","OUT"]:
			result.append("AM%d_%s"%[i,suffix])
		for suffix in ["COM","150","300"]:
			result.append("V%d_%s"%[i,suffix])
	for i in range(2):
		for suffix in ["IN","OUT","VP","VN"]:
			result.append("W%d_%s"%[i,suffix])
	for i in range(1,7):
		result.append("M%d"%i)
	result.append_array(["DYN_0","DYN_1"])
	return result

static func locations() -> Dictionary:
	var result := {}
	for id in ids():
		result[id] = Vector3(-4.2,1.5,-1.4)
	for id in ["power","variable","R_0","R_1","R_2"]:
		result[id] = Vector3(-4.2,1.5,-1.4)
	return result
