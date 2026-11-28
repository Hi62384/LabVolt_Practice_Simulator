extends SceneTree
const Transcript=preload("res://scripts/campus/ai/speech_transcript.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	for pair: Array in [
		["My bench press record is 315 pounds.","My bench press record is three hundred and fifteen pounds."],
		["The voltage is 12.5 V.","The voltage is twelve point five volts."],
		["The current is -2 A.","The current is negative two amperes."],
		["It draws 0.005 A.","It draws zero point zero zero five amps."],
		["Use 1,250 ohms.","Use one thousand two hundred fifty ohms."],
		["I can't do it. Let's ask Dr. Volts.","I cannot do it, let us ask Doctor Volts!"],
		["2 + 3 = 5.","Two plus three equals five."],
		["12 / 3 = 4.","Twelve divided by three equals four."],
		["The load is 20 mA.","The load is twenty milliamps."],
		["This is 3.3 kΩ.","This is three point three kiloohms."],
		["The signal is DC.","The signal is D C."]
	]:
		if not Transcript.matches(pair[0],pair[1]):failures.append("Equivalent: "+str(pair)+" => "+Transcript.canonical(pair[0])+" / "+Transcript.canonical(pair[1]))
	for pair: Array in [
		["The voltage is 12.5 V.","The voltage is one hundred twenty five volts."],
		["The current is -2 A.","The current is two amperes."],
		["Do not touch the terminal.","Do touch the terminal."],
		["Use 3 mA.","Use three megaamperes."],
		["Use 3 MA.","Use three milliamperes."],
		["The answer is 2 + 3.","The answer is two times three."],
		["My record is 315 pounds.","My record is three hundred fifty pounds."],
		["The value is 12.05.","The value is twelve point five."],
		["Say one two.","Say three."],
		["Yes.","Yes. I promise."],
		["...","!"],
		["A line.",""]
	]:
		if Transcript.matches(pair[0],pair[1]):failures.append("Mismatch accepted: "+str(pair))
	for failure: String in failures:push_error(failure)
	print("SPEECH_TRANSCRIPT ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
