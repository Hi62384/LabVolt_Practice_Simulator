extends RefCounted
static func number(value: float) -> String:
	if value==0:return "0"
	return String.num_scientific(value) if absf(value)<0.001 or absf(value)>=1e6 else String.num(value,4)

## Presentation serialization only. Parsing and grading belong to the shared engine.
static func source(node: Dictionary, depth: int = 0) -> String:
	if depth > 24: return "?"
	var op := str(node.get("op", ""))
	var args: Array = node.get("args", [])
	if op == "num": return str(node.get("value", "0"))
	if op == "symbol": return str(node.get("name", "x"))
	if op == "text": return str(node.get("value", ""))
	if op in ["matrix","determinant"]:
		var lines:Array[String]=[]
		for row in node.get("rows",[]):
			var cells:Array[String]=[]
			for cell in row:cells.append(source(cell,depth+1))
			lines.append("["+",".join(cells)+"]")
		return "["+",".join(lines)+"]"
	var parts: Array[String] = []
	for arg in args:
		parts.append(source(arg, depth + 1) if arg is Dictionary else "?")
	if op in ["add", "sub", "mul", "div", "pow"] and parts.size() == 2:
		return "(" + parts[0] + {"add":"+", "sub":"-", "mul":"*", "div":"/", "pow":"^"}[op] + parts[1] + ")"
	if op == "neg" and parts.size() == 1: return "-(" + parts[0] + ")"
	if op == "equation" and parts.size() == 2: return parts[0] + "=" + parts[1]
	if op == "subscript" and parts.size() == 2: return parts[0] + "_" + parts[1]
	if op == "complex_polar" and parts.size() == 2: return parts[0] + "∠" + parts[1]
	return op + "(" + ",".join(parts) + ")"

static func json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	if value is float: return is_finite(value)
	if value is Dictionary:
		if value.size() > 512: return false
		for key in value:
			if not (key is String or key is StringName) or not json_safe(value[key], depth + 1): return false
	elif value is Array:
		if value.size() > 2048: return false
		for child in value:
			if not json_safe(child, depth + 1): return false
	elif not (value is String or value is StringName or value is int or value is bool or value == null): return false
	return true
