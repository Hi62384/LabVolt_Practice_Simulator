extends RefCounted
## Proposed simulator sequence informed by the supplied DGS266 materials.
const TOPICS := [
 {"title":"Digital signals and waveforms","source":"Introduction to digital and  waveforms.pptx","theory":"Digital signals use discrete logic levels. A timing diagram relates input and output levels over time; period is the duration of one cycle and frequency is its reciprocal.","worked":"A 200 Hz periodic waveform has a period of 1/200 s, or 5 ms.","lab":"Use a signal generator and scope to observe a digital waveform. Measure the period and compare frequency, duty cycle and logic levels."},
 {"title":"Binary and number systems","source":"Number Systems.pptx","theory":"Binary digits represent powers of two. Hexadecimal digits group four binary bits. Place values, rather than the printed digits alone, determine the represented number.","worked":"Binary 1011 equals 8 + 2 + 1 = decimal 11, or hexadecimal B.","lab":"Record binary switch combinations and convert them to decimal and hexadecimal. Test all four-bit inputs; distinguish decimal values from their BCD encoding."},
 {"title":"Logic gates and truth tables","source":"Logic Gates.pptx; DGS266_Lab4.pdf","theory":"NOT complements a bit; AND requires all inputs high; OR requires at least one. NAND and NOR invert those outputs, while XOR is high when two inputs differ.","worked":"For A=1 and B=0, A AND B=0, A OR B=1, and A XOR B=1.","lab":"With power off, wire a supported gate IC on a breadboard, supply the specified logic rails, use switches for inputs and a resistor-limited LED for output. Record every input combination and compare to the truth table."},
 {"title":"Boolean algebra and simplification","source":"Boolean Algebra and Logic Simplification.pptx","theory":"Boolean identities and De Morgan's theorems transform expressions while preserving each truth-table row. Grouping adjacent minterms in a Karnaugh map can remove changing variables.","worked":"A AND (B OR NOT B) simplifies to A because B OR NOT B is always 1.","lab":"Predict and record the truth table for a mixed-gate expression. Rebuild a simplified equivalent and compare all input combinations."},
 {"title":"Combinational logic analysis","source":"Combinational Logic Analysis.pptx","theory":"Combinational outputs depend on present inputs. Trace each gate in order, then compare the expression and truth table for every input combination.","worked":"Y=(A AND B) OR C is high for A=1, B=1, C=0 because the AND term is high.","lab":"Build a small combinational circuit with gate ICs, switch inputs and a resistor-limited indicator. Record intermediate nodes and verify the complete truth table."},
 {"title":"Combinational functions and displays","source":"Functions of Combinational Logic.pptx; DGS266 - LAB 6 Instructions.pdf","theory":"Decoders convert input codes into output selections. A seven-segment digit uses individually controlled segments, whose active polarity depends on the display and driver.","worked":"A decimal digit uses seven named segments a through g; digit 8 uses all seven.","lab":"Use the educational 74LS47 model and common-anode display. With power off, connect the display common to +5 V, each segment through its own resistor to the corresponding active-low driver output, and the four BCD inputs to defined switch levels. Keep /LT, /BI and /RBI high for normal operation. Test decimal inputs 0–9 and compare the displayed pattern."},
 {"title":"Latches and flip-flops","source":"Latches  and Flip-Flops.pptx; Latches and Flip Flops Practice Questions.pdf","theory":"Sequential logic stores state. A positive-edge D flip-flop captures D on a rising clock edge; asynchronous controls can override the clock.","worked":"If D is 1 immediately before an active rising edge, an enabled D flip-flop stores Q=1 after the edge.","lab":"Power a supported 74HC74, set preset and clear inactive, drive D and the clock with defined levels, and record Q before and after rising edges."},
 {"title":"Integrated digital systems and PLC concepts","source":"Course Introduction.pptx; Functions of Combinational Logic.pptx","theory":"Digital systems combine logic, memory, inputs and outputs. A PLC reads inputs, executes a program and updates outputs in a scan; implementation details depend on the controller.","worked":"A simple interlock enables an output only when both the run command and safety condition are true.","lab":"Build and test a two-input interlock with supported gate components. Explain the equivalent input–logic–output sequence; this exercise is not a full PLC simulation."}
]
static func catalog() -> Dictionary:
 return {"id":"DGS266","course_id":"DGS266","title":"Digital Electronics and Introduction to PLC","subject":"Electrical","description":"Learn digital waveforms, number systems, logic gates, combinational and sequential logic, and introductory PLC concepts through lecture and lab activities.","icon":"dc_nodes","lecture_weeks":TOPICS.size(),"lab_weeks":TOPICS.size(),"sequence_status":"Proposed simulator sequence based on supplied examples; not an official timetable"}
