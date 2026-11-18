extends RefCounted
## Numeric source only. The tokenizer rejects names outside the numeric environment.
const FUNCTIONS := ["abs","sqrt","sin","cos","tan","log","exp","pow","min","max","floor","ceil","round"]
const MAX_STEPS := 240
var variables := {"pi":PI,"tau":TAU}
var lines := PackedStringArray()
var output := PackedStringArray()
var remaining := MAX_STEPS
var issue := ""
var tokens := RegEx.new()
var assignment := RegEx.new()

func run(source: String) -> String:
	if source.length()>1600:return "Source exceeds 1,600 characters."
	tokens.compile("[a-z_][a-z_0-9]*|(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)|[+*/%^<>=!() ,-]")
	assignment.compile("^let ([a-z_][a-z_0-9]{0,19}) = (.+)$")
	lines=source.split("\n")
	variables={"pi":PI,"tau":TAU}
	remaining=MAX_STEPS
	output.clear()
	issue=""
	_block(0,lines.size(),0)
	return "\n".join(output) if issue.is_empty() and not output.is_empty() else "Finished successfully." if issue.is_empty() else issue

func _block(start: int, end: int, depth: int) -> void:
	if depth>5:
		issue="Blocks can be nested up to five levels."
		return
	var line_index := start
	while line_index<end and issue.is_empty():
		remaining-=1
		if remaining<0:
			issue="Execution limit reached."
			return
		var text := lines[line_index].get_slice("#",0).strip_edges()
		if text.begins_with("if ") or text.begins_with("repeat "):
			var stop:=_find_end(line_index+1,end)
			if stop<0:
				issue="Line %d needs a closing end." % (line_index+1)
				return
			var repeat_block := text.begins_with("repeat ")
			var value: Variant=_evaluate(text.substr(7 if repeat_block else 3))
			if not issue.is_empty():return
			var count := int(value) if repeat_block else int(bool(value))
			if repeat_block and (not (value is float or value is int) or count<0 or count>40 or float(count)!=float(value)):
				issue="repeat needs a whole number from 0 to 40."
				return
			for iteration in count:
				_block(line_index+1,stop,depth+1)
				if not issue.is_empty():return
			line_index=stop+1
			continue
		if text.begins_with("print "):
			var value: Variant=_evaluate(text.substr(6))
			if not issue.is_empty():return
			if output.size()>=60:
				issue="Output limit reached."
				return
			output.append(str(value))
		elif not text.is_empty():
			var matched := assignment.search(text)
			if matched==null:
				issue="Line %d expects let, print, if, or repeat." % (line_index+1)
				return
			var name := matched.get_string(1)
			var value: Variant=_evaluate(matched.get_string(2))
			if not issue.is_empty():return
			if name in FUNCTIONS or name in ["pi","tau"] or (not variables.has(name) and variables.size()>=24):
				issue="Variable name is reserved or the variable limit was reached."
				return
			variables[name]=value
		line_index+=1

func _find_end(start: int, end: int) -> int:
	var nesting:=0
	for index in range(start,end):
		var text:=lines[index].get_slice("#",0).strip_edges()
		if text.begins_with("if ") or text.begins_with("repeat "):nesting+=1
		elif text=="end":
			if nesting==0:return index
			nesting-=1
	return -1

func _evaluate(source: String) -> Variant:
	if source.is_empty() or source.length()>160:
		issue="Expected a numeric expression of at most 160 characters."
		return 0
	var offset:=0
	var numeric_source:=PackedStringArray()
	for token in tokens.search_all(source):
		var word:=token.get_string()
		if token.get_start()!=offset or (word[0] in "abcdefghijklmnopqrstuvwxyz_" and not variables.has(word) and word not in FUNCTIONS):
			issue="Unsupported expression."
			return 0
		numeric_source.append(word+".0" if word.is_valid_int() else word)
		offset=token.get_end()
	if offset!=source.length():
		issue="Unsupported expression."
		return 0
	var expression:=Expression.new()
	if expression.parse("".join(numeric_source),PackedStringArray(variables.keys()))!=OK:
		issue=expression.get_error_text()
		return 0
	var value: Variant=expression.execute(variables.values(),null,false,true)
	if expression.has_execute_failed() or not (value is bool or value is float or value is int) or (not value is bool and not is_finite(float(value))):
		issue="Expression must produce a finite number or a comparison."
		return 0
	return value
