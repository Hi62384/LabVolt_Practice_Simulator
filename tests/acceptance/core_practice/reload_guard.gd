extends RefCounted
## Test-only JSON roundtrip guard. Production persistence/schema are unchanged.
const Profile=preload("res://scripts/electronics_profile.gd")
static func grid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=0.0
static func pins_shape(pins: Variant) -> bool:
	if not pins is Array or pins.is_empty() or pins.size()>64:return false
	for pin in pins:
		if not pin is Dictionary:return false
		for key in ["id","name","node","role","connector"]:
			if not pin.get(key) is String:return false
		if not pin.get("position") is Dictionary:return false
		if pin.position.size()!=2 or not grid_number(pin.position.get("x")) or not grid_number(pin.position.get("y")):return false
	return true
static func matches(expected: Variant,actual: Variant,inventory: Variant) -> bool:
	# Profile.same retains all dictionary keys and exact array ordering. Only
	# int/float representation differs; numeric values still compare exactly.
	return pins_shape(expected) and pins_shape(actual) and Profile.same(expected,actual) and grid_number(inventory) and float(inventory)==1.0
static func field(expected: Variant,actual: Variant) -> Dictionary:
	return {"expected":expected,"actual":actual,"expected_type":typeof(expected),"actual_type":typeof(actual),"expected_type_name":type_string(typeof(expected)),"actual_type_name":type_string(typeof(actual)),"raw_equal":expected==actual,"same":Profile.same(expected,actual)}
static func inspect(expected: Variant,actual: Variant,inventory: Variant) -> Dictionary:
	var out:={"expected_array_type":typeof(expected),"actual_array_type":typeof(actual),"raw_array_equal":expected==actual,"profile_same_full_pins":Profile.same(expected,actual),"strict_semantic_match":matches(expected,actual,inventory),"expected_shape_valid":pins_shape(expected),"actual_shape_valid":pins_shape(actual),"inventory":field(1,inventory),"inventory_numeric_integral_one":grid_number(inventory) and float(inventory)==1.0,"named_pin_rows":[]}
	if not expected is Array or not actual is Array:return out
	out.expected_count=expected.size();out.actual_count=actual.size()
	var representation_only: bool=out.expected_shape_valid and out.actual_shape_valid and out.profile_same_full_pins
	var numeric_transition:=false
	for i in maxi(expected.size(),actual.size()):
		var a: Dictionary=expected[i] if i<expected.size() and expected[i] is Dictionary else {}
		var b: Dictionary=actual[i] if i<actual.size() and actual[i] is Dictionary else {}
		var row:={"index":i,"expected_keys":a.keys(),"actual_keys":b.keys()}
		for key in ["id","name","node","role","connector"]:
			row[key]=field(a.get(key),b.get(key))
			if typeof(a.get(key))!=TYPE_STRING or typeof(b.get(key))!=TYPE_STRING or a.get(key)!=b.get(key):representation_only=false
		row.position={}
		var ap: Dictionary=a.get("position",{}) if a.get("position",{}) is Dictionary else {}
		var bp: Dictionary=b.get("position",{}) if b.get("position",{}) is Dictionary else {}
		for axis in ["x","y"]:
			row.position[axis]=field(ap.get(axis),bp.get(axis))
			row.position[axis].expected_grid_number=grid_number(ap.get(axis));row.position[axis].actual_grid_number=grid_number(bp.get(axis))
			if not grid_number(ap.get(axis)) or not grid_number(bp.get(axis)) or not Profile.same(ap.get(axis),bp.get(axis)):representation_only=false
			if typeof(ap.get(axis))!=typeof(bp.get(axis)):
				if grid_number(ap.get(axis)) and grid_number(bp.get(axis)):numeric_transition=true
				else:representation_only=false
		out.named_pin_rows.append(row)
	out.numeric_grid_type_transition_observed=numeric_transition
	out.numeric_grid_type_transition_only=representation_only and numeric_transition
	return out
