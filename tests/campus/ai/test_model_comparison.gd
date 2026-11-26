extends SceneTree

const Pricing = preload("res://scripts/campus/ai/model_pricing.gd")
const Comparison = preload("res://scripts/campus/ai/model_comparison.gd")
const Models = preload("res://scripts/campus/ai/openai_models.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var standard := Pricing.pricing("gpt-5.4-mini", "text")
	assert(standard.input==.75 and standard.output==4.5)
	assert(Pricing.token_cost(standard,{"input":800,"output":200})==1500000)
	assert(Pricing.token_cost(standard,{"input":800,"cached":200,"output":200})==1365000)
	assert(Comparison.measurement("gpt-5.4-mini","text","low").status=="missing")
	assert(Comparison.score("gpt-5.4-mini","text","xhigh")==88.0)
	assert(Comparison.score("gpt-5.4-mini-2026-03-17","text","xhigh")==-1.0)
	assert(Comparison.score("gpt-6.2-astra","text","max")==-1.0)
	assert(Comparison.score("gpt-6.2-astra","text")==97.0)
	assert(not Models.supports("text-embedding-3-small","text"))
	assert(Models.lifecycle("o4-mini","2026-11-26").status=="retired")
	print("MODEL_COMPARISON PASS")
	quit()
