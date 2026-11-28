extends RefCounted
## Legacy anchors supply defaults; explicit authoring and independent generated
## dimensions take precedence. Correlated defaults never override saved traits.

static func author_overrides(id: String) -> Dictionary:
	match id:
		"chad":
			return {"independence":.96,"confidence":.98,"arrogance":.96,"selfishness":.86,"meanness":.85,"empathy":.14,
				"ambition":.99,"generosity":.17,"willingness_to_help":.19,"interest_in_student_success":.21,
				"dominance":.90,"humility":.09,"respectfulness":.30,"competitiveness":.96,"teaching_patience":.28,"confrontation":.83,"stubbornness":.91,"willingness_to_disagree":.97,"sarcasm":.82,"forgiveness":.22}
		"mr_bro":
			return {"confidence":.9,"arrogance":.67,"empathy":.44,"ambition":.7,"generosity":.46,"slang":.96,
				"willingness_to_help":.38,"storytelling":.62,"teaching_patience":.38,"playfulness":.93,"risk_taking":.68,"stubbornness":.57,"confrontation":.66,"shyness":.05,"teaching_effort":.28,"interest_in_student_success":.32,"professionalism":.18,"formality":.08,"carelessness":.76,"focus":.16,"conversational_length":.26}
		"ms_rivera":
			return {"willingness_to_help":.28,"teaching_patience":.38,"interest_in_student_success":.30,"professionalism":.54,"focus":.16,"laziness":.87,"motivation":.23,"initiative":.19,"stubbornness":.6,"confidence":.66,"shyness":.25}
		"ms_bird_heart":
			return {"empathy":.97,"generosity":.94,"willingness_to_help":.98,"interest_in_student_success":.99,"assertiveness":.78,"emotional_sensitivity":.94,"criticism_sensitivity":.8,"confrontation":.28,"stubbornness":.43,"forgiveness":.73}
		"mr_stone":
			return {"dominance":.96,"discipline":.99,"professionalism":.94,"slang":.02,"interruption_tolerance":.07,"confidence":.94,"confrontation":.82,"stubbornness":.78,"respect_for_authority":.96,"forgiveness":.39,"empathy":.42}
		"brian":
			return {"confrontation":.88,"teaching_patience":.13,"interruption_tolerance":.12,"self_control":.46,"anger_sensitivity":.98,"meanness":.71,"confidence":.86,"stubbornness":.84,"willingness_to_disagree":.95,"empathy":.22,"forgiveness":.25}
		"stanley":
			return {"teaching_effort":.08,"interest_in_student_success":.2,"motivation":.12,"energy":.19,"initiative":.08,"confrontation":.12,"shyness":.16,"confidence":.78,"laziness":.82,"stubbornness":.71,"willingness_to_help":.28,"teaching_patience":.35}
		"ms_clocks":
			return {"confidence":.88,"organization":.98,"focus":.95,"self_control":.93,"confrontation":.58,"stubbornness":.58,"sarcasm":.34,"respectfulness":.7,"teaching_effort":.9}
		"dr_volts":
			return {"confidence":.8,"curiosity":.99,"enthusiasm":.98,"excitability":.95,"focus":.55,"stubbornness":.44,"willingness_to_disagree":.81,"risk_taking":.52,"misbehavior":.08}
		"mr_gusto":
			return {"confidence":.85,"playfulness":.96,"sarcasm":.69,"shyness":.06,"confrontation":.5,"stubbornness":.39,"teasing":.82,"empathy":.77}
		"jeff":
			return {"confidence":.86,"confrontation":.73,"strictness":.96,"stubbornness":.63,"respect_for_authority":.81,"generosity":.67,"shyness":.08}
		"bill_nye":
			return {"confidence":.8,"curiosity":.94,"stubbornness":.28,"willingness_to_disagree":.85,"confrontation":.48,"arrogance":.29,"humility":.76}
		"mr_apple":
			return {"confidence":.69,"storytelling":.97,"rambling":.91,"stubbornness":.51,"initiative":.72,"shyness":.1,"organization":.4}
		"mr_phillips":
			return {"confidence":.87,"stubbornness":.48,"willingness_to_disagree":.72,"humility":.68,"organization":.84,"confrontation":.52}
		"mr_hamstrings":
			return {"confidence":.76,"stubbornness":.62,"competitiveness":.67,"discipline":.81,"initiative":.73,"teasing":.54}
		"mr_allu":
			return {"teaching_effort":.22,"confidence":.38,"shyness":.86,"awkwardness":.82,"initiative":.22,"curiosity":.78,"stubbornness":.32,"respect_for_authority":.39,"willingness_to_disagree":.49,"focus":.24}
		"bill":
			return {"confidence":.9,"stubbornness":.81,"confrontation":.7,"organization":.94,"sarcasm":.61,"empathy":.39,"respect_for_authority":.86}
		"mr_blake":
			return {"confidence":.8,"curiosity":.9,"stubbornness":.46,"risk_taking":.66,"patience":.49,"initiative":.86,"focus":.41}
		"josh_wildes":
			return {"confidence":.84,"stubbornness":.69,"willingness_to_disagree":.94,"respect_for_authority":.36,"playfulness":.55,"competitiveness":.78,"bluntness":.82,"criticism_sensitivity":.46,"teaching_effort":.18,"willingness_to_help":.38}
		"bradley":
			return {"confidence":.72,"shyness":.42,"stubbornness":.56,"focus":.83,"confrontation":.36,"self_control":.87,"initiative":.41}
		"ms_lunch":
			return {"confidence":.86,"assertiveness":.91,"confrontation":.72,"stubbornness":.64,"empathy":.74,"organization":.91,"patience":.52}
	return {}

