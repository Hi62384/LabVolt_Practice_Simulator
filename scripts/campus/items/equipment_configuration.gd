extends RefCounted
## Versioned product options. Clients and the inventory authority use the same quote.

const VERSION := 1
const PHONE := "smartphone"
const DEFINITIONS := {
	PHONE: {
		"hardware": {
			"storage": {"label": "Photo storage", "labels": ["4 MB", "16 MB", "64 MB"], "values": [4, 16, 64], "prices": [0, 90, 250]},
			"processor": {"label": "App speed", "labels": ["Standard", "Fast", "Instant"], "values": [600, 250, 0], "prices": [0, 105, 280]},
			"display": {"label": "Display quality", "labels": ["Standard", "Sharp", "Full resolution"], "values": [.65, .82, 1.0], "prices": [0, 75, 190]},
			"battery": {"label": "Battery life", "labels": ["20 min", "32.5 min", "48 min"], "values": [1200.0, 1950.0, 2900.0], "prices": [0, 85, 225]},
			"charging": {"label": "Full charge", "labels": ["120 sec", "82 sec", "55 sec"], "values": [120.0, 82.0, 55.0], "prices": [0, 45, 110]},
		},
		"appearance": {
			"shell": {"label": "Case", "labels": ["Graphite", "Deep blue", "Jade", "Coral", "Lilac"], "values": ["243943", "25457a", "27745e", "b95755", "8074a0"], "prices": [0, 18, 18, 18, 18]},
			"trim": {"label": "Buttons and trim", "labels": ["Steel", "Silver", "Copper", "Black"], "values": ["7597a3", "b7c2ca", "b6764b", "222831"], "prices": [0, 12, 12, 12]},
			"finish": {"label": "Surface finish", "labels": ["Satin", "Matte", "Brushed metal"], "values": [Vector2(.45, .0), Vector2(.78, .0), Vector2(.32, .65)], "prices": [0, 0, 35]},
		},
	},
}

static func defaults(kind: String) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(kind, {})
	if definition.is_empty():return {}
	var result := {"version": VERSION}
	for group in definition:
		var choices := {}
		for property in definition[group]:choices[property] = 0
		result[group] = choices
	return result

static func quote(kind: String, base_price: int, selection: Variant) -> Dictionary:
	var definition: Dictionary = DEFINITIONS.get(kind, {})
	if definition.is_empty() or not selection is Dictionary or selection.size() != definition.size() + 1 or selection.get("version") != VERSION:
		return {}
	var price := base_price
	var normalized := {"version":VERSION}
	for group in definition:
		var choices: Variant = selection.get(group)
		if not choices is Dictionary or choices.size() != definition[group].size():return {}
		var indices := {}
		for property in definition[group]:
			var entry: Dictionary = definition[group][property]
			var index := _index(choices.get(property), entry.values.size())
			if index<0:return {}
			indices[property]=index
			price += int(entry.prices[index])
		normalized[group]=indices
	return {"price": price, "configuration": normalized}

static func value(kind: String, configuration: Dictionary, group: String, key: String, fallback: Variant) -> Variant:
	var options: Dictionary = DEFINITIONS.get(kind, {}).get(group, {}).get(key, {})
	if options.is_empty():return fallback
	var index := _index(configuration.get(group, {}).get(key),options.values.size())
	if index<0:return fallback
	return options.values[index]

static func _index(value: Variant, size: int) -> int:
	if not (value is int or value is float) or not is_finite(value) or value<0 or value>=size or value!=floor(value):return -1
	return int(value)

static func phone_value(item: Dictionary, key: String, fallback: Variant) -> Variant:
	return value(PHONE, item.get("configuration", {}), "hardware", key, fallback)

static func phone_appearance(item: Dictionary) -> Dictionary:
	return item.get("configuration", {}).get("appearance", {})

static func same_phone_configuration(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():return left.is_empty() and right.is_empty()
	var canonical := quote(PHONE,0,left)
	return not canonical.is_empty() and canonical==quote(PHONE,0,right)
