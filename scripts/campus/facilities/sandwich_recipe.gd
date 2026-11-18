extends RefCounted

const BREAD := {"white":"Italian white","wheat":"Whole wheat","herb":"Herb & cheese"}
const SIZE := {"six":"6-inch","foot":"Footlong"}
const PROTEIN := {"veg":"Vegetable","turkey":"Turkey","chicken":"Roasted chicken"}
const CHEESE := {"none":"No cheese","cheddar":"Cheddar","swiss":"Swiss"}
const VEGETABLES := {"lettuce":"Lettuce","tomato":"Tomato","cucumber":"Cucumber","onion":"Red onion","pepper":"Bell pepper"}
const SAUCES := {"mayo":"Mayonnaise","mustard":"Mustard","ranch":"Ranch","hot":"Hot sauce"}
const DEFAULT := {"bread":"white","size":"six","protein":"veg","cheese":"none","heated":false,"vegetables":[],"sauces":[]}

static func valid(recipe: Variant) -> bool:
	if not recipe is Dictionary or recipe.size()!=DEFAULT.size():return false
	for key in DEFAULT:
		if not recipe.has(key):return false
	if not BREAD.has(recipe.bread) or not SIZE.has(recipe.size) or not PROTEIN.has(recipe.protein) or not CHEESE.has(recipe.cheese) or not recipe.heated is bool:return false
	return _choices_valid(recipe.vegetables,VEGETABLES,5) and _choices_valid(recipe.sauces,SAUCES,3)

static func _choices_valid(values: Variant, options: Dictionary, limit: int) -> bool:
	if not values is Array or values.size()>limit:return false
	var seen := {}
	for value in values:
		if not value is String or not options.has(value) or seen.has(value):return false
		seen[value]=true
	return true

static func price(recipe: Dictionary) -> int:
	return 6 + (4 if recipe.size=="foot" else 0) + (2 if recipe.protein!="veg" else 0) + (1 if recipe.cheese!="none" else 0)

static func servings(recipe: Dictionary) -> int:
	return 6 if recipe.size=="foot" else 3

static func title(recipe: Dictionary) -> String:
	return "%s %s sub" % [SIZE[recipe.size],PROTEIN[recipe.protein]]

static func names(values: Array, options: Dictionary) -> String:
	var labels := PackedStringArray()
	for value in values:labels.append(str(options[value]))
	return ", ".join(labels)
