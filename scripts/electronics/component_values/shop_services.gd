extends RefCounted
## Pure bridge to the component shop's existing describe/quote service shape.
const Values=preload("res://scripts/electronics/component_values/values.gd")

static func describe(id: String, catalog: Dictionary) -> Dictionary:
	var resolved := Values.resolve(id,catalog)
	if not resolved.ok:return {"fields":[],"error":resolved.error}
	var result: Array=[]
	var specs := Values.fields(resolved.entry)
	for key in specs:
		var spec: Dictionary=specs[key].duplicate(true)
		spec.key=key
		spec.default=Values.format_value(float(spec.default),str(spec.unit))
		spec.help="Supported range: %s to %s. SI prefixes are case sensitive."%[Values.format_value(float(spec.minimum),str(spec.unit)),Values.format_value(float(spec.maximum),str(spec.unit))]
		result.append(spec)
	return {"fields":result}

static func quote(id: String, settings: Dictionary, amount: Variant, catalog: Dictionary, inventory: Dictionary) -> Dictionary:
	if id.begins_with("ic:"):return Values.fail("Use the existing host-priced custom-circuit purchase service")
	var resolved := Values.resolve(id,catalog)
	if not resolved.ok:return resolved
	# A listed procedural variant supplies its existing overrides when edited.
	var merged: Dictionary=resolved.settings.duplicate(true);merged.merge(settings,true)
	var configured := Values.configure(str(resolved.base_id),merged,catalog)
	if not configured.ok:return configured
	var stock: Variant=inventory.get(configured.id,0)
	if not (stock is int or stock is float) or not is_finite(float(stock)) or float(stock)!=floor(float(stock)) or stock<0 or stock>Values.MAX_STACK:return Values.fail("Invalid inventory count")
	var plan := Values.intent(str(resolved.base_id),merged,amount,catalog,int(stock))
	if not plan.ok:return plan
	return {"ok":true,"unit_price":plan.unit_price,"total":plan.total_price,"id":plan.id,"intent":{"op":"buy_configured","args":[resolved.base_id,merged,plan.quantity]}}
