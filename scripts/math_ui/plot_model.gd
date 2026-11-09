extends RefCounted
## Finite numeric sampling for presentation only; never an answer validator.
static func evaluate(f: Dictionary, x: float) -> float:
	var y := NAN
	var offset := float(f.get("offset", 0))
	var amplitude := float(f.get("amplitude", 1))
	match str(f.get("kind", "sin")):
		"sin", "cos":
			var period := float(f.get("period", TAU if f.get("angle_unit") == "radians" else 360.0))
			if absf(period) < 1e-12: return NAN
			var t := TAU * (x - float(f.get("phase", 0))) / period
			y = offset + amplitude * (sin(t) if f.get("kind", "sin") == "sin" else cos(t))
		"exponential":
			var base := float(f.get("base", exp(1.0)))
			var power := float(f.get("rate", 1)) * (x - float(f.get("phase", 0)))
			if base <= 0 or absf(power * log(base)) > 600: return NAN
			y = offset + amplitude * pow(base, power)
		"log":
			var base := float(f.get("base", 10))
			var arg := float(f.get("rate", 1)) * (x - float(f.get("phase", 0)))
			if base <= 0 or absf(base - 1) < 1e-12 or arg <= 0: return NAN
			y = offset + amplitude * log(arg) / log(base)
		"quadratic": y = float(f.get("a", 1)) * x * x + float(f.get("b", 0)) * x + float(f.get("c", 0))
		"line": y = float(f.get("slope", 1)) * x + offset
	return y if is_finite(y) else NAN

static func valid_bounds(bounds: Array) -> bool:
	return bounds.size() == 2 and is_finite(float(bounds[0])) and is_finite(float(bounds[1])) and float(bounds[1]) - float(bounds[0]) >= 1e-8 and maxf(absf(float(bounds[0])),absf(float(bounds[1]))) <= 1e12

static func triangle_valid(vertices: Array) -> bool:
	if vertices.size() != 3: return false
	var v: Array[Vector2] = []
	for p in vertices:
		if not p is Dictionary or not is_finite(float(p.get("x", NAN))) or not is_finite(float(p.get("y", NAN))): return false
		v.append(Vector2(float(p.x), float(p.y)))
	return absf((v[1] - v[0]).cross(v[2] - v[0])) > 1e-9
