extends RefCounted
static func format_value(value: float, unit: String) -> String:
	if not is_finite(value): return "—"
	var factor := 1.0; var prefix := ""
	var magnitude := absf(value)
	if magnitude>=1000: factor=1000.0; prefix="k"
	elif magnitude>0 and magnitude<0.000001: factor=0.000000001; prefix="n"
	elif magnitude>0 and magnitude<0.001: factor=0.000001; prefix="μ"
	elif magnitude>0 and magnitude<1: factor=0.001; prefix="m"
	return ("%.3f"%(value/factor)).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")+" "+prefix+unit

static func probe(value: float) -> String:
	return ("%.3f"%value).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")+"×"
