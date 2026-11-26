extends RefCounted

const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const DATASET:="Campus Lab Reasoning 1"
const PATH:="user://openai_comparison_v1.cfg"
const OUTPUT_LIMIT:=512
# Original prompts with objective, fixed grading. These are not GPQA or MMMU-Pro items.
const QUESTIONS:=[
	["At 12 V across a 4 Ω resistor, what is the current? A: 0.33 A, B: 3 A, C: 8 A, D: 48 A.","B"],
	["A 6 Ω and a 3 Ω resistor are connected in parallel. What is the equivalent resistance? A: 2 Ω, B: 3 Ω, C: 4.5 Ω, D: 9 Ω.","A"],
	["A 10-bit ADC has 1024 bins across exactly 5 V. What is one bin's nominal width? A: 0.49 mV, B: 2.44 mV, C: 4.88 mV, D: 20.48 mV.","C"],
	["An ideal 60 Hz sine wave with a peak of 14.14 V has about what RMS voltage? A: 7.07 V, B: 14.14 V, C: 28.28 V, D: 10 V.","D"],
	["A first-order RC circuit starts uncharged when a DC step is applied. After one time constant, about what percentage of its final capacitor voltage is reached? A: 37%, B: 63%, C: 86%, D: 100%.","B"],
	["A worksheet records 24 trials. Exactly one quarter failed, and half of the failed trials were retried. How many failed trials were not retried? A: 3, B: 6, C: 9, D: 12.","A"],
	["A voltmeter should measure the drop across a component without substantially changing its current. What is appropriate? A: Low resistance in series, B: Low resistance in parallel, C: High resistance in parallel, D: High resistance in series.","C"],
	["A table lists test IDs A1, B2, A3, and B4. Return the last test whose ID starts with A by selecting its option. A: B2, B: A1, C: B4, D: A3.","D"]
]
var completed: Dictionary={}
var progress: Dictionary={}
var running:=false
var canceled:=false

func _init() -> void:
	var cfg:=ConfigFile.new()
	if cfg.load(PATH)==OK:
		var values: Variant=cfg.get_value("runs","complete",{})
		if values is Dictionary:completed=values
		values=cfg.get_value("runs","progress",{})
		if values is Dictionary:progress=values

func key(id: String, effort: String, mode: String) -> String:
	return JSON.stringify([DATASET,id,effort,mode])

func _prompt(index: int) -> String:
	return "Choose one answer. Reply with only its capital letter A, B, C, or D.\n"+str(QUESTIONS[index][0])

func estimate(id: String, first := 0) -> int:
	var rate:=Pricing.pricing(id,"text")
	if rate.is_empty():return -1
	var total:=0
	for index in range(first,QUESTIONS.size()):
		var cost:=Pricing.token_cost(rate,{"input":_prompt(index).to_utf8_buffer().size()+384,"output":OUTPUT_LIMIT})
		if cost<0:return -1
		total+=cost
	return total

func record(id: String, effort: String, mode: String) -> Dictionary:
	var result: Variant=completed.get(key(id,effort,mode),{})
	return result if result is Dictionary else {}

func _save() -> void:
	var cfg:=ConfigFile.new()
	cfg.set_value("runs","schema",1)
	cfg.set_value("runs","complete",completed)
	cfg.set_value("runs","progress",progress)
	cfg.save(PATH)

func run(service: Node,id: String,effort: String,mode: String,budget: int,draft: Dictionary,report: Callable) -> void:
	if running or not service.host_allowed() or (not service.configured() and str(draft.get("key","")).is_empty()):return
	if effort!=Models.normalize_effort(id,effort) or not Models.available_for(id,"text"):return
	var signature:=key(id,effort,mode)
	var state: Dictionary=progress.get(signature,{"run_id":Crypto.new().generate_random_bytes(12).hex_encode(),"next":0,"right":0,"results":[]})
	var first:=int(state.next)
	var maximum:=estimate(id,first)
	if maximum<0 or maximum>budget:
		if report.is_valid():report.call("The selected budget cannot cover this run.")
		return
	canceled=false
	running=true
	for index in range(first,QUESTIONS.size()):
		if canceled or service.busy or not is_instance_valid(service):break
		if report.is_valid():report.call("Question %d of %d"%[index+1,QUESTIONS.size()])
		var result: Dictionary=await service.comparison_question(_prompt(index),id,effort,mode,OUTPUT_LIMIT,draft)
		var measurement: Dictionary=result.get("measurement",{})
		# A transport error or mismatched reply settings must not become a scored question.
		if not result.get("ok",false) or (not effort.is_empty() and str(measurement.get("effort",effort))!=effort):
			if report.is_valid():report.call("Paused · "+str(result.get("error","Reported effort differs from the selected effort.")))
			break
		var answer:=str(result.get("text","")).strip_edges().to_upper().trim_suffix(".")
		var correct:=answer==str(QUESTIONS[index][1])
		state.right+=int(correct)
		state.next=index+1
		state.results.append({"correct":correct,"measurement":measurement})
		progress[signature]=state
		_save()
	running=false
	if int(state.next)==QUESTIONS.size():
		var times: Array=[]
		var totals:={}
		var snapshots:={}
		var costs_known:=0
		var cost_total:=0
		for item in state.results:
			var measurement: Dictionary=item.measurement
			if measurement.has("latency_ms"):times.append(measurement.latency_ms)
			if not str(measurement.get("model","")).is_empty():snapshots[measurement.model]=true
			for field in ["input","output","cached","reasoning"]:
				if measurement.get("usage",{}).has(field):totals[field]=totals.get(field,0)+measurement.usage[field]
			if int(measurement.get("cost",-1))>=0:
				costs_known+=1
				cost_total+=int(measurement.cost)
		times.sort()
		var elapsed:=0
		for value in times:elapsed+=int(value)
		var n:=QUESTIONS.size()
		var ratio:=float(state.right)/n
		var denominator:=1.0+3.8416/n
		var center:=(ratio+3.8416/(2.*n))/denominator
		var half:=1.96*sqrt((ratio*(1.-ratio)+3.8416/(4.*n))/n)/denominator
		completed[signature]={"model":id,"snapshots":snapshots.keys(),"reasoning_effort":effort,"reasoning_mode":mode,
			"source_type":"local","benchmark":DATASET,"score_percent":100.*ratio,"correct":state.right,"questions":n,
			"interval":[100.*maxf(0.,center-half),100.*minf(1.,center+half)],"avg_ms":float(elapsed)/times.size() if not times.is_empty() else -1.,
			"median_ms":(float(times[(times.size()-1)/2])+float(times[times.size()/2]))*.5 if not times.is_empty() else -1.,
			"usage":totals,"cost":cost_total if costs_known==n else -1,"run_id":state.run_id,"timestamp":Time.get_datetime_string_from_system(true)}
		progress.erase(signature)
		if completed.size()>128:completed.erase(completed.keys()[0])
		_save()
		if report.is_valid():report.call("Complete · %d / %d correct"%[state.right,n])
	elif report.is_valid() and canceled:report.call("Paused · %d of %d recorded"%[state.next,QUESTIONS.size()])
