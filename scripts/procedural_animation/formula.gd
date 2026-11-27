extends RefCounted
## Numeric expressions with an allowlisted grammar. No object or game instance
## is exposed to the evaluator.
const FUNCTIONS := ["absf","acos","asin","atan","atan2","ceilf","clampf","cos","exp","floorf","fmod","lerpf","log","maxf","minf","pow","roundf","signf","sin","sqrt","tan"]
const LIMIT := 1e6
static var token := RegEx.create_from_string("(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[+*/%(),-]|<=|>=|==|!=|<|>|\\s+")

static func compile(source: Variant,names: PackedStringArray) -> Expression:
	if not source is String or source.is_empty() or source.length()>144:return null
	var cursor:=0
	var depth:=0
	for item in token.search_all(source):
		if item.get_start()!=cursor:return null
		var word:=item.get_string()
		cursor=item.get_end()
		if word=="(":depth+=1
		elif word==")":depth-=1
		if depth not in range(0,9):return null
		if word.is_valid_identifier():
			if word not in names and word not in FUNCTIONS:return null
			if word in FUNCTIONS and not source.substr(cursor).strip_edges().begins_with("("):return null
	if cursor!=source.length() or depth!=0:return null
	var result:=Expression.new()
	return result if result.parse(source,names)==OK else null

static func value(program: Expression,inputs: Array,fallback: float) -> float:
	var output: Variant=program.execute(inputs,null,false,true)
	if program.has_execute_failed():return fallback
	if output is bool:return 1. if output else 0.
	if not (output is int or output is float) or not is_finite(float(output)):return fallback
	return clampf(float(output),-LIMIT,LIMIT)