static func weeks(kind: String) -> Array:
 if kind not in ["lecture","lab"]:return []
 var result:=[]
 var weight_policy: Dictionary=preload("res://scripts/campus/academics/grade_weight_policy.gd").course("DGS266")
 var weights: Array=weight_policy.get(kind,[])
 for i in TOPICS.size():
  var row:Dictionary=TOPICS[i]
  result.append({"week":i+1,"title":row.title,"topics":[row.title],"kind":kind,"source":{"document":row.source,"basis":"Supplied course examples; original simulator lesson"},"equipment":["Breadboard","DC supply","Logic ICs","Switches","LED and resistors"],"sequence_status":"proposed","is_exam":false,"assessment_type":"assignment","grade_weight":weights[i] if i<weights.size() else null})
 return result
static func lesson(week: int,kind: String,duration: int=420) -> Dictionary:
 var list:=weeks(kind)
 if week<1 or week>list.size():return {"error":"Unknown course, kind or week"}
 var info:Dictionary=list[week-1].duplicate(true);var row:Dictionary=TOPICS[week-1]
 var sections:=[row.theory,row.worked,row.lab if kind=="lab" else "Apply the concept to a new input or timing example and explain your reasoning."]
 var stages:=[];var time:=0;var total:=clampi(duration,300,600)
 for i in sections.size():
  var length:=total-time if i==sections.size()-1 else int(total/sections.size())
  stages.append({"id":"DGS266.%s.%d.%d"%[kind,week,i],"start_seconds":time,"duration_seconds":length,"duration":length,"title":["Concept","Worked example","Lab activity" if kind=="lab" else "Practice"][i],"caption":sections[i],"text":sections[i],"formulas":"","worked":row.worked if i==1 else "","highlight":i})
  time+=length
 info.merge({"course_id":"DGS266","duration":total,"duration_seconds":total,"presentation_id":"DGS266.%s.%d.v1"%[kind,week],"stages":stages,"timeline":stages,"theory":row.theory,"formulas":"","worked":row.worked,"procedure":row.lab,"equipment_text":row.lab,"source_gates":[],"objectives":["Explain "+row.title,"Predict outputs and verify the result"]},true)
 return info
