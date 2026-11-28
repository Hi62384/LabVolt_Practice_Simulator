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
		["Use 5 mW and 2 MW.","Use five milliwatts and two megawatts."],
		["Use 4.7 µF and 10 nH.","Use four point seven microfarads and ten nanohenries."],
		["The frequency is 5 MHz.","The frequency is five megahertz."],
		["Use 5 H.","Use five henries."],
		["2 * (3 + 4) = 14.","Two times open parenthesis three plus four close parenthesis equals fourteen."],
		["Ask Mr. Bro (our teacher).","Ask Mister Bro, our teacher."],
		["I am here as a student.","I am here as a student."],
		["The signal is DC.","The signal is D C."]
	]:
		if not Transcript.matches(pair[0],pair[1]):failures.append("Equivalent: "+str(pair)+" => "+Transcript.canonical(pair[0])+" / "+Transcript.canonical(pair[1]))
	for pair: Array in [
		["The voltage is 12.5 V.","The voltage is one hundred twenty five volts."],
		["The current is -2 A.","The current is two amperes."],
		["Do not touch the terminal.","Do touch the terminal."],
		["Use 3 mA.","Use three megaamperes."],
		["Use 3 MA.","Use three milliamperes."],
		["Use 5 mW.","Use 5 MW."],
		["Use 5 mW.","Use five MW."],
		["Use 5 mF.","Use 5 MF."],
		["Use 5 mHz.","Use 5 MHz."],
		["The value is 5 H.","The value is 5 h."],
		["2 * (3 + 4) = 14.","2 * 3 + 4 = 14."],
		["x * (y + z).","x * y + z."],
		["The interval is [1, 2].","The interval is (1, 2)."],
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
