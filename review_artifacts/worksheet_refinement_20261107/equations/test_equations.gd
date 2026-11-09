extends RefCounted
## Offline regression runner; call run() from an existing Godot test harness.
const Parser = preload("res://scripts/ui/paper_workspace/equations/parser.gd")
const Layout = preload("res://scripts/ui/paper_workspace/equations/layout.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var parser = Parser.new()
	var source := "(((33)(66)/33+66)^2) + 3)"
	var unmatched: Dictionary = parser.parse(source)
	_check(not unmatched.ok and unmatched.source == source, "unmatched closing parenthesis retains source", failures)
	var nested := "((a+b)/(c-d))^2"
	var valid: Dictionary = parser.parse(nested)
	_check(valid.ok and valid.tree.op == "^" and valid.tree.left.op == "group", "nested fraction and power precedence", failures)
	var fraction: Dictionary = parser.parse("a/(b/c)")
	_check(fraction.ok and fraction.tree.op == "/" and fraction.tree.right.op == "group", "nested denominator", failures)
	var implicit: Dictionary = parser.parse("(a+b)(c+d)")
	_check(implicit.ok and implicit.tree.op == "*" and implicit.tree.implicit, "adjacent groups multiply", failures)
	var explicit: Dictionary = parser.parse("a+b/c")
	_check(explicit.ok and explicit.tree.op == "+" and explicit.tree.right.op == "/", "division before addition", failures)
	var unary: Dictionary = parser.parse("-a^2")
	_check(unary.ok and unary.tree.op == "prefix" and unary.tree.child.op == "^", "power before unary minus", failures)
	var powers: Dictionary = parser.parse("a^b^c")
	_check(powers.ok and powers.tree.op == "^" and powers.tree.right.op == "^", "right associative powers", failures)
	var divisions: Dictionary = parser.parse("a/b/c")
	_check(divisions.ok and divisions.tree.op == "/" and divisions.tree.left.op == "/", "left associative divisions", failures)
	var subscript: Dictionary = parser.parse("x_1^2")
	_check(subscript.ok and subscript.tree.op == "_" and subscript.tree.right.op == "^", "subscript and power grouping", failures)
	_check(not parser.parse("(").ok, "unclosed group", failures)
	_check("character 1" in str(parser.parse("(").error), "unclosed group error position", failures)
	_check(not parser.parse("a)").ok and "character 2" in str(parser.parse("a)").error), "trailing closing parenthesis position", failures)
	_check(not parser.parse("a@b").ok and "character 2" in str(parser.parse("a@b").error), "invalid token position", failures)
	_check(not parser.parse("a/").ok, "missing denominator", failures)
	_check(not parser.parse("").ok, "empty source", failures)
	_check(not parser.parse("a".repeat(513)).ok, "length bound", failures)
	_check(not parser.parse("(".repeat(25) + "a" + ")".repeat(25)).ok, "depth bound", failures)
	var font: Font = ThemeDB.fallback_font
	var plan: Dictionary = Layout.build("a/(b^2)",font,24)
	var lines := 0
	for command in plan.commands:
		if command.kind == "line": lines += 1
	_check(plan.ok and lines == 1 and plan.size.x > 0 and plan.size.y > font.get_height(24), "fraction draw plan and extent", failures)
	var clamped: Dictionary = Layout.build("a/b",font,999999)
	_check(clamped.ok and clamped.size.x <= Layout.MAX_EXTENT and clamped.size.y <= Layout.MAX_EXTENT, "huge font request is clamped", failures)
	_check(Layout.build("a/b",font,-100).ok, "negative font request is clamped", failures)
	_check(Layout.build("(x+y)/(z^2)",font,24).source == "(x+y)/(z^2)", "exact source roundtrip", failures)
	var radical: Dictionary = Layout.build("sqrt(x^2+y^2)",font,24)
	var radical_rules := 0
	for command in radical.commands:
		if command.kind == "line": radical_rules += 1
	_check(radical.ok and radical_rules == 1 and radical.size.y > 0, "radical has measured overbar", failures)
	var greek: Dictionary = Layout.build("alpha+omega=i",font,24)
	var greek_text := ""
	for command in greek.commands:
		if command.kind == "text": greek_text += command.text
	_check(greek.ok and "α" in greek_text and "ω" in greek_text, "named Greek glyphs", failures)
	var matrix: Dictionary = Layout.build("[1,2;3,4]",font,24)
	var matrix_lines := 0
	for command in matrix.commands:
		if command.kind == "line": matrix_lines += 1
	_check(matrix.ok and matrix_lines == 6 and matrix.size.x > 0, "two by two matrix brackets", failures)
	_check(not Parser.new().parse("[1,2;3]").ok, "unequal matrix rows rejected", failures)
	_check(not Parser.new().parse("sqrt()").ok, "empty function rejected", failures)
	_check(not Parser.new().parse("[1,2").ok, "open matrix rejected", failures)
	_check(Layout.build("[1,2;3,4]",font,24).source == "[1,2;3,4]", "matrix exact source roundtrip", failures)
	return failures

static func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition: failures.append(label)
