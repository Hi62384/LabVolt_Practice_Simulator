extends RefCounted
## Pure fictional vocal design. The persistent voice store owns actual IDs.
const DESIGNS_PATH:="res://assets/campus/faculty/character_voice_designs.json"
# Heuristic preset suggestions, not measured acoustic classifications.
const HINTS:={
	"alloy":["androgynous",.50,.50,.50],"ash":["masculine",.35,.55,.50],
	"ballad":["masculine",.56,.75,.64],"coral":["feminine",.63,.72,.58],
	"echo":["masculine",.60,.38,.66],"sage":["feminine",.45,.72,.38],
	"shimmer":["feminine",.73,.58,.76],"verse":["androgynous",.62,.55,.72],
	"marin":["androgynous",.43,.73,.42],"cedar":["masculine",.32,.48,.34]
}
const MAX_PROMPT:=2000
static var _authored: Dictionary={}

static func _load_authored() -> void:
	if _authored.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGNS_PATH))
		if parsed is Dictionary and parsed.get("version")==1 and parsed.get("voices") is Dictionary:
			_authored=parsed.voices.duplicate(true)

static func authored() -> Dictionary:
	_load_authored()
	return _authored.duplicate(true)

static func has_authored(id: String) -> bool:
	_load_authored()
	return _authored.has(id)

static func _text(value: Variant,fallback: String,limit: int) -> String:
	if not value is String:return fallback
	var clean: String=value.strip_edges()
	return fallback if clean.is_empty() else clean.left(limit)

static func _number(value: Variant,fallback: float,low: float,high: float) -> float:
	return clampf(float(value),low,high) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _suggest(presentation: String,pitch: float,warmth: float,pace: float,preferred: String="") -> String:
	var selected: String="alloy"
	var best:=INF
	for id: String in HINTS:
		var hint: Array=HINTS[id]
		var distance:=absf(pitch-float(hint[1]))*.9+absf(warmth-float(hint[2]))*.7+absf(pace-float(hint[3]))*.7
		if presentation!="androgynous" and hint[0]!=presentation:distance+=.65 if hint[0]=="androgynous" else 2.
		elif presentation=="androgynous" and hint[0]!="androgynous":distance+=.45
		if id==preferred:distance-=.28
		if distance<best:best=distance;selected=id
	return selected

