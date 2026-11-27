extends RefCounted
## The authored anchors describe different aspects of a person. Related traits
## are derived together so a generated classmate's habits agree with their speech.

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
		"curiosity":curiosity,"creativity":lerpf(curiosity,humor,.4),"focus":focus,"attention_span":lerpf(focus,patience,.35),
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
	},true)
	return values

static func activity_preferences(traits: Dictionary) -> Dictionary:
	return {"demonstration":traits.demonstrations,"group":traits.cooperativeness,
		"quiz":traits.competitiveness,"practice":traits.independence,"board":traits.explanation_depth}

static func prompt_traits(traits: Dictionary) -> String:
	var rounded:={}
	for name in traits:
		rounded[name]=snappedf(float(traits[name]),.01)
	return JSON.stringify(rounded)
