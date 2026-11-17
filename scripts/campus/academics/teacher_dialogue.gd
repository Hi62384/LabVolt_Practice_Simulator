extends RefCounted
## Shared offline wording; never changes a grade, inventory, or course answer.
const DATA_PATH := "res://assets/campus/faculty/personalities.json"
static var _config: Dictionary={}
static func personalities() -> Dictionary:
 if _config.is_empty():
  var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
  if parsed is Dictionary and parsed.get("version",0)==1:_config=parsed.get("teachers",{})
 return _config

## Deliberately limited keyword recognition, not a claim to understand free speech.
static func message_intent(message: String) -> String:
 var words:=PackedStringArray()
 var word:=""
 for c in message.to_lower().left(240):
  if (c >= "a" and c <= "z") or c=="'":word+=c
  elif not word.is_empty():words.append(word);word=""
 if not word.is_empty():words.append(word)
 for token in ["sorry","apologize","apologise"]:
  if token in words:return "apology"
 if ("shut" in words and "up" in words) or ("you" in words and ("stupid" in words or "idiot" in words)):return "rude"
 for token in ["help","stuck","confused"]:
  if token in words:return "help"
 if "circuit" in words and ("look" in words or "check" in words or "see" in words) and ("my" in words or "this" in words):return "show_work"
 if ("demonstrate" in words or "demonstration" in words or "experiment" in words) and ("you" in words or "show" in words or "could" in words or "can" in words):return "demonstration_request"
 if ("wrong" in words or "incorrect" in words or "mistake" in words) and ("your" in words or "board" in words):return "challenge"
 if "joke" in words or "funny" in words:return "joke"
 if "?" in message:return "question"
 for token in ["hello","hi","hey"]:
  if token in words:return "greeting"
 return "chat"

