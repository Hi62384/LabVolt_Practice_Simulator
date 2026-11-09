extends RefCounted

const ARGUMENTS := {
	"FV":"rate %, periods, principal OR rate %, periods, payment, present",
	"PV":"rate %, periods, future OR rate %, periods, payment, future",
	"PMT":"rate %, periods, loan OR rate %, periods, present, future",
	"N":"rate %, payment, present, future",
	"I%":"periods, payment, present, future",
	"NPV":"rate %, initial cash flow, later cash flows…",
	"IRR":"initial cash flow, later cash flows…",
	"MU":"cost, selling price",
	"MAR":"cost, selling price",
	"%CHG":"old value, new value",
	"SL":"cost, salvage, useful life",
	"BEP":"fixed costs, price per unit, cost per unit",
	"EFF":"nominal annual rate %, periods per year",
	"NOM":"effective annual rate %, periods per year",
}

static func evaluate(operation: String, input: String) -> Dictionary:
	var values := PackedFloat64Array()
	for field in input.split(","):
		var number := field.strip_edges()
		if not number.is_valid_float() or not is_finite(float(number)):
			return {"ok":false,"error":"Enter numbers separated by commas"}
		values.append(float(number))
	var count := values.size()
	var valid_count := count==2
	match operation:
		"FV","PV","PMT": valid_count=count in [3,4]
		"N","I%": valid_count=count==4
		"NPV": valid_count=count>=3
		"IRR": valid_count=count>=2
		"SL","BEP": valid_count=count==3
	if not valid_count:
		return {"ok":false,"error":ARGUMENTS[operation]}
	var value := _calculate(operation,values)
	if not is_finite(value):
		return {"ok":false,"error":"No result for these values"}
	return {"ok":true,"value":value}

static func _calculate(operation: String, values: PackedFloat64Array) -> float:
	var a := values[0]
	var b := values[1]
	match operation:
		"MU": return 100.0*(b-a)/a if a!=0.0 else NAN
		"MAR": return 100.0*(b-a)/b if b!=0.0 else NAN
		"%CHG": return 100.0*(b-a)/a if a!=0.0 else NAN
		"SL": return (a-b)/values[2] if values[2]>0.0 else NAN
		"BEP": return a/(b-values[2]) if b>values[2] else NAN
		"EFF": return 100.0*(pow(1.0+a/(100.0*b),b)-1.0) if b>0.0 and a/(100.0*b)>-1.0 else NAN
		"NOM": return 100.0*b*(pow(1.0+a/100.0,1.0/b)-1.0) if b>0.0 and a>-100.0 else NAN
		"NPV": return _npv(a/100.0,values.slice(1)) if a>-100.0 else NAN
		"IRR":
			var has_positive := false
			var has_negative := false
			for flow in values:
				has_positive=has_positive or flow>0.0
				has_negative=has_negative or flow<0.0
			if not has_positive or not has_negative:return NAN
			return 100.0*_solve_rate(func(rate: float):return _npv(rate,values))
		"I%":
			if a<=0.0 or (b==0.0 and values[2]==0.0 and values[3]==0.0):return NAN
			return 100.0*_solve_rate(func(rate: float):
				var discount := pow(1.0+rate,-a)
				return values[2]+b*_annuity(rate,a)+values[3]*discount)
		"N":
			var rate := a/100.0
			var present := values[2]
			var future := values[3]
			if rate<=-1.0:return NAN
			if is_zero_approx(rate):
				var periods := -(present+future)/b if b!=0.0 else NAN
				return periods if periods>=0.0 else NAN
			var denominator := present*rate+b
			if denominator==0.0:return NAN
			var growth := (b-future*rate)/denominator
			if growth<=0.0:return NAN
			var periods := log(growth)/log(1.0+rate)
			return periods if periods>=0.0 else NAN
	return _time_value(operation,values)

static func _time_value(operation: String, values: PackedFloat64Array) -> float:
	var rate := values[0]/100.0
	var periods := values[1]
	if rate<=-1.0 or periods<=0.0:return NAN
	var discount := pow(1.0+rate,-periods)
	var annuity := _annuity(rate,periods)
	var amount := values[2]
	# The three-argument forms retain the calculator's original positive-amount convention.
	if values.size()==3:
		match operation:
			"FV":return amount/discount
			"PV":return amount*discount
			"PMT":return amount/annuity
	match operation:
		"FV":return -(values[3]+amount*annuity)/discount
		"PV":return -amount*annuity-values[3]*discount
		"PMT":return -(amount+values[3]*discount)/annuity
	return NAN

static func _annuity(rate: float, periods: float) -> float:
	return periods if absf(rate)<1e-10 else (1.0-pow(1.0+rate,-periods))/rate

static func _npv(rate: float, flows: PackedFloat64Array) -> float:
	var value := 0.0
	for index in range(flows.size()-1,-1,-1):
		value=flows[index]+value/(1.0+rate)
	return value

static func _solve_rate(residual: Callable) -> float:
	var previous_rate := exp(-12.0)-1.0
	var previous := float(residual.call(previous_rate))
	for step in range(1,193):
		var rate := exp(-12.0+step*.125)-1.0
		var value := float(residual.call(rate))
		if value==0.0:return rate
		if is_finite(previous) and is_finite(value) and signf(previous)!=signf(value):
			var low := previous_rate
			var high := rate
			for _iteration in 64:
				var middle := (low+high)*.5
				var current := float(residual.call(middle))
				if current==0.0:return middle
				if signf(current)==signf(previous):low=middle
				else:high=middle
			return (low+high)*.5
		previous_rate=rate
		previous=value
	return NAN
