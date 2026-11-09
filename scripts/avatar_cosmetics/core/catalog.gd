extends RefCounted
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
# Match the persistence adapter's currency bound; normalize before strict core validation.
const MAX_PRICE := 1000000000

static func collect(definitions: Array) -> Dictionary:
	var items := {}
	var errors: Array=[]
	for definition in definitions:
		if not definition is Dictionary:errors.append("Definition must be a dictionary");continue
		var canonical: Dictionary=definition.duplicate(true)
		var price = canonical.get("price",0)
		if not (price is int or price is float):errors.append("Invalid price");continue
		if not is_finite(float(price)) or price<0 or price>MAX_PRICE:
			errors.append("Invalid price");continue
		if float(price)!=floor(float(price)):errors.append("Invalid price");continue
		canonical.price=int(price)
		var invalid := Core.validate_definition(canonical)
		if not invalid.is_empty():errors.append_array(invalid);continue
		var id: String=definition.id
		if items.has(id):errors.append("Duplicate cosmetic ID: "+id);continue
		items[id]=canonical
	return {"items":items,"errors":errors}
