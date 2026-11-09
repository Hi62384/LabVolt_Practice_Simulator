extends RefCounted

const DIGITS := ["black","brown","red","orange","yellow","green","blue","violet","gray","white"]
const COLORS := ["29292e","744225","bd3e36","d98136","e2b84b","53804f","3c68a8","805399","9b9da2","eee9d8"]
const PREFERRED := [10,11,12,13,15,16,18,20,22,24,27,30,33,36,39,43,47,51,56,62,68,75,82,91]

static func ratings() -> Array:
	var values: Array = []
	for power in range(-1, 5):
		for digits in PREFERRED:
			values.append(digits * pow(10.0, power))
	return values

static func bands(value: float, tolerance: float) -> Array[Dictionary]:
	if value <= 0.0: return []
	var precision := 3 if is_equal_approx(tolerance, .01) else 2
	var multiplier := floori(log(value) / log(10.0) + .000001) - precision + 1
	var significant := roundi(value / pow(10.0, multiplier))
	if multiplier < -2 or multiplier > 9 or not is_equal_approx(value, significant * pow(10.0, multiplier)):
		return []
	var result: Array[Dictionary] = []
	for digit in str(significant):
		result.append({"name":DIGITS[int(digit)],"color":COLORS[int(digit)]})
	if multiplier < 0:
		result.append({"name":"gold" if multiplier == -1 else "silver","color":"c7a34b" if multiplier == -1 else "bcc2c7"})
	else:
		result.append({"name":DIGITS[multiplier],"color":COLORS[multiplier]})
	result.append({"name":"brown" if precision == 3 else "gold","color":"744225" if precision == 3 else "c7a34b"})
	return result

