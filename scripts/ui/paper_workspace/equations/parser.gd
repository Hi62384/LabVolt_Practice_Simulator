extends RefCounted
## Display-only equation grammar. The original source is never normalized or rewritten.
const MAX_LENGTH := 512
const MAX_TOKENS := 256
const MAX_DEPTH := 24
const FUNCTIONS := ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "exp", "abs"]
var _tokens: Array[Dictionary] = []
var _at := 0
var _error := ""

func parse(source: String) -> Dictionary:
	_tokens.clear(); _at = 0; _error = ""
	if source.length() > MAX_LENGTH: return _result(source, {}, "Equation is longer than 512 characters.")
	var i := 0
	while i < source.length():
		var c := source[i]
		if c in " \t\r\n": i += 1; continue
		if c in "0123456789.":
			var start := i
			var dots := 0
			while i < source.length() and source[i] in "0123456789.":
				if source[i] == ".": dots += 1
				i += 1
			var value := source.substr(start, i - start)
			if dots > 1 or value == ".": return _result(source, {}, "Invalid number at character %d." % (start + 1))
			_tokens.append({"kind":"atom", "text":value, "pos":start})
		elif c.to_lower() in "abcdefghijklmnopqrstuvwxyz" or c in "πθφΩαβγΔΣμ∞":
			var start := i
			while i < source.length() and (source[i].to_lower() in "abcdefghijklmnopqrstuvwxyz" or source[i] in "πθφΩαβγΔΣμ∞"): i += 1
			_tokens.append({"kind":"atom", "text":source.substr(start, i - start), "pos":start})
		elif c in "+-*/^_()=,;[]×÷−":
			_tokens.append({"kind":{"×":"*","÷":"/","−":"-"}.get(c,c), "text":c, "pos":i}); i += 1
		else: return _result(source, {}, "Unsupported character '%s' at character %d." % [c, i + 1])
		if _tokens.size() > MAX_TOKENS: return _result(source, {}, "Equation has too many symbols (limit 256).")
	if _tokens.is_empty(): return _result(source, {}, "Enter an equation.")
	_tokens.append({"kind":"end", "text":"", "pos":source.length()})
	var tree := _expr(0, 0)
	if _error.is_empty() and _kind() != "end": _error = "Unexpected '%s' at character %d." % [_token().text, int(_token().pos) + 1]
	return _result(source, tree, _error)

func _result(source: String, tree: Dictionary, problem: String) -> Dictionary:
	return {"ok":problem.is_empty(), "source":source, "tree":tree, "error":problem}

func _token() -> Dictionary:
	return _tokens[mini(_at, _tokens.size() - 1)]

func _kind() -> String:
	return str(_token().kind)

func _expr(min_bp: int, depth: int) -> Dictionary:
	if depth > MAX_DEPTH: _error = "Equation nesting exceeds 24 levels."; return {}
	var left: Dictionary = {}
	var kind := _kind()
	if kind in ["+", "-"]:
		_at += 1
		var child := _expr(25, depth + 1)
		left = {"op":"prefix", "sign":kind, "child":child}
	elif kind == "atom":
		var atom: String = _token().text
		_at += 1
		if atom in FUNCTIONS and _kind() == "(":
			var function_position: int = _token().pos
			_at += 1
			if _kind() == ")" or _kind() == "end": _error = "Missing argument for %s at character %d." % [atom, function_position + 1]; return {}
			var argument := _expr(0, depth + 1)
			if not _error.is_empty(): return {}
			if _kind() != ")": _error = "Missing ')' for %s at character %d." % [atom, function_position + 1]; return {}
			_at += 1
			left = {"op":"function", "name":atom, "child":argument}
		else: left = {"op":"atom", "text":atom}
	elif kind == "[":
		var matrix_position: int = _token().pos
		_at += 1
		var rows: Array = []
		var row: Array = []
		if _kind() == "]" or _kind() == "end": _error = "Matrix needs cells at character %d." % (matrix_position + 1); return {}
		while _error.is_empty():
			row.append(_expr(11, depth + 1))
			if not _error.is_empty(): return {}
			if row.size() > 8: _error = "Matrix exceeds 8 columns."; return {}
			if _kind() == ",": _at += 1; continue
			rows.append(row)
			if rows.size() > 8: _error = "Matrix exceeds 8 rows."; return {}
			if _kind() == ";": row = []; _at += 1; continue
			break
		if _kind() != "]": _error = "Missing ']' for matrix at character %d." % (matrix_position + 1); return {}
		_at += 1
		var columns: int = rows[0].size()
		for cells in rows:
			if cells.size() != columns: _error = "Matrix rows must have the same number of cells."; return {}
		left = {"op":"matrix", "rows":rows}
	elif kind == "(":
		var opening_position: int = _token().pos
		_at += 1
		if _kind() == ")": _error = "Empty parentheses at character %d." % (int(_token().pos) + 1); return {}
		if _kind() == "end": _error = "Missing ')' for '(' at character %d." % (opening_position + 1); return {}
		var inside := _expr(0, depth + 1)
		if _error != "": return {}
		if _kind() != ")": _error = "Missing ')' for '(' at character %d." % (opening_position + 1); return {}
		_at += 1
		left = {"op":"group", "child":inside}
	else:
		_error = "Expected a number, symbol, or '(' at character %d." % (int(_token().pos) + 1)
		return {}
	while _error.is_empty():
		kind = _kind()
		var implicit := kind in ["atom", "(", "["]
		var bp := 10 if kind in ["=", ","] else (20 if kind in ["+", "-"] else (30 if kind in ["*", "/"] or implicit else (40 if kind in ["^", "_"] else -1)))
		if bp < min_bp: break
		var operator := "*" if implicit else kind
		if not implicit: _at += 1
		var right := _expr(bp if operator in ["^", "_"] else bp + 1, depth + 1)
		if _error != "": return {}
		left = {"op":operator, "left":left, "right":right, "implicit":implicit}
	return left