static func generate(week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
 var info:=lesson(week,kind)
 if info.has("error"):return info
 var Q=preload("res://scripts/campus/courses/dc_assignments.gd")
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 var a:=rng.randi_range(0,1);var b:=rng.randi_range(0,1)
 var q:=[]
 match week:
  1:q.append(Q.numeric("What is the period of a 200 Hz waveform?",5.0,"ms","T = 1/f = 0.005 s."))
  2:q.append(Q.numeric("Convert binary 1011 to decimal.",11.0,"","8 + 2 + 1 = 11."))
  3:q.append(Q.choice("For A=%d and B=%d, what is A XOR B?"%[a,b],["0","1"],int(a!=b),"XOR is high when the two inputs differ."))
  4:q.append(Q.choice("Which expression is equivalent to A AND (B OR NOT B)?",["A","B","NOT A","0"],0,"B OR NOT B is 1, so the result is A."))
  5:q.append(Q.choice("For A=1, B=1, C=0, what is (A AND B) OR C?",["0","1"],1,"The AND term is 1 and C is 0."))
  6:q.append(Q.numeric("How many segments a–g are lit to form the digit 8?",7.0,"","All seven segments are on."))
  7:q.append(Q.choice("What does a positive-edge D flip-flop capture at its active edge?",["The D input","The clock frequency","The supply current","The previous input forever"],0,"With asynchronous controls inactive, the D level is stored on the active edge."))
  8:q.append(Q.choice("Which condition enables an AND interlock?",["Either input is high","Both inputs are high","Both inputs are low","The inputs differ"],1,"An AND output is high only when both inputs are high."))
 q.append(Q.choice("What should you do before changing breadboard wiring?",["Turn the output off","Increase the supply voltage","Short the supply","Leave all leads connected to live power"],0,"Turn outputs off before modifying the circuit."))
 if kind=="lab":
  match week:
   1:q.append(Q.choice("A square wave completes one cycle in 5 ms. What frequency should the oscilloscope show?",["200 Hz","50 Hz","5 Hz","2000 Hz"],0,"Frequency is the reciprocal of the period: 1 / 0.005 s = 200 Hz."))
   2:q.append(Q.choice("While testing four binary switches, how many distinct input combinations should you record?",["4","8","16","32"],2,"Four independent binary inputs have 2⁴ = 16 combinations."))
   3:q.append(Q.choice("How should the indicator LED be connected to limit its current?",["With a resistor in series","Directly across the supply","With a wire across the LED","Without a return path"],0,"A series resistor limits current through the LED."))
   4:q.append(Q.choice("How can you check whether two logic circuits are equivalent?",["Compare their outputs for every input combination","Compare their physical sizes","Measure only one input combination","Use different supply voltages"],0,"Equivalent combinational circuits produce the same output for every input combination."))
   5:q.append(Q.choice("When tracing a combinational circuit, what should you measure before its final output?",["Its intermediate gate outputs","Only the supply label","The disconnected breadboard","The wire colours"],0,"Intermediate gate outputs help locate the first stage that differs from the predicted truth table."))
   6:q.append(Q.choice("For the modeled 74LS47 and common-anode display, how is each segment connected?",["Through a separate resistor to a driver output","Directly between two driver outputs","Directly across the supply without a resistor","Through a single wire with no driver"],0,"Each active-low output sinks its own segment current through a series resistor."))
   7:q.append(Q.choice("With preset and clear inactive, when does the modeled 74HC74 capture D?",["At a rising clock edge","Continuously while the clock is low","Only when power is removed","At every falling edge"],0,"The modeled D flip-flop captures D on a rising clock edge."))
   8:q.append(Q.choice("How many input combinations must a two-input interlock be tested against?",["Two","Three","Four","Eight"],2,"Two binary inputs have four combinations: 00, 01, 10 and 11."))
 var procedure: String=info.procedure
 var result := {"course_id":"DGS266","week":week,"kind":kind,"difficulty":clampi(difficulty,0,4),"title":info.title,"theory":info.theory,"data":info.worked,"procedure":procedure,"equipment_text":procedure,"worked_example":info.worked,"source":info.source,"questions":q,"teaching_id":info.presentation_id,"assessment_type":"assignment","is_exam":false,"grade_weight":info.grade_weight,"assessment_policy":{"practice_never_official":true,"default_seconds":1800,"gradebook_owner":"academics"},"source_gates":[],"seed":seed_value,"teaching":{"equipment":procedure,"worked":info.worked},"lab_validation":"written_only"}
 if kind=="lab":
  if week==1:
   procedure+="\n\nConnect the function generator GEN to oscilloscope S1 and REF to GND. Set the generator to Square or Pulse and capture at least two complete cycles. Select Record waveform on this worksheet. Written answers and the connected capture each count for half the mark."
   result.practical={"type":"digital_scope"};result.lab_validation="digital_scope"
  elif week==2:
   procedure+="\n\nPower a 74HC08 and connect four switches to inputs 1A, 1B, 2A and 2B (least to most significant bit). Set each four-bit combination and select Record binary inputs. Record all 16 values and keep the same wiring until submission. Written answers and recorded input combinations each count for half the mark."
   result.practical={"type":"digital_binary"};result.lab_validation="digital_binary"
  elif week==3:
   procedure+="\n\nPower a supported logic gate. Set each input combination and select Record gate levels on this worksheet. Record all four combinations for a two-input gate, or both combinations for NOT. Keep the same wiring until submission. Written answers and recorded gate levels each count for half the mark."
   result.practical={"type":"digital_truth_table"};result.lab_validation="digital_truth_table"
  elif week==4:
   procedure+="\n\nBuild A AND (B OR NOT B) using 74HC04, 74HC32 and 74HC08 gates. Set all four A/B combinations and select Record gate levels for each; the output should equal A. Keep the same wiring until submission. Written answers and recorded behavior each count for half the mark."
   result.practical={"type":"digital_simplify"};result.lab_validation="digital_simplify"
  elif week==5:
   procedure+="\n\nBuild Y = (A AND B) OR C using a 74HC08 and 74HC32. Set all eight A/B/C combinations and select Record gate levels for each. Keep the same wiring until submission. Written answers and recorded behavior each count for half the mark."
   result.practical={"type":"digital_combination"};result.lab_validation="digital_combination"
  elif week==6:
   procedure+="\n\nWith the 74LS47 driving a common-anode display through individual segment resistors, set each BCD value from 0 to 9. Select Record display for each value and keep the same wiring until submission. Written answers and recorded display behavior each count for half the mark."
   result.practical={"type":"digital_display"};result.lab_validation="digital_display"
  elif week==7:
   procedure+="\n\nWith preset and clear inactive, use Record gate levels on the worksheet before and after a rising clock edge with D low, then repeat with D high. Keep D unchanged across each recorded edge and keep the same wiring until submission. Written answers and recorded behavior each count for half the mark."
   result.practical={"type":"digital_flipflop"};result.lab_validation="digital_flipflop"
  elif week==8:
   procedure+="\n\nPower a 74HC08 AND gate as the interlock. Set each input combination and select Record gate levels on this worksheet. Record all four combinations and keep the same wiring until submission. Written answers and recorded behavior each count for half the mark."
   result.practical={"type":"digital_interlock"};result.lab_validation="digital_interlock"
  else:procedure+="\n\nUse the bench equipment to perform the activity. Your submitted written answers are graded; the simulator does not automatically grade your circuit."
  result.procedure=procedure;result.equipment_text=procedure;result.teaching.equipment=procedure
 return result