static func independent_student_traits(rng: RandomNumberGenerator) -> Dictionary:
	var values := {}
	# Each draw is independent; confident/shy, mean/helpful or diligent/rebellious
	# combinations remain possible. Biographies and decisions explain the mixture.
	for key in ["meanness","empathy","anger_sensitivity","confrontation","shyness","confidence","arrogance","humor","sarcasm","friendliness","selfishness","motivation","academic_ability","study_habits","misbehavior","curiosity","emotional_sensitivity","competitiveness","initiative","respect_for_authority","stubbornness","willingness_to_disagree","forgiveness","grudges","generosity","risk_taking","self_control","criticism_sensitivity","academic_motivation","cooperativeness","ambition","teasing"]:
		values[key] = rng.randf_range(.06,.95)
	values.patience = rng.randf_range(.1,.94)
	values.trustfulness = rng.randf_range(.1,.9)
	values.optimism = rng.randf_range(.08,.92)
	values.emotional_stability = rng.randf_range(.12,.92)
	values.academic_confidence = rng.randf_range(.1,.94)
	values.playfulness = rng.randf_range(.06,.95)
	return values

static func expand(base: Dictionary, social: float, confidence: float, focus: float, curiosity: float, strictness: float) -> Dictionary:
	var warmth:=float(base.warmth)
	var patience:=float(base.patience)
	var humor:=float(base.humor)
	var temper:=float(base.temper)
	var energy:=float(base.energy)
	var reasoning:=float(base.reasoning)
	var teaching:=float(base.get("teaching_competence",.35))
	var effort:=float(base.get("teaching_effort",.3))
	var discipline:=lerpf(focus,strictness,.35)
	var resilience:=lerpf(patience,confidence,.5)
	var empathy:=lerpf(warmth,patience,.35)
	var play:=lerpf(humor,social,.25)
	var values:=base.duplicate()
	values.merge({
		"friendliness":warmth,"meanness":temper*(1.-empathy),"introversion":1.-social,
		"extroversion":social,"sociability":lerpf(social,warmth,.25),"shyness":(1.-confidence)*(1.-social*.4),
		"confidence":confidence,"assertiveness":lerpf(confidence,strictness,.3),"confrontation":lerpf(temper,confidence,.35),
		"empathy":empathy,"compassion":lerpf(empathy,warmth,.3),"emotional_sensitivity":lerpf(warmth,1.-resilience,.5),
		"honesty":.54+.4*discipline,"trustfulness":lerpf(warmth,1.-strictness,.4),
		"cooperativeness":lerpf(empathy,discipline,.25),"competitiveness":lerpf(confidence,1.-empathy,.35),
		"talkativeness":social,"initiative":lerpf(social,confidence,.4),"awkwardness_tolerance":resilience,
		"anger_sensitivity":temper,"emotional_stability":resilience,"irritability":temper*(1.-patience*.45),
		"anxiety":1.-resilience,"optimism":lerpf(warmth,confidence,.5),"pessimism":1.-lerpf(warmth,confidence,.5),
		"enthusiasm":lerpf(energy,curiosity,.4),"excitability":lerpf(play,energy,.5),
		"forgiveness":empathy,"grudges":lerpf(temper,1.-empathy,.55),"criticism_sensitivity":1.-lerpf(confidence,patience,.4),
		"pride":lerpf(confidence,strictness,.4),"expressiveness":lerpf(social,energy,.4),
		"stress_tolerance":resilience,"impulsiveness":lerpf(1.-discipline,temper,.35),
		"sarcasm":humor*(.9-.5*warmth),"playfulness":play,"seriousness":lerpf(strictness,1.-humor,.5),
		"formality":lerpf(strictness,1.-social,.3),"bluntness":lerpf(temper,1.-warmth,.55),
		"politeness":lerpf(empathy,discipline,.3),"teasing":play*(.95-.35*empathy),
		"vocabulary_complexity":lerpf(reasoning,discipline,.3),"speech_energy":lerpf(energy,social,.25),
		"speaking_pace":lerpf(energy,temper,.15),"rambling":social*(1.-focus*.6),
		"storytelling":lerpf(social,play,.4),"interrupting":temper*(1.-patience*.9),
		"conversational_length":lerpf(social,patience,.3),"awkwardness":(1.-resilience)*(1.-social*.4),
		"slang":social*(1.-strictness*.75),"laziness":1.-lerpf(energy,discipline,.5),
		"work_ethic":lerpf(discipline,effort,.4),"motivation":lerpf(energy,effort,.45),
		"intelligence":reasoning,"carelessness":1.-discipline,"curiosity":curiosity,"creativity":lerpf(curiosity,humor,.4),"focus":focus,"attention_span":lerpf(focus,patience,.35),
		"discipline":discipline,"independence":lerpf(confidence,focus,.35),"risk_taking":confidence*(1.-discipline*.75),
		"responsibility":lerpf(discipline,empathy,.25),"professionalism":lerpf(discipline,strictness,.3),
		"organization":lerpf(focus,discipline,.35),"adaptability":lerpf(curiosity,patience,.4),
		"self_control":resilience,"respect_for_authority":discipline,"misbehavior":(1.-discipline)*temper,
		"mental_arithmetic":lerpf(reasoning,focus,.3),"learning_ability":lerpf(reasoning,curiosity,.35),
		"teaching_competence":teaching,"teaching_effort":effort,"subject_passion":lerpf(curiosity,effort,.35),
		"willingness_to_help":lerpf(empathy,effort,.45),"simplification":lerpf(teaching,patience,.25),
		"attention_to_understanding":lerpf(teaching,empathy,.5),"teaching_patience":lerpf(patience,teaching,.2),
		"explanation_depth":lerpf(teaching,focus,.4),"strictness":strictness,
		"interruption_tolerance":patience*(1.-strictness*.45),"demonstrations":float(base.get("demonstrations",.3)),
		"academic_confidence":lerpf(confidence,reasoning,.4),"study_interest":curiosity,
		"academic_motivation":lerpf(curiosity,effort,.5),"study_habits":lerpf(discipline,focus,.4),
		"selfishness":1.-empathy,"generosity":warmth*.85,"dominance":confidence*.8,"respectfulness":lerpf(empathy,discipline,.4),
		"arrogance":confidence*(1.-empathy),"humility":empathy*(1.-confidence*.45),"jealousy":(1.-resilience)*.7,
		"ambition":lerpf(confidence,effort,.4),"conversational_confidence":lerpf(confidence,social,.4),
		"stubbornness":lerpf(confidence,strictness,.4),"academic_ability":reasoning,"willingness_to_disagree":lerpf(strictness,confidence,.5),"mischievousness":play*(1.-discipline*.65),
		"teaching_creativity":lerpf(teaching,curiosity,.55),"interest_in_student_success":lerpf(warmth,effort,.4),
	},true)
	values.merge(base,true)
	return values

static func activity_preferences(traits: Dictionary) -> Dictionary:
	return {"demonstration":traits.demonstrations,"group":traits.cooperativeness,
		"quiz":traits.competitiveness,"practice":traits.independence,"board":traits.explanation_depth}

static func prompt_traits(traits: Dictionary) -> String:
	var rounded:={}
	for name in traits:
		rounded[name]=snappedf(float(traits[name]),.01)
	return JSON.stringify(rounded)

static func required_keys() -> Array:
	# Generated people supply every dimension themselves. These legacy defaults
	# define the compatibility schema only; they never generate new students.
	var base := {"warmth":.5,"patience":.5,"humor":.5,"temper":.5,"energy":.5,"reasoning":.5}
	return expand(base,.5,.5,.5,.5,.5).keys()
