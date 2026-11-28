extends RefCounted
## Preserve whole sentences; subtitle pages never remove spoken content.
const MAX_TEXT := 1600
const MAX_SEGMENTS := 6

static func complete(text: String, limit := MAX_TEXT) -> String:
	var clean := text.strip_edges().replace("\r", " ").replace("\n", " ")
	if clean.length() <= limit: return clean
	var end := -1
	for index in range(mini(limit, clean.length())):
		if clean[index] in ".!?" and (index + 1 == clean.length() or clean[index + 1] in " \n\t\"”'"):
			end = index + 1
	return clean.substr(0, end).strip_edges() if end > 0 else ""

# A streaming boundary must have lookahead: a period at the end of the
# current delta could still become a decimal, abbreviation or ellipsis.
# Long replies retain the first five sentence boundaries and coalesce the
# remainder to bound voice-session startup costs and memory.
static func sentence_parts(text: String, complete_field: bool=true) -> Array[String]:
	var parts: Array[String]=[]
	var clean:=text.replace("\r"," ").replace("\n"," ")
	var start:=0
	var i:=0
	while i<clean.length() and parts.size()<MAX_SEGMENTS-1:
		if clean[i] not in ".!?":
			i+=1;continue
		var end:=i+1
		while end<clean.length() and clean[end] in ".!?\"”'’)]":end+=1
		if end==clean.length() and not complete_field:break
		if end<clean.length() and clean[end] not in " \t":
			i=end;continue
		if clean[i]==".":
			var before:=clean.substr(start,i-start+1).strip_edges()
			var token:=before.get_slice(" ",before.get_slice_count(" ")-1).to_lower()
			if token in ["mr.","mrs.","ms.","dr.","prof.","st.","vs.","etc.","e.g.","i.e.","a.m.","p.m.","a.c.","d.c."] or (token.length()==2 and token[0].to_lower()!=token[0].to_upper()):
				i=end;continue
			# Do not divide a dotted initialism, e.g. U.S. or Ph.D.
			if token.count(".")>1 and not token.ends_with("..."):
				i=end;continue
		var sentence:=clean.substr(start,end-start).strip_edges()
		if not sentence.is_empty():parts.append(sentence)
		start=end;i=end
	if complete_field:
		var remainder:=clean.substr(start).strip_edges()
		if not remainder.is_empty():parts.append(remainder)
	return parts

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
