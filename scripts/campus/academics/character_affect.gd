extends RefCounted
## Affect recovers over minutes, independently of persistent relationship memory.
## Values may coexist (amused and irritated, confident and angry). Saved states
## are migrated against the baseline before applying or recovering a signal.
const RECOVERY:={
	"happiness":.0008,"anger":.0007,"irritation":.0009,"frustration":.00065,"stress":.0006,
	"excitement":.0017,"boredom":.0007,"sadness":.0003,"disappointment":.0004,"anxiety":.0008,
	"embarrassment":.0011,"amusement":.0017,"confidence":.0006,"tiredness":.0002,"interest":.0008,"patience":.0007,
}
const EXPRESSION:={
	"happiness":"happy","anger":"angry","irritation":"irritated","frustration":"frustrated","stress":"stressed",
	"excitement":"excited","boredom":"bored","sadness":"sad","disappointment":"disappointed","anxiety":"anxious",
	"embarrassment":"embarrassed","amusement":"amused","confidence":"confident","tiredness":"tired",
	"interest":"interested","patience":"patient",
}
const SIGNALS:={
	"insult":{"anger":.25,"irritation":.38,"sadness":.15,"embarrassment":.12,"patience":-.23},
	"apology":{"anger":-.15,"irritation":-.13,"stress":-.08,"sadness":-.05,"patience":.12},
	"compliment":{"happiness":.31,"confidence":.21,"embarrassment":.22},
	"joke":{"amusement":.50,"happiness":.16,"stress":-.12},
	"disruption":{"anger":.17,"irritation":.34,"frustration":.30,"stress":.38,"patience":-.26},
	"success":{"happiness":.46,"excitement":.39,"confidence":.34,"interest":.16,"disappointment":-.27},
	"setback":{"disappointment":.44,"sadness":.25,"frustration":.28,"confidence":-.22,"anxiety":.21},
	"collaboration":{"happiness":.26,"interest":.25,"confidence":.12,"patience":.18,"boredom":-.20},
	"rivalry":{"excitement":.42,"interest":.35,"anxiety":.22,"boredom":-.25},
	"challenge":{"interest":.32,"boredom":-.24},
	"workload":{"stress":.28,"tiredness":.27,"frustration":.23},
	"idle":{"boredom":.31,"tiredness":.13,"interest":-.2},
	"criticism":{"irritation":.12,"disappointment":.13,"interest":.15,"confidence":-.06},
	"constructive_criticism":{"interest":.23,"embarrassment":.06,"confidence":-.03},
	"disagreement":{"interest":.19,"irritation":.06},
	"banter":{"amusement":.34,"happiness":.09,"irritation":.05},
	"teasing":{"amusement":.2,"embarrassment":.12,"irritation":.08},
	"initiative":{"interest":.26,"confidence":.12,"happiness":.11},
	"excitement":{"excitement":.25,"interest":.16},
	"betrayal":{"anger":.34,"sadness":.34,"disappointment":.48,"stress":.23},
	"reconciliation":{"happiness":.17,"anger":-.11,"irritation":-.14,"patience":.15},
}

static func baseline(traits: Dictionary) -> Dictionary:
	return {"happiness":_trait(traits,"optimism")*.28,"anger":.0,"irritation":_trait(traits,"irritability")*.14,
		"frustration":.04,"stress":.05,"excitement":.07,"boredom":.05,"sadness":.03,"disappointment":.03,
		"anxiety":_trait(traits,"anxiety")*.24,"embarrassment":.0,"amusement":.04,
		"confidence":_trait(traits,"confidence"),"tiredness":1.-_trait(traits,"energy"),"interest":_trait(traits,"curiosity")*.32,
		"patience":_trait(traits,"patience")}

static func recover(values: Dictionary,traits: Dictionary,elapsed: float) -> void:
	var rest:=baseline(traits)
	var recovery:=.75+_trait(traits,"emotional_stability")*.55
	for key in RECOVERY:
		values[key]=move_toward(float(values.get(key,rest[key])),float(rest[key]),maxf(0.,elapsed)*float(RECOVERY[key])*recovery)

static func apply(values: Dictionary,traits: Dictionary,signal_name: String,strength: float) -> void:
	var normalized: String={"hostile_criticism":"insult","provocation":"insult","inappropriate_remark":"insult","inappropriate":"insult","harassment":"insult","help":"collaboration","study":"collaboration"}.get(signal_name,signal_name)
	var changes: Dictionary=SIGNALS.get(normalized,{})
	var rest:=baseline(traits)
	for key in changes:
		var scale:=1.0
		match key:
			"anger","irritation","frustration":scale=.6+_trait(traits,"anger_sensitivity")*.8
			"anxiety","stress":scale=1.4-_trait(traits,"stress_tolerance")*.7
			"sadness","disappointment","embarrassment":scale=.55+_trait(traits,"criticism_sensitivity")*.9
			"amusement","excitement":scale=.55+_trait(traits,"excitability")*.9
		if normalized=="apology":scale*=.2+_trait(traits,"forgiveness")*.8
		if normalized in ["insult","criticism"] and key in ["sadness","embarrassment"]:scale*=.4+_trait(traits,"emotional_sensitivity")
		if normalized in ["insult","criticism"] and key=="anger":scale*=.5+_trait(traits,"confrontation")
		values[key]=clampf(float(values.get(key,rest[key]))+float(changes[key])*clampf(strength,0.,1.)*scale,0.,1.)

static func dominant(values: Dictionary,traits: Dictionary) -> String:
	var rest:=baseline(traits)
	var strongest:=.19
	var label:="steady"
	for key in EXPRESSION:
		var score:=float(values.get(key,rest[key]))-float(rest[key])*.7
		if key=="patience":score=float(values.get("patience",rest.patience))-float(rest.patience)
		if key=="confidence":score=float(values.get("confidence",rest.confidence))-float(rest.confidence)
		if key=="tiredness":score=float(values.get("tiredness",rest.tiredness))*.48-.1
		if score<=strongest:continue
		strongest=score
		label=EXPRESSION[key]
	return label

static func presentation(values: Dictionary,traits: Dictionary) -> Dictionary:
	var rest:=baseline(traits)
	var signals:={}
	for key in rest:
		signals[key]=clampf(float(values.get(key,rest[key])),0.,1.)
	var expression:=_trait(traits,"expressiveness")
	return {"emotions":signals,"dominant":dominant(signals,traits),
		"gesture_intensity":clampf(.25+expression*.45+signals.anger*.35+signals.excitement*.3,0.,1.),
		"eye_contact":clampf(.25+_trait(traits,"confidence")*.6-signals.embarrassment*.45,0.,1.),
		"personal_space":clampf(.75+_trait(traits,"shyness")*.5+signals.anxiety*.3,.65,1.6),
		"movement_speed":clampf(.65+_trait(traits,"energy")*.45+signals.anger*.1-signals.tiredness*.2,.45,1.25)}

static func _trait(traits: Dictionary,key: String) -> float:
	# Public student profiles intentionally omit private temperament. Missing
	# traits use a neutral presentation estimate, never a network disclosure
	# or a mutation of the profile. Complete normalized host profiles are exact.
	var value: Variant=traits.get(key,.5)
	if not (value is float or value is int) or not is_finite(float(value)):return .5
	return clampf(float(value),0.,1.)
