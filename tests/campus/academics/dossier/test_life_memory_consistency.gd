extends SceneTree
## Local semantic-boundary checks; no authored reply is evidence of AI quality.
const Life = preload("res://scripts/campus/academics/character_life_memory.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var original := {"topic":"bench_press_pr","detail":"My bench press record is 287 pounds.","value":"287 pounds","kind":"current"}
	var records := {}
	var checked := Life.validate(original, original.detail, records)
	check(checked.ok and not checked.review, "A directly quoted canonical quantity is locally grounded")
	var boasting := original.duplicate(true)
	boasting.detail += " Not bad for an old guy."
	check(not Life.validate(boasting, boasting.detail, {}).review, "Unrelated conversational negation does not force a validation request")
	Life.apply(records, checked)
	var contradiction := {"topic":"bench_press_pr","detail":"My bench press record is 325 pounds.","value":"287 pounds","kind":"current"}
	check(not Life.validate(contradiction, contradiction.detail, records).ok, "An unchanged stored value cannot hide a contradictory spoken number")
	check(not Life.speech_check(contradiction.detail, records, [contradiction], true).ok, "Merely proposing the topic cannot bypass utterance consistency")
	var unrelated_value := {"topic":"squat.record","detail":"My squat record is 391 pounds.","value":"700 pounds","kind":"current"}
	check(not Life.validate(unrelated_value, unrelated_value.detail, records).ok, "A new canonical quantity absent from the quoted detail is rejected")
	var explained := {"topic":"bench_press_pr","detail":"My bench press record is 325 pounds now.","value":"325 pounds","kind":"current","revision":"update","reason":"I finally managed a heavier lift after training all spring."}
	var spoken: String = explained.detail + " " + explained.reason
	checked = Life.validate(explained, spoken, records)
	check(checked.ok and not checked.review and Life.speech_check(spoken, records, [explained], true).ok, "An explained current record update remains valid")
	Life.apply(records, checked)
	check(records.bench_press_pr.value == "325 pounds" and records.bench_press_pr.history.size() == 1 and records.bench_press_pr.history[0].value == "287 pounds", "A legitimate record update preserves the earlier value")
	var cross_subject := "My bench press record is 444 pounds. My deadlift record is 325 pounds."
	check(not Life.speech_check(cross_subject, records, [], true).ok, "Another subject's number cannot satisfy the bench record check")
	var joined_subject := "My bench press record is 444 pounds, and my deadlift record is 325 pounds."
	check(not Life.speech_check(joined_subject, records, [], true).ok, "Conjoined personal subjects retain their own quantities")
	var mixed := Life.speech_check("My bench press was 444 before my current 325 pounds.", records, [], true)
	check(mixed.ok and mixed.review, "An unexplained additional number next to a recalled value requires deeper review")
	var recall := Life.speech_check("Bench press, 325 pounds.", records, [], true)
	check(recall.ok and not recall.review, "Direct recollection requires no extra validation request")
	var historical := Life.speech_check("My bench press record is 325 pounds. I reached it on my 22nd birthday.", records, [], true)
	check(historical.ok and historical.review, "Recalling an old number cannot silently establish another numerical life detail")
	var squat := {"topic":"squat.record","detail":"My squat record is 391 pounds.","value":"391 pounds","kind":"current"}
	var independent := Life.speech_check(squat.detail, records, [squat], true)
	check(independent.ok and not independent.review, "Different personal subjects can establish independent grounded numbers")
	check(Life.normalized("not vegetarian") != Life.normalized("vegetarian"), "Canonical value comparison preserves negation")
	check(Life.normalized("Never trained") != Life.normalized("Trained"), "Canonical value comparison preserves historical denials")
	var diet := {"topic":"diet.preference","detail":"I am not vegetarian.","value":"not vegetarian","kind":"preference"}
	var diet_records := {}
	Life.apply(diet_records, Life.validate(diet, diet.detail, diet_records))
	var reversal := {"topic":"diet.preference","detail":"I am vegetarian now.","value":"vegetarian","kind":"preference"}
	check(not Life.validate(reversal, reversal.detail, diet_records).ok, "Dropping not cannot silently reverse an established preference")
	reversal.revision = "update"
	reversal.reason = "I changed what I cook after moving to a new flat."
	checked = Life.validate(reversal, reversal.detail + " " + reversal.reason, diet_records)
	check(checked.ok, "An explicitly explained change in preference remains possible")
	Life.apply(diet_records, checked)
	check(diet_records["diet.preference"].history[0].value == "not vegetarian", "A preference reversal retains the original negative fact")
	var semantic := {"topic":"social.style","detail":"I usually keep to myself when strangers visit.","value":"introverted","kind":"current"}
	check(Life.validate(semantic, semantic.detail, {}).get("review", false) and Life.speech_check(semantic.detail, {}, [semantic], true).review, "Nonliteral canonicalization is flagged for semantic review rather than treated as locally proven")
	var negated_value := {"topic":"diet.preference","detail":"I am not vegetarian.","value":"vegetarian","kind":"preference"}
	check(Life.speech_check(negated_value.detail, {}, [negated_value], true).review, "A positive canonical label under a negative quote requires deeper validation")
	var spoken_number := {"topic":"bench.record","detail":"My bench record is three hundred pounds.","value":"300 pounds","kind":"current"}
	check(Life.speech_check(spoken_number.detail, {}, [spoken_number], true).review, "A spelled-out numerical paraphrase requires semantic validation")
	check(Life.speech_check("My bench record is three hundred eighty pounds.", records, [], true).review, "Spelling a conflicting number cannot bypass an established quantity without a proposal")
	var mixed_spelling := {"topic":"career.duration","detail":"I worked there for five years, starting in 2018.","value":"5 years","kind":"historical"}
	check(Life.validate(mixed_spelling,mixed_spelling.detail,{}).get("review",false), "Written quantity alongside a numeric date can receive semantic review")
	var fake_timestamp := Life.speech_check("My favorite number is " + str(records.bench_press_pr.at) + ".", records, [], true)
	check(not fake_timestamp.ok, "Persistence timestamps are not treated as spoken personal knowledge")
	print("LIFE_MEMORY_CONSISTENCY ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)
