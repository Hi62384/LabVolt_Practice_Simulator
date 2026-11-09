extends Control
## Bounded, real two-dimensional notation: fractions, scripts, radicals and matrices.
var ast: Dictionary = {"op":"text", "value":""}
var font: Font = ThemeDB.fallback_font
var ink := Color("e7f2fa")
var operations: Array = []
var hits: Array = []
var background: StyleBoxFlat
var highlight_enabled:=false
var highlight_path:Array=[]
signal node_selected(path: Array)

func _init() -> void:
	background=StyleBoxFlat.new()
	background.bg_color=Color("183442")
	background.set_corner_radius_all(5)

func set_expression(value: Dictionary) -> void:
	ast = value.duplicate(true)
	operations.clear()
	hits.clear()
	var bounds := _layout(ast, Vector2(12, 12), 24, [], 0)
	custom_minimum_size = bounds + Vector2(24, 24)
	queue_redraw()

func _text(value: String, at: Vector2, fs: int) -> Vector2:
	var s := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	operations.append(["text", value, at + Vector2(0, fs), fs])
	return Vector2(s.x, fs * 1.35)

func _shift(first: int, last: int, hit_first: int, hit_last: int, delta: Vector2) -> void:
	for i in range(first,last):
		if operations[i][0]=="text":operations[i][2]+=delta
		else:operations[i][1]+=delta;operations[i][2]+=delta
	for i in range(hit_first,hit_last):hits[i].rect.position+=delta

