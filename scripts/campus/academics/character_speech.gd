extends RefCounted
## Preserve whole sentences; subtitle pages never remove spoken content.
const MAX_TEXT := 1600

static func complete(text: String, limit := MAX_TEXT) -> String:
	var clean := text.strip_edges().replace("\r", " ").replace("\n", " ")
	if clean.length() <= limit: return clean
	var end := -1
	for index in range(mini(limit, clean.length())):
		if clean[index] in ".!?" and (index + 1 == clean.length() or clean[index + 1] in " \n\t\"”'"):
			end = index + 1
	return clean.substr(0, end).strip_edges() if end > 0 else ""

static func pages(text: String, target := 260) -> Array[String]:
	var output: Array[String] = []
	var remaining := text.strip_edges()
	while remaining.length() > target:
		var cut := -1
		for i in range(mini(target, remaining.length())):
			if remaining[i] in ".!?" and (i + 1 == remaining.length() or remaining[i + 1] == " "): cut = i + 1
		if cut < target / 3:
			cut = remaining.rfind(" ", target)
		if cut <= 0: cut = target
		output.append(remaining.substr(0, cut).strip_edges())
		remaining = remaining.substr(cut).strip_edges()
	if not remaining.is_empty(): output.append(remaining)
	return output
