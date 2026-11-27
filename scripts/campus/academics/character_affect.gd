extends RefCounted
## Transient affect is separate from saved interpersonal history. Each signal
## returns toward the character's own baseline at a different rate.
const RECOVERY:={
	"happiness":.010,"anger":.013,"irritation":.010,"frustration":.009,"stress":.009,
	"excitement":.024,"boredom":.012,"sadness":.006,"disappointment":.010,"anxiety":.014,
	"embarrassment":.024,"amusement":.022,"confidence":.008,"tiredness":.004,"interest":.013,"patience":.012,
}
const EXPRESSION:={
	"happiness":"happy","anger":"angry","irritation":"irritated","frustration":"frustrated","stress":"stressed",
	"excitement":"excited","boredom":"bored","sadness":"sad","disappointment":"disappointed","anxiety":"anxious",
	"embarrassment":"embarrassed","amusement":"amused","confidence":"confident","tiredness":"tired",
	"interest":"interested","patience":"patient",
}
const SIGNALS:={
	"insult":{"anger":.25,"irritation":.38,"sadness":.15,"embarrassment":.12,"patience":-.23},
	"apology":{"anger":-.40,"irritation":-.36,"stress":-.19,"sadness":-.13,"patience":.28},
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
}

static func baseline(traits: Dictionary) -> Dictionary:
	return {"happiness":float(traits.optimism)*.28,"anger":.0,"irritation":float(traits.irritability)*.14,
		"frustration":.04,"stress":.05,"excitement":.07,"boredom":.05,"sadness":.03,"disappointment":.03,
		"anxiety":float(traits.anxiety)*.24,"embarrassment":.0,"amusement":.04,
		"confidence":float(traits.confidence),"tiredness":1.-float(traits.energy),"interest":float(traits.curiosity)*.32,
		"patience":float(traits.patience)}

static func recover(values: Dictionary,traits: Dictionary,elapsed: float) -> void:
	var rest:=baseline(traits)
	var recovery:=.75+float(traits.emotional_stability)*.55
	for key in RECOVERY:
		values[key]=move_toward(float(values[key]),float(rest[key]),elapsed*float(RECOVERY[key])*recovery)

static func apply(values: Dictionary,traits: Dictionary,signal_name: String,strength: float) -> void:
	var changes: Dictionary=SIGNALS.get(signal_name,{})
	for key in changes:
		var scale:=1.0
		match key:
			"anger","irritation","frustration":scale=.6+float(traits.anger_sensitivity)*.8
			"anxiety","stress":scale=1.4-float(traits.stress_tolerance)*.7
			"sadness","disappointment","embarrassment":scale=.55+float(traits.criticism_sensitivity)*.9
			"amusement","excitement":scale=.55+float(traits.excitability)*.9
		if signal_name=="apology":scale*=.65+float(traits.forgiveness)*.7
		values[key]=clampf(float(values[key])+float(changes[key])*clampf(strength,0.,1.)*scale,0.,1.)

static func dominant(values: Dictionary,traits: Dictionary) -> String:
	var rest:=baseline(traits)
	var strongest:=.19
	var label:="steady"
	for key in EXPRESSION:
		var score:=float(values[key])-float(rest[key])*.7
		if key=="patience":score=float(values.patience)-float(rest.patience)
		if key=="confidence":score=float(values.confidence)-float(rest.confidence)
		if key=="tiredness":score=float(values.tiredness)*.48-.1
		if score<=strongest:continue
		strongest=score
		label=EXPRESSION[key]
	return label