static func surprise_comment(personality: Dictionary,course: String,variant: int) -> String:
 var talk:=clampf(float(personality.get("talkativeness",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 if talk<.7 or focus>=.65:return ""
 var subject: String="circuits" if course in ["ETY155","ELM253","DGS266"] else "this problem" if course.begins_with("MTH") else "today's topic"
 var traits:=str(personality.get("description","")).to_lower()
 if "humor" in traits:return "I had a joke about %s, but the answer might need more work. Back to the example."%subject
 if "tired" in traits or "senile" in traits:return "I lost my place for a moment. We were checking %s; let's return to that step."%subject
 if "strict" in traits:return "A brief pause. Now show me the next step for %s."%subject
 var lines:=[
  "That reminds me of a story, but I had better finish the point about %s first."%subject,
  "A quick thought: where might you use %s outside this classroom?"%subject,
  "I almost went off on a tangent there. Let's bring it back to %s."%subject,
 ]
 return str(lines[posmod(variant,lines.size())])

static func overlap_comment(personality: Dictionary) -> String:
 var strict:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 if strict>=.75:return "One voice at a time. Stop talking over the lesson."
 if focus<.4:return "I lost the thread for a moment. Let's take turns and get back to the problem."
 return "One voice at a time, please. Let's return to the problem."

static func lesson_wrap(personality: Dictionary,course: String) -> String:
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 var subject: String="the measured values, polarity, and safe circuit setup" if course in ["ETY155","ELM253"] else ("the chosen formula, units, and each calculation step" if course.begins_with("MTH") else "the input conditions and the logic behind your result")
 if teaching>=.55:return "Before the assessment, check %s. Show the reasoning on your own paper."%subject
 if focus>=.5:return "One last check: %s. Then work independently."%subject
 return "Let's return to the main point: %s. Work from your own notes next."%subject

static func assessment_intro(personality: Dictionary,course: String) -> String:
 var strict:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var talk:=clampf(float(personality.get("talkativeness",.5)),0.0,1.0)
 if strict>=.75:return "The %s assessment is ready. Work independently, show your reasoning, and keep the room quiet."%course
 if teaching>=.7:return "Your %s assessment is ready. Take your time, read each task, and explain your method."%course
 if talk>=.75:return "Now for the %s assessment. Let's see what each of you can do independently."%course
 return "The %s assessment is ready. Please work independently."%course

static func respond(id: String,intent: String,context: Dictionary,variant: int) -> String:
 var p: Dictionary=personalities().get(id,{})
 if p.is_empty():return "I cannot talk right now."
 var teaching: float=float(p.get("teaching",.5)) if p.get("teaching")!=null else .5
 var focus: float=float(p.get("focus",.5)) if p.get("focus")!=null else .5
 var strict: float=float(p.get("difficulty",.5)) if p.get("difficulty")!=null else .9
 var talk: float=float(p.get("talkativeness",.5)) if p.get("talkativeness")!=null else .7
 var traits:=str(p.get("description","")).to_lower()
 var course:=str(context.get("course","the lesson")).left(30)
 var first: Array=[];var second: Array=[]
 match intent:
  "call_on":
   first=["Your turn. Explain how you would approach this question.","Let's hear your reasoning before we reveal the result.","What is your answer, and how did you reach it?"] if teaching>=.6 else ["Your turn. What do you think?","Let's hear your answer.","What would you choose?"]
   if strict>=.75:first=["Your turn. Show your reasoning clearly.","Explain your answer to the class.","I want to hear your method, not just a guess."]
  "help":
   first=["Let's look at this together.","Start with what you know.","Show me where you got stuck."] if teaching>=.6 else ["Take another look.","Try the instructions again.","Work through it one step at a time."]
   second=["Identify the given values and the quantity being asked for.","Check the instructions and explain your next step.","Compare your method with the example in the lesson."] if teaching>=.6 else ["The lesson notes may help.","Write down your question before trying again.","We can come back to that."]
  "chat":
   first=["Hello there.","How are things going?","Good to see you."] if strict<.75 else ["What can I do for you?","Do you need something?","Let's stay attentive."]
   second=["We have work to do in %s."%course,"Let's keep our attention on %s."%course,"Tell me what you need for %s."%course] if focus>=.7 else ["I was thinking about something else entirely.","There's always something interesting happening around campus.","I suppose we can take a moment to talk."]
  "hazard":
   first=["Power is off after a circuit fault. Check the connections before trying again.","The circuit has tripped. Let's inspect the wiring with power off.","That connection caused a fault. Isolate power and review the circuit."]
  "throw":
   if context.get("impact_kind","")=="student":first=["You hit another student with that paper ball. Stop throwing things in class.","That paper ball struck a student. Put it away and check on them."]
   elif context.get("impact_kind","")=="teacher":first=["That paper ball hit me. Stop throwing things in class.","I saw your paper ball hit me. This stops now."]
   else:first=["Your paper ball struck the classroom surface. Stop throwing things.","That paper ball scuffed the room. Please keep classroom materials on the desks."]
  "class_message":
   if context.get("phase","")=="assignment" and context.get("level","calm")=="firm":
    first=["Stop talking during the assessment. Return to your own work now.","This assessment is individual. End the conversation now.","I have asked for quiet. Focus on your own sheet."]
   elif context.get("phase","")=="assignment":
    first=["Please work quietly on your assessment.","Keep your answers to yourself until the assessment ends.","This is individual work. Please stop talking."] if strict>=.6 else ["Let's keep the assessment quiet.","Please focus on your own work for now.","We can talk once the assessment is over."]
   elif context.get("round_mode","")=="demonstration":
    first=["Hold the interruption. Let everyone see the demonstration first.","Please let me finish showing this result, then we can discuss it.","Wait until the demonstration ends before speaking over it."]
   elif context.get("level","calm")=="firm":
    first=["Stop interrupting the lesson. Give the class your attention now.","We have paused for this conversation enough. Return to the lesson.","I need you to stop talking over the class now."]
   else:
    first=["Let's keep the discussion brief during the lesson.","Please give the lesson your attention.","We can continue the conversation after this part."] if strict>=.6 else ["Let's come back to the lesson for a moment.","Hold that thought while we finish this part.","Let's keep going with the lesson."]
  "noise":
   if context.get("phase","")=="assignment" and context.get("level","calm")=="firm":
    first=["That is too loud for an assessment. Stop talking now.","Enough noise. Everyone needs to work independently.","Lower your voice now and return to your assessment."]
   elif context.get("phase","")=="assignment":
    first=["Please keep the assessment room quiet.","Let's keep voices down while others work.","Could you be quiet for the assessment, please?"]
   elif context.get("level","calm")=="firm":
    first=["That is too loud. Stop talking and focus on the class.","Enough noise. This class needs your attention now.","Lower your voice now. You are disrupting the room."]
   else:
    first=["Please keep the noise down.","Let's keep the room quiet for a moment.","Could you lower your voice, please?"]
  "phone":
   if context.get("phase","")=="assignment":first=["Put the phone away during the assessment. Work from your own sheet.","Please close the phone and return to the assessment.","Phones away. Keep your attention on your own work."]
   elif context.get("level","calm")=="firm":first=["That phone is distracting you. Close it and rejoin the lesson now.","I have asked you to put the phone away. Focus on the class.","Phone away now. We are working through this together."]
   else:first=["Please put the phone away while we explain this part.","Let's keep the phone closed during the lesson.","You can check the phone after this activity."]
  "seat_departure":
   first=["Please come back to the lesson when you finish moving around.","Let's settle back in and follow the next step together.","If you need to move, keep it brief and rejoin the class."] if strict<.7 else ["Return to your place and follow the lesson.","Please stop wandering and give the class your attention.","Settle in so we can continue."]
  "rude":
   first=["That language is not acceptable in this class. Explain your concern respectfully.","Stop there. You can disagree, but speak respectfully.","I will listen to a question, not an insult. Try again respectfully."] if strict>=.6 else ["Let's pause. Tell me what is wrong without insulting anyone.","I hear that you are upset. Please explain it respectfully.","We can discuss the problem when you speak respectfully."]
  "apology":
   first=["All right. Let's get back to work.","Thank you for saying so. Let's move on.","I appreciate the apology. Let's continue."] if strict>=.6 else ["That's all right. Let's move on.","No problem. Thanks for saying so.","It's okay. We can continue."]
  "question":
   first=["Tell me which part you would like to understand.","What have you tried so far?","Let's identify the part you're asking about."] if teaching>=.6 else ["Could you be more specific?","Check the lesson notes and tell me where you're stuck.","Let's come back to that question."]
  "challenge":
   first=["Show me the step you disagree with, and we will check it together.","Which line of the working looks wrong to you? Let's test it.","Point out the disputed step before we decide whether the result is right."]
   if context.get("round_mode","")=="mistake":first=["Good catch. Identify the first incorrect step on the board before I reveal it.","There may be an error in this worked example. Show us where it begins.","Check each step on the board and explain which one fails."]
  "show_work":
   var physical: Dictionary=context.get("physical_state",{})
   if context.get("round_mode","")=="physical" and physical.get("fault",false):first=["The station has tripped. Isolate power and inspect the circuit before showing a result."]
   elif context.get("round_mode","")=="physical" and physical.get("changed",false):first=["I can see a valid station change. Explain what you adjusted; we will compare the measurement after predictions close."]
   elif context.get("round_mode","")=="physical":first=["Show me a permitted live change at your assigned station first, then we can compare the measurement."]
   else:first=["Tell me which connection or measurement you want checked. Keep power off while changing the circuit."]
  "demonstration_request":
   first=["Let's try a demonstration when this activity clears. Make a prediction before I show the result."] if context.get("scheduled",false) else ["We can consider a demonstration when this lesson has room for it."]
  "decline":
   first=["You may skip this optional round. Try the next question with us.","That's your choice for this practice. Follow the worked example.","Watch this round, then join us for the next one."] if strict>=.7 else ["That's fine for this optional practice. Keep following the lesson.","You can watch this time and try the next one.","Take a moment, then rejoin when you're ready."]
  "joke":
   if "friendly jokes" in traits or "playful humor" in traits:first=["All right, that one made me smile. Back to the lesson.","You got a laugh. Now show me how you'd solve the problem.","I see what you did there. Let's get back to work."]
   elif "warm encouragement" in traits:first=["A little laughter helps. Let's keep trying.","That was funny. Now let's work through the next step.","I like the spirit. Let's return to the question."]
   elif talk>=.75 and focus<.65:first=["All right, that one made me smile. Back to the lesson.","You got a laugh. Now show me how you'd solve the problem.","I see what you did there. Let's get back to work."]
   elif strict>=.7:first=["Save the jokes until after class. We have a problem to solve.","I heard you. Keep your attention on the lesson.","Let's leave the comedy for the break."]
   else:first=["Fair enough. Let's return to the question.","A quick laugh is fine. Now back to it.","All right. What's the next step?"]
  "greeting":
   first=["Hello. How can I help?","Hi there.","Hello. What do you need?"]
  _:
   first=["See you later.","Take care.","Back to it, then."]
 var output:=str(first[posmod(variant,first.size())])
 if not second.is_empty() and (talk>=.4 or intent=="help"):output+=" "+str(second[posmod(int(variant/3),second.size())])
 var relationship: Dictionary=context.get("relationship",{})
 if intent=="help" and int(relationship.get("positive",0))>=3:output+=" I appreciate you asking questions."
 elif intent=="chat" and int(relationship.get("familiarity",0))>=4:output+=" Good to see you again."
 if id=="jeff" and not context.get("in_class",false) and intent=="chat":output="Hi. If something's bothering you, you can talk to me."
 if intent in ["help","question"]:
  var guidance:=_guidance(context)
  if not guidance.is_empty():output+=" "+guidance
  if "ai examples" in traits:output+=" Verify any suggested result against the given values."
  elif "order and concentration" in traits:output+=" Keep each step in order."
  elif "warm encouragement" in traits:output+=" Take it one step at a time."
 if id=="mr_bro" and intent=="chat":output+=" Remember to make time for your workouts."
 elif id=="chad" and intent=="chat":output+=" Keep working toward your goals."
 elif id=="ms_bird_heart" and intent=="chat":output+=" You're doing fine, dear."
 return output.left(350)

static func _guidance(context: Dictionary) -> String:
 var course:=str(context.get("course","")).to_upper()
 var phase:=str(context.get("phase",""))
 if phase=="assignment":return "For the assessment, explain your reasoning and check your work against the task instructions. I can discuss the method without giving you the answer."
 if context.get("round_mode","")=="physical":
  var state: Dictionary=context.get("physical_state",{})
  if state.get("fault",false):return "The station has tripped. Switch off power and inspect the setup before trying another measurement."
  if state.get("changed",false):return "The station has a valid measured change. Keep your prediction separate until the result is revealed, then compare the two values."
  return "Make one permitted station change, observe the live meter, and record whether you expect the RMS value to rise, fall, or stay close."
 if context.get("round_mode","")=="group":
  var progress: Dictionary=context.get("team_progress",{})
  if progress.is_empty():return "Use your own team's notes to compare methods. You can still submit your own answer."
  if int(progress.get("notes",0))==0:return "Start your team's notes with a known value or assumption. Ask a teammate to check it against the question."
  if int(progress.get("submitted",0))==0:return "Your team has a starting note. Have someone explain or challenge its next step, then submit your own answer."
  return "Your team has an answer in. Compare the method with the question and make your own submission before time expires."
 if context.get("round_mode","")=="board":return "Write the known quantities on the board, explain the next step, and ask the class to check your reasoning."
 var topic:=str(context.get("title","")).strip_edges().left(64)
 var prefix:="For %s, "%topic if not topic.is_empty() else ""
 match course:
  "ETY155":return prefix+"identify the supply rails, component values, and polarity before you power the circuit. Then measure one node at a time."
  "ELM253":return prefix+"trace the complete current path with power isolated. Check the meter connection and range before taking a reading."
  "DGS266":return prefix+"write the truth table first, then simplify the logic expression and test each input combination."
  "MTH147","MTH255":return prefix+"write the known values and the required result, choose the relevant formula, and check units after calculating."
  _:
   if phase=="lesson":return prefix+"compare your next step with the example on the board and ask about the point where they differ."
 return "Tell me which course and step you are working on so I can give a more specific hint."