func _layout(n: Dictionary, at: Vector2, fs: int, path: Array, depth: int) -> Vector2:
	if depth > 24 or operations.size() > 1500: return _text("…", at, fs)
	var start := operations.size()
	var op := str(n.get("op", "text"))
	var a: Array = n.get("args", [])
	var box := Vector2.ZERO
	if op in ["num", "symbol", "text"]:
		var word := str(n.get("value", n.get("name", "□")))
		word = {"theta":"θ", "phi":"φ", "omega":"ω", "pi":"π", "alpha":"α", "beta":"β"}.get(word, word)
		box = _text(word if not word.is_empty() else "□", at, fs)
	elif op == "div" and a.size() == 2:
		var top_first:=operations.size();var top_hit:=hits.size()
		var top := _layout(a[0], at, fs, path + [0], depth + 1)
		var top_last:=operations.size();var top_hit_last:=hits.size()
		var bottom_first:=operations.size();var bottom_hit:=hits.size()
		var bottom := _layout(a[1], at + Vector2(0, top.y + 10), fs, path + [1], depth + 1)
		box = Vector2(maxf(top.x, bottom.x) + 12, top.y + bottom.y + 10)
		_shift(top_first,top_last,top_hit,top_hit_last,Vector2((box.x-top.x)/2,0))
		_shift(bottom_first,operations.size(),bottom_hit,hits.size(),Vector2((box.x-bottom.x)/2,0))
		operations.append(["line", at + Vector2(-3, top.y + 4), at + Vector2(box.x, top.y + 4)])
	elif op=="exp" and a.size()==1:
		var e_size:=_text("e",at+Vector2(0,fs*0.35),fs)
		var exponent:=_layout(a[0],at+Vector2(e_size.x+2,0),maxi(12,int(fs*0.7)),path+[0],depth+1)
		box=Vector2(e_size.x+exponent.x+2,maxf(e_size.y+fs*0.35,exponent.y))
	elif op=="log" and a.size()==2:
		var log_size:=_text("log",at,fs)
		var base_size:=_layout(a[1],at+Vector2(log_size.x,fs*0.65),maxi(12,int(fs*0.7)),path+[1],depth+1)
		var x:=log_size.x+base_size.x+4
		x+=_text("(",at+Vector2(x,0),fs).x
		var argument:=_layout(a[0],at+Vector2(x,0),fs,path+[0],depth+1)
		x+=argument.x
		x+=_text(")",at+Vector2(x,0),fs).x
		box=Vector2(x,maxf(argument.y,fs*1.7))
	elif op=="factorial" and a.size()==1:
		var base_size:=_layout(a[0],at,fs,path+[0],depth+1)
		box=Vector2(base_size.x+_text("!",at+Vector2(base_size.x,0),fs).x,base_size.y)
	elif op in ["pow", "subscript"] and a.size() == 2:
		var base := _layout(a[0], at + Vector2(0, fs * 0.35 if op == "pow" else 0), fs, path + [0], depth + 1)
		var small := _layout(a[1], at + Vector2(base.x + 2, 0 if op == "pow" else base.y * 0.6), maxi(12, int(fs * 0.7)), path + [1], depth + 1)
		box = Vector2(base.x + small.x + 2, base.y + small.y * 0.6)
	elif op in ["sqrt", "cbrt", "root"] and a.size() > 0:
		var rad_index := 1 if op == "root" and a.size() == 2 else 0
		var prefix := "√" if op == "sqrt" else "∛" if op == "cbrt" else "√"
		var pre := _text(prefix, at, fs)
		if op == "root" and rad_index == 1: _layout(a[0], at, maxi(10, fs / 2), path + [0], depth + 1)
		var rad := _layout(a[rad_index], at + Vector2(pre.x, 4), fs, path + [rad_index], depth + 1)
		operations.append(["line", at + Vector2(pre.x, 2), at + Vector2(pre.x + rad.x, 2)])
		box = Vector2(pre.x + rad.x, rad.y + 4)
	elif op in ["matrix", "determinant"]:
		var rows: Array = n.get("rows", [])
		var x := at.x + 14
		var y := at.y + 5
		var max_x := x
		for r in range(mini(rows.size(), 6)):
			x = at.x + 14
			var height := float(fs * 1.4)
			for c in range(mini(rows[r].size(), 6)):
				var cell := _layout(rows[r][c], Vector2(x,y), fs, path + [r,c], depth + 1)
				x += maxf(cell.x + 20, 70)
				height = maxf(height, cell.y + 8)
			max_x = maxf(max_x,x)
			y += height
		box = Vector2(max_x - at.x + 6, y - at.y + 5)
		for edge in [at.x + 3, at.x + box.x - 3]:
			operations.append(["line", Vector2(edge, at.y), Vector2(edge, at.y + box.y)])
			if op == "matrix":
				operations.append(["line", Vector2(edge,at.y),Vector2(edge + (7 if edge < max_x else -7),at.y)])
	else:
		var separators := {"add":" + ", "sub":" − ", "mul":" · ", "equation":" = ", "complex_polar":" ∠ "}
		var is_binary := separators.has(op)
		var grouping:bool=op in ["add","sub","mul"]
		var cursor := at
		var parts:Array=[]
		if not is_binary or grouping:
			var first:=operations.size()
			cursor.x += _text("(" if grouping else ("−" if op == "neg" else op + "("), cursor, fs).x
			parts.append({"first":first,"last":operations.size(),"hit_first":hits.size(),"hit_last":hits.size(),"height":fs*1.35})
		for i in range(mini(a.size(), 12)):
			if i > 0:
				var sep_first:=operations.size()
				cursor.x += _text(str(separators.get(op, ", ")), cursor, fs).x
				parts.append({"first":sep_first,"last":operations.size(),"hit_first":hits.size(),"hit_last":hits.size(),"height":fs*1.35})
			var first:=operations.size();var hit_first:=hits.size()
			var child := _layout(a[i], cursor, fs, path + [i], depth + 1)
			parts.append({"first":first,"last":operations.size(),"hit_first":hit_first,"hit_last":hits.size(),"height":child.y})
			cursor.x += child.x
			box.y = maxf(box.y, child.y)
		if grouping or (not is_binary and op != "neg"):
			var first:=operations.size()
			cursor.x += _text(")", cursor, fs).x
			parts.append({"first":first,"last":operations.size(),"hit_first":hits.size(),"hit_last":hits.size(),"height":fs*1.35})
		box.x = cursor.x - at.x
		box.y = maxf(box.y, fs * 1.35)
		for part in parts:_shift(part.first,part.last,part.hit_first,part.hit_last,Vector2(0,(box.y-float(part.height))/2))
	if operations.size() > start: hits.append({"rect":Rect2(at, box),"path":path})
	return box

func _draw() -> void:
	draw_style_box(background,Rect2(Vector2.ZERO,size))
	if highlight_enabled:
		for hit in hits:
			if hit.path==highlight_path:draw_rect(hit.rect.grow(3),Color("63b6cb"),false,1.5)
	for item in operations:
		if item[0] == "text": draw_string(font, item[2], item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, item[3], ink)
		else: draw_line(item[1], item[2], ink, 1.5, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for hit in hits:
			if hit.rect.has_point(event.position):
				node_selected.emit(hit.path)
				accept_event()
				return
