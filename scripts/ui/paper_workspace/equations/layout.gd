extends RefCounted
## A measured draw plan. Coordinates are top-left relative to the annotation origin.
const Parser = preload("res://scripts/ui/paper_workspace/equations/parser.gd")
const MAX_EXTENT := 4096.0
const MIN_SCRIPT_SIZE := 8

static func build(source: String, font: Font, font_size: int) -> Dictionary:
	var parsed: Dictionary = Parser.new().parse(source)
	var size := clampi(font_size, 8, 96)
	if not parsed.ok:
		return _fallback(source, font, size, parsed.error)
	var box := _layout(parsed.tree, font, size, 0)
	if box.size.x > MAX_EXTENT or box.size.y > MAX_EXTENT:
		return _fallback(source, font, size, "Equation layout exceeds the page limit.")
	return {"ok":true, "source":source, "error":"", "size":box.size, "commands":box.commands}

static func _fallback(source: String, font: Font, size: int, error: String) -> Dictionary:
	var extent := Vector2.ZERO
	var commands := []
	for line in source.split("\n"):
		var row := _text(line, font, size)
		while line.length() > 1 and row.size.x > MAX_EXTENT:
			line = line.left(line.length() - 1)
			row = _text(line, font, size)
		if extent.y + row.size.y > MAX_EXTENT:break
		commands.append_array(_shift(row.commands, Vector2(0, extent.y)))
		extent.x = maxf(extent.x, row.size.x)
		extent.y += row.size.y
	return {"ok":false, "source":source, "error":error, "size":extent, "commands":commands}

static func draw(canvas: CanvasItem, plan: Dictionary, origin: Vector2, font: Font, color: Color) -> void:
	for command in plan.get("commands", []):
		if command.kind == "line": canvas.draw_line(origin + command.a, origin + command.b, color, command.width, true)
		elif command.kind == "text": canvas.draw_string(font, origin + command.pos, command.text, HORIZONTAL_ALIGNMENT_LEFT, -1, command.font_size, color)

