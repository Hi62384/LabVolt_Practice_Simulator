extends RefCounted

const Recipe = preload("res://scripts/campus/facilities/sandwich_recipe.gd")
const OVEN_MS := 10000
const OVEN_LOAD_MS := 800
const MAX_IDLE_MS := 90000
const LABELS := ["Choose bread", "Choose the length", "Choose a filling and cheese", "Toast the sandwich?", "Add vegetables", "Choose sauces", "Confirm your sandwich"]
var owner := 0
var station := ""
var step := 0
var recipe: Dictionary = {}
var touched := 0
var oven_until := 0
var filling_chosen := false
var cheese_chosen := false

func start(peer: int, counter: String, now: int) -> bool:
	if owner != 0: return false
	owner = peer
	station = counter
	step = 0
	touched = now
	oven_until = 0
	filling_chosen = false
	cheese_chosen = false
	recipe = Recipe.DEFAULT.duplicate(true)
	return true

func clear() -> void:
	owner = 0
	recipe = {}
	oven_until = 0

func expired(now: int) -> bool:
	return owner > 0 and now - touched >= MAX_IDLE_MS

func tick(now: int) -> bool:
	if oven_until == 0 or now < oven_until: return false
	oven_until = 0
	step = 4
	return true

func choose(key: String, now: int) -> bool:
	if owner == 0 or oven_until > 0: return false
	var parts := key.split("/")
	if parts.size() != 2: return false
	var kind := parts[0]
	var value := parts[1]
	match step:
		0:
			if kind != "bread" or not Recipe.BREAD.has(value): return false
			recipe.bread = value
			step = 1
		1:
			if kind != "size" or not Recipe.SIZE.has(value): return false
			recipe.size = value
			step = 2
		2:
			if kind == "protein" and Recipe.PROTEIN.has(value):
				recipe.protein = value
				filling_chosen = true
			elif kind == "cheese" and Recipe.CHEESE.has(value):
				recipe.cheese = value
				cheese_chosen = true
			elif key == "advance/next" and filling_chosen and cheese_chosen:
				step = 3
			else: return false
		3:
			if kind != "toast" or value not in ["yes","no"]: return false
			recipe.heated = value == "yes"
			if recipe.heated: oven_until = now + OVEN_LOAD_MS + OVEN_MS
			else: step = 4
		4,5:
			var field := "vegetables" if step==4 else "sauces"
			var options := Recipe.VEGETABLES if step==4 else Recipe.SAUCES
			if key == "advance/next":
				step += 1
			elif kind == field and options.has(value):
				var choices: Array = recipe[field]
				if value in choices: choices.erase(value)
				elif choices.size() < (5 if step==4 else 3): choices.append(value)
				else: return false
			else: return false
		_: return false
	touched = now
	return true

func snapshot(now: int) -> Dictionary:
	if owner == 0: return {}
	return {"owner":owner,"step":step,"recipe":recipe.duplicate(true),"oven_ms":maxi(0,oven_until-now),"label":LABELS[step],"price":Recipe.price(recipe)}
