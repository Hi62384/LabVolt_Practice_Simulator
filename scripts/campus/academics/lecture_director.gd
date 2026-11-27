extends RefCounted
## Chooses class narration from the host's released curriculum stage.
static func cue(activity: Dictionary, stage: Dictionary, now: float, personality: Dictionary) -> Dictionary:
	var duration:=float(activity.get("teaching",{}).get("duration_seconds",420.0))
	var elapsed := clampf(duration - (float(activity.deadline) - now), 0.0, duration)
	var interval := lerpf(17.0, 10.0, clampf(float(personality.get("talkativeness", .5)),0.0,1.0))
	var slot := floori(elapsed / interval)
	var section_slot:=maxi(0,floori((elapsed-float(stage.get("start_seconds",0.)))/interval))
	var title := str(stage.get("title", activity.get("title","today's lesson")))
	var stage_index := int(stage.get("index",0))
	var strict := float(personality.get("difficulty",.5)) >= .65
	var lines: Array[String] = []
	var text := str(stage.get("text", stage.get("caption",""))).strip_edges()
	for paragraph in text.split("\n",false):
		for sentence in paragraph.split(". ",false):
			if not sentence.strip_edges().is_empty(): lines.append(sentence.strip_edges())
	for step in stage.get("steps",[]):
		var line := str(step.get("text","") if step is Dictionary else step).strip_edges()
		if not line.is_empty() and not lines.has(line): lines.append(line)
	for key in ["formulas","worked"]:
		var line := str(stage.get(key,"")).strip_edges()
		if not line.is_empty() and not lines.has(line): lines.append(line)
	if not lines.is_empty() and section_slot>=lines.size():return {}
	var line := lines[section_slot] if not lines.is_empty() else title
	if slot == 0:
		line = "%s Today’s topic is %s. %s" % [personality.get("opening","Let's begin %s."%activity.course), title, line]
	elif elapsed >= duration-30.:
		line = "Before the assessment, review %s. %s" % [title,line]
	elif slot % 3 == 2:
		line = str(personality.get("check_in","Check your reasoning: " if strict else "Try this check with me: ")) + line
	if not line.ends_with(".") and not line.ends_with("?"): line += "."
	var result := {"key":"%d:%d" % [stage_index,slot],"text":line}
	if slot % 3 == 0: result.anchor = [0.0,-2.6,2.6][posmod(floori(slot / 3.0),3)]
	return result


static func answer(question: String, stage: Dictionary) -> String:
	if stage.is_empty():
		return "Ask about the material as we work through today's lesson."
	var title := str(stage.get("title","this concept"))
	var topic := str(stage.get("text",stage.get("caption","")))
	var query := question.to_lower().split(" ",false)
	var best := ""
	var highest := 0
	for sentence in topic.split(". ",false):
		var lower := sentence.to_lower()
		var score := 0
		for word in query:
			var term := word.strip_edges().trim_suffix("?")
			if term.length() >= 4 and lower.contains(term): score += 1
		if score > highest:
			highest = score
			best = sentence.strip_edges()
	if not best.is_empty(): return best.left(218) + ("." if not best.ends_with(".") else "")
	return ("We're working on %s. Tell me which step or quantity you're unsure about, or use Hint during the practice question." % title).left(220)