static func draft(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	if id.is_empty():return {}
	_load_authored()
	if _authored.has(id):return _authored[id].duplicate(true)
	var role:=str(person.get("role","student"))
	var traits: Dictionary=person.get("traits",{}) if person.get("traits",{}) is Dictionary else {}
	var vocal: Dictionary={}
	var dossier: Variant=person.get("dossier",{})
	if dossier is Dictionary and dossier.get("voice") is Dictionary:vocal=dossier.voice.duplicate(true)
	if person.get("voice") is Dictionary:vocal.merge(person.voice,true)
	if person.get("vocal_identity") is Dictionary:vocal.merge(person.vocal_identity,true)
	var description_words:=" "+str(vocal.get("profile","")).to_lower()+" "+str(vocal.get("characteristics","")).to_lower()+" "
	# Only explicitly supplied acoustic descriptions inform legacy migration;
	# never derive voice presentation from names, appearance, or demographics.
	var described_presentation:="androgynous"
	if "feminine" in description_words or " female " in description_words:described_presentation="feminine"
	elif "masculine" in description_words or " male " in description_words:described_presentation="masculine"
	var presentation:=str(vocal.get("presentation",person.get("vocal_presentation",described_presentation))).to_lower()
	if presentation not in ["masculine","feminine","androgynous"]:presentation=described_presentation
	var age:=int(_number(vocal.get("perceived_age",person.get("age",22)),22.,18.,110.))
	var warmth:=_number(traits.get("warmth"),.5,0.,1.)
	var speaking:=_number(traits.get("speaking_pace"),.5,0.,1.)
	var pace:=_number(vocal.get("normal_pace"),.85+speaking*.28,.65,1.3)
	var default_pitch:="low or low-middle register" if "low register" in description_words or "deep voice" in description_words or "bass-baritone" in description_words else "upper-middle register" if "high register" in description_words or "higher pitch" in description_words else "middle register with natural conversational variation"
	var pitch:=_text(vocal.get("pitch_range"),default_pitch,180)
	var pitch_value:=.35 if "low" in pitch.to_lower() or "deep" in pitch.to_lower() else .68 if "upper" in pitch.to_lower() or "high" in pitch.to_lower() else .5
	var accent:=_text(vocal.get("accent",person.get("accent")),"natural North American English",180)
	var timbre:=_text(vocal.get("timbre"),"rounded and warm" if warmth>.6 else "clear and dry",180)
	var resonance:=_text(vocal.get("resonance"),"balanced, unforced resonance",180)
	var texture:=_text(vocal.get("texture"),"light natural breath and grain",180)
	var articulation:=_text(vocal.get("articulation"),"clear conversational diction",220)
	var manner:=_text(vocal.get("characteristics",person.get("style")),"plain-spoken",500)
	var described:=_text(vocal.get("profile"),"",420)
	if described.begins_with("Permanent voice of "):described=""
	var preferred: String=str(vocal.get("identifier","")) if not described.is_empty() and str(person.get("dossier_status",""))=="complete" else ""
	var voice:=_suggest(presentation,pitch_value,warmth,clampf((pace-.65)/.65,0.,1.),preferred)
	var profile:={"character_id":id,"provider":"openai","voice_type":"preset","permanent_voice_id":voice,
		"compatible_model_families":["gpt-live-1.1","gpt-live-1","gpt-realtime-2.1","gpt-realtime-2.1-mini","gpt-audio-1.5","gpt-4o-mini-tts"],
		"perceived_age":age,"vocal_presentation":presentation,"pitch_range":pitch,"resonance":resonance,
		"timbre":timbre,"texture":texture,"accent":accent,"normal_pace":pace,"normal_projection":"normal",
		"articulation":articulation,"mannerisms":manner,
		"emotional_tendencies":"Express emotions within this person's natural range; mood changes performance, not speaker identity.",
		"profile_version":1,"audition_status":"not_auditioned","approval_status":"provisional_preset",
		"voice_design_status":"matched_dossier_pool","allocation":"faculty" if role in ["teacher","staff"] else "student"}
	var prompt:="An original fictional adult voice, age about %d, %s vocal presentation. Pitch: %s. Resonance: %s. Timbre: %s. Texture: %s. Accent: %s. Articulation: %s. Natural speaking manner: %s."%[age,presentation,pitch,resonance,timbre,texture,accent,articulation,manner]
	if not described.is_empty():prompt+=" Additional fictional vocal design: "+described+"."
	var suffix:=" Keep age, timbre and accent stable across calm, happiness, sadness, anger and fatigue. No permanent baked-in emotion. Do not imitate a real or identifiable person."
	profile.design_description=prompt.left(MAX_PROMPT-suffix.length())+suffix
	profile.provisional_notice="Heuristically matched shared preset; not an auditioned custom voice. Speaker is saved once, never rematched on mood changes."
	return profile

static func dossier_seed(person: Dictionary) -> Dictionary:
	var profile:=draft(person)
	if profile.is_empty():return {}
	return {"identifier":str(profile.permanent_voice_id),"profile":str(profile.design_description),"characteristics":str(profile.mannerisms),
		"delivery":"Mood changes delivery, never the underlying vocal identity.",
		"presentation":str(profile.vocal_presentation),"perceived_age":int(profile.perceived_age),
		"pitch_range":str(profile.pitch_range),"resonance":str(profile.resonance),"timbre":str(profile.timbre),
		"texture":str(profile.texture),"accent":str(profile.accent),"articulation":str(profile.articulation),"normal_pace":float(profile.normal_pace)}