static func _text(value: String, font: Font, size: int) -> Dictionary:
	var ascent := font.get_ascent(size)
	var height := maxf(font.get_height(size), float(size))
	var width := maxf(1.0, font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return {"size":Vector2(width,height), "baseline":ascent, "commands":[{"kind":"text", "text":value, "pos":Vector2(0,ascent), "font_size":size}]}

static func _shift(commands: Array, offset: Vector2) -> Array:
	var result := []
	for command in commands:
		var copy: Dictionary = command.duplicate()
		if copy.kind == "line": copy.a += offset; copy.b += offset
		else: copy.pos += offset
		result.append(copy)
	return result

static func _row(parts: Array, gap: float = 0.0) -> Dictionary:
	var baseline := 0.0
	var descent := 0.0
	for part in parts:
		baseline = maxf(baseline, part.baseline)
		descent = maxf(descent, part.size.y - part.baseline)
	var x := 0.0
	var commands := []
	for part in parts:
		commands.append_array(_shift(part.commands, Vector2(x, baseline - part.baseline)))
		x += part.size.x + gap
	return {"size":Vector2(maxf(1.0,x - gap),baseline + descent), "baseline":baseline, "commands":commands}

static func _radical(argument: Dictionary, font: Font, size: int, index: Dictionary = {}) -> Dictionary:
	var root := _text("√", font, size)
	var clearance := maxf(2.0, float(size)*0.12)
	var stroke := maxf(1.25, float(size)*0.055)
	var body_y := clearance + stroke
	var root_y := maxf(0.0, body_y + argument.baseline - root.baseline)
	var index_width := 0.0 if index.is_empty() else float(index.size.x)
	var body_x := index_width + float(root.size.x)
	var commands := _shift(root.commands, Vector2(index_width,root_y))
	commands.append_array(_shift(argument.commands, Vector2(body_x + 2.0,body_y)))
	commands.append({"kind":"line", "a":Vector2(body_x,clearance), "b":Vector2(body_x + argument.size.x + 4.0,clearance), "width":stroke})
	if not index.is_empty(): commands.append_array(index.commands)
	var height := maxf(root_y+root.size.y,body_y+argument.size.y)
	if not index.is_empty(): height = maxf(height,index.size.y)
	return {"size":Vector2(body_x+argument.size.x+4.0,height), "baseline":body_y+argument.baseline, "commands":commands}

static func _layout(node: Dictionary, font: Font, size: int, depth: int) -> Dictionary:
	if depth > Parser.MAX_DEPTH: return _text("?", font, size)
	var op: String = node.op
	if op == "sequence":
		var parts := []
		for part in node.parts: parts.append(_layout(part, font, size, depth + 1))
		return _row(parts)
	if op == "caret":
		var height := font.get_height(size)
		return {"size":Vector2(size * .56 if node.empty else 0.0,height), "baseline":font.get_ascent(size),
			"commands":[{"kind":"caret","pos":Vector2.ZERO,"trail":node.trail,"index":node.index,"empty":node.empty,"height":height}]}
	if op == "atom":
		var names := {"alpha":"α", "beta":"β", "gamma":"γ", "delta":"δ", "theta":"θ", "lambda":"λ", "mu":"μ", "pi":"π", "rho":"ρ", "sigma":"σ", "phi":"φ", "omega":"ω", "infty":"∞"}
		return _text(str(names.get(node.text, node.text)), font, size)
	if op == "function":
		var argument := _layout(node.child, font, size, depth+1)
		if node.name == "sqrt": return _radical(argument,font,size)
		var function_name: String = str(node.name)
		return _row([_text(function_name + "(",font,size),argument,_text(")",font,size)])
	if op == "matrix": return _matrix(node.rows, font, size, depth+1)
	if op == "group": return _row([_text("(",font,size), _layout(node.child,font,size,depth+1), _text(")",font,size)])
	if op == "prefix": return _row([_text(node.sign,font,size), _layout(node.child,font,size,depth+1)])
	var left_node: Dictionary = node.left
	if op in ["/", "^", "_"] and left_node.op == "group": left_node = left_node.child
	var left := _layout(left_node,font,size,depth+1)
	var right_node: Dictionary = node.right
	if op in ["/", "^", "_"] and right_node.op == "group": right_node = right_node.child
	var script_size := maxi(MIN_SCRIPT_SIZE, int(round(float(size)*0.70)))
	if op == "ⁿ√":
		if right_node.op == "group": right_node = right_node.child
		return _radical(left,font,size,_layout(right_node,font,script_size,depth+1))
	if op in ["^", "_"]:
		var right := _layout(right_node,font,script_size,depth+1)
		var rise := maxf(0.0, right.size.y * 0.40) if op == "^" else 0.0
		var left_y := rise
		var right_y: float = 0.0 if op == "^" else float(left.baseline) + float(size)*0.20
		var height := maxf(left_y + left.size.y, right_y + right.size.y)
		var commands := _shift(left.commands,Vector2(0,left_y))
		commands.append_array(_shift(right.commands,Vector2(left.size.x + 1.0,right_y)))
		return {"size":Vector2(left.size.x + right.size.x + 1.0,height), "baseline":left_y + left.baseline, "commands":commands}
	var right := _layout(right_node,font,size,depth+1)
	if op == "/":
		var pad := maxf(4.0,float(size)*0.18)
		var space := maxf(4.0,float(size)*0.20)
		var width := maxf(left.size.x,right.size.x) + pad*2.0
		var rule_y: float = float(left.size.y) + space*0.5
		var denominator_y: float = float(left.size.y) + space + 1.5
		var commands := _shift(left.commands,Vector2((width-left.size.x)*0.5,0))
		commands.append({"kind":"line", "a":Vector2(pad*0.35,rule_y), "b":Vector2(width-pad*0.35,rule_y), "width":maxf(1.25,float(size)*0.065)})
		commands.append_array(_shift(right.commands,Vector2((width-right.size.x)*0.5,denominator_y)))
		return {"size":Vector2(width,denominator_y+right.size.y), "baseline":rule_y, "commands":commands}
	var symbol: String = "" if bool(node.get("implicit",false)) else str({"*":" × ","+":" + ","-":" − ","=":" = ",",":", "}.get(op," ? "))
	return _row([left,_text(symbol,font,size),right]) if not symbol.is_empty() else _row([left,right],maxf(2.0,float(size)*0.12))

static func _matrix(rows: Array, font: Font, size: int, depth: int) -> Dictionary:
	var cell_gap := maxf(6.0,float(size)*0.30)
	var row_gap := maxf(4.0,float(size)*0.20)
	var columns: int = rows[0].size()
	var widths: Array[float] = []
	var heights: Array[float] = []
	var baselines: Array[float] = []
	var measured: Array = []
	for column in range(columns): widths.append(0.0)
	for row in rows:
		var cells: Array = []
		var baseline := 0.0
		var descent := 0.0
		for column in range(columns):
			var cell: Dictionary = _layout(row[column],font,size,depth+1)
			cells.append(cell)
			widths[column] = maxf(widths[column],cell.size.x)
			baseline = maxf(baseline,cell.baseline)
			descent = maxf(descent,cell.size.y-cell.baseline)
		measured.append(cells)
		baselines.append(baseline)
		heights.append(baseline+descent)
	var content_width := 0.0
	for width in widths: content_width += width + cell_gap
	content_width -= cell_gap
	var content_height := 0.0
	for height in heights: content_height += height + row_gap
	content_height -= row_gap
	var bracket_width := maxf(5.0,float(size)*0.22)
	var padding := maxf(4.0,float(size)*0.16)
	var total_width := content_width + 2.0*(bracket_width+padding)
	var total_height := content_height + 2.0*padding
	var commands := []
	var y := padding
	for row_index in range(rows.size()):
		var x := bracket_width + padding
		for column in range(columns):
			var cell: Dictionary = measured[row_index][column]
			commands.append_array(_shift(cell.commands,Vector2(x+(widths[column]-cell.size.x)*0.5,y+baselines[row_index]-cell.baseline)))
			x += widths[column]+cell_gap
		y += heights[row_index]+row_gap
	var stroke := maxf(1.25,float(size)*0.055)
	for edge_x in [0.0,total_width]:
		var tip_x: float = bracket_width if edge_x == 0.0 else total_width-bracket_width
		commands.append({"kind":"line", "a":Vector2(edge_x,0), "b":Vector2(tip_x,0), "width":stroke})
		commands.append({"kind":"line", "a":Vector2(edge_x,total_height), "b":Vector2(tip_x,total_height), "width":stroke})
		commands.append({"kind":"line", "a":Vector2(edge_x,0), "b":Vector2(edge_x,total_height), "width":stroke})
	return {"size":Vector2(total_width,total_height), "baseline":total_height*0.5, "commands":commands}
