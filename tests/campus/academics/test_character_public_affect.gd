extends SceneTree
## Exercise the actual network-facing student profile, not a hand-written full
## trait fixture. The connected-client Faculty loop is tested separately.
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const PUBLIC_TRAITS:=["speaking_pace","expressiveness","energy","shyness","confidence","arrogance"]
# Recorded before the public-profile compatibility fix; normalized full host
# traits must keep their established emotional behavior.
const BRIAN_BASELINE:={"happiness":.189,"anger":0.,"irritation":.1209404,"frustration":.04,"stress":.05,"excitement":.07,"boredom":.05,"sadness":.03,"disappointment":.03,"anxiety":.1056,"embarrassment":0.,"amusement":.04,"confidence":.86,"tiredness":.28,"interest":.11888,"patience":.18}
const BRIAN_RECOVERED:={"happiness":.189,"anger":.3545818,"irritation":.506445,"frustration":.04,"stress":.05,"excitement":.07,"boredom":.05,"sadness":.1051386,"disappointment":.03,"anxiety":.1056,"embarrassment":.02644532,"amusement":.04,"confidence":.86,"tiredness":.28,"interest":.11888,"patience":.0274022}

func _initialize() -> void:
	var person:=Profiles.legacy_student(14)
	var public:=Students._public_profile(person)
	var original_public:=public.duplicate(true)
	assert(public.traits.size()==PUBLIC_TRAITS.size())
	for key in public.traits:assert(key in PUBLIC_TRAITS)
	var values:=Affect.baseline(person.traits)
	values.anger=.92;values.sadness=.74;values.embarrassment=.68;values.irritation=.81
	var before:=values.duplicate(true)
	for frame in 600:
		Affect.recover(values,public.traits,1./60.)
		var shown:=Affect.presentation(values,public.traits)
		assert(shown.emotions.size()==Affect.RECOVERY.size())
		for key in shown.emotions:
			var number:=float(shown.emotions[key])
			assert(is_finite(number) and number>=0. and number<=1.,key)
		assert(shown.dominant==Affect.dominant(values,public.traits))
		for key in ["gesture_intensity","eye_contact","personal_space","movement_speed"]:assert(is_finite(float(shown[key])),key)
	assert(float(values.anger)<float(before.anger) and float(values.anger)>.9,"Repeated client frames must recover slowly without erasing the received emotion")
	assert(float(values.sadness)<float(before.sadness) and float(values.embarrassment)<float(before.embarrassment))
	assert(public==original_public,"Presentation must not populate or transmit omitted private traits")
	assert(Affect.presentation(values,public.traits).dominant=="angry")
	# A partial/old mood snapshot also grows to the full visible state safely.
	var sparse:={"anger":.6}
	Affect.recover(sparse,public.traits,1./60.)
	assert(sparse.size()==Affect.RECOVERY.size() and sparse.anger>.59)
	var empty_traits:={}
	var neutral:=Affect.baseline(empty_traits)
	Affect.recover(neutral,empty_traits,1.)
	assert(empty_traits.is_empty() and Affect.presentation(neutral,empty_traits).dominant=="steady")
	var malformed: Dictionary=public.traits.duplicate(true)
	malformed.energy=NAN;malformed.confidence="unknown"
	var safe:=Affect.baseline(malformed)
	assert(is_equal_approx(safe.confidence,.5) and is_equal_approx(safe.tiredness,.5))
	var brian:=Profiles.teacher("brian")
	var full:=Affect.baseline(brian.traits)
	_close(full,BRIAN_BASELINE)
	Affect.apply(full,brian.traits,"insult",.8)
	Affect.recover(full,brian.traits,37.)
	_close(full,BRIAN_RECOVERED)
	var delivery:=Affect.presentation(full,brian.traits)
	assert(delivery.dominant=="irritated")
	assert(absf(float(delivery.gesture_intensity)-.60570363)<.000001)
	assert(absf(float(delivery.eye_contact)-.754099606)<.000001)
	assert(absf(float(delivery.personal_space)-.80808)<.000001)
	assert(absf(float(delivery.movement_speed)-.95345818)<.000001)
	print("CHARACTER_PUBLIC_AFFECT PASS: actual public profile, 600 recovery frames, private traits absent, full-profile behavior preserved")
	quit(0)

func _close(actual: Dictionary,expected: Dictionary) -> void:
	assert(actual.size()==expected.size())
	for key in expected:assert(absf(float(actual[key])-float(expected[key]))<.000001,key)
