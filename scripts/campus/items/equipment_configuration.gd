extends RefCounted
## Versioned product options. Clients and the inventory authority use the same quote.

const VERSION := 1
const PHONE := "smartphone"
const LAPTOP := "portable_laptop"
const USB := "usb"
const NOTEBOOK := "notebook"
const CASE_OPTIONS := {"label":"Case","labels":["Slate","Deep blue","Jade","Coral"],"values":["667b84","25457a","27745e","b95755"],"prices":[0,18,18,18]}
const TRIM_OPTIONS := {"label":"Trim","labels":["Silver","Copper","Black"],"values":["b7c2ca","b6764b","222831"],"prices":[0,12,12]}
const FINISH_OPTIONS := {"label":"Finish","labels":["Satin","Matte","Brushed metal"],"values":[Vector2(.45,0),Vector2(.78,0),Vector2(.32,.65)],"prices":[0,0,35]}
const DEFINITIONS := {
	NOTEBOOK: {
		"hardware": {
			"pages":{"label":"Pages","labels":["12","32","80"],"values":[12,32,80],"prices":[0,8,18]},
			"ruling":{"label":"Paper ruling","labels":["Lined","Grid","Blank","Dotted"],"values":["lined","grid","blank","dotted"],"prices":[0,3,0,3]},
			"size":{"label":"Paper size","labels":["Letter","Compact"],"values":[Vector2(780,1100),Vector2(590,830)],"prices":[0,0]},
			"orientation":{"label":"Orientation","labels":["Portrait","Landscape"],"values":[false,true],"prices":[0,0]},
			"spacing":{"label":"Ruling spacing","labels":["Standard","Wide"],"values":[24,32],"prices":[0,0]},
			"paper":{"label":"Paper shade","labels":["Ivory","White","Cream"],"values":["fcfaf2","fafcfd","fff0cc"],"prices":[0,0,2]},
		},
		"appearance": {
			"cover":{"label":"Binding","labels":["Softcover","Hardcover"],"values":[.004,.014],"prices":[0,9]},
			"shell":CASE_OPTIONS,"trim":TRIM_OPTIONS,"finish":FINISH_OPTIONS,
		},
	},
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
	LAPTOP: {
		"hardware": {
			"processor": {"label":"Boot time","labels":["1.6 sec","0.9 sec","0.35 sec"],"values":[1600,900,350],"prices":[0,240,560]},
			"display": {"label":"Display quality","labels":["Standard","Sharp","Full resolution"],"values":[.58,.78,1.0],"prices":[0,180,460]},
			"battery": {"label":"Battery life","labels":["15 min","25 min","38 min"],"values":[900.0,1500.0,2300.0],"prices":[0,220,520]},
			"charging": {"label":"Full charge","labels":["120 sec","82 sec","55 sec"],"values":[120.0,82.0,55.0],"prices":[0,95,220]},
		},
		"appearance": {"shell":CASE_OPTIONS,"trim":TRIM_OPTIONS,"finish":FINISH_OPTIONS},
	},
	USB: {
		"hardware": {
			"storage": {"label":"Storage","labels":["8 MB","32 MB","64 MB","150 MB"],"values":[8,32,64,150],"prices":[0,20,45,100]},
			"read": {"label":"Read speed","labels":["4 MB/s","12 MB/s","24 MB/s"],"values":[4,12,24],"prices":[0,10,24]},
			"write": {"label":"Write speed","labels":["4 MB/s","12 MB/s","24 MB/s"],"values":[4,12,24],"prices":[0,12,28]},
		},
		"appearance": {
			"shell": {"label":"Case","labels":["Teal","Deep blue","Jade","Coral"],"values":["287e84","25457a","27745e","b95755"],"prices":[0,6,6,6]},
			"trim": {"label":"Detail","labels":["Mint","Silver","Copper","Black"],"values":["b5eadb","b7c2ca","b6764b","222831"],"prices":[0,4,4,4]},
			"finish": {"label":"Finish","labels":["Satin","Matte","Brushed metal"],"values":[Vector2(.45,0),Vector2(.78,0),Vector2(.32,.65)],"prices":[0,0,9]},
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
	return same_configuration(PHONE,left,right)

static func same_configuration(kind: String, left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():return left.is_empty() and right.is_empty()
	var canonical := quote(kind,0,left)
	return not canonical.is_empty() and canonical==quote(kind,0,right)

static func usb_capacity(pending: Variant) -> int:
	var capacity: Variant=pending.get("capacity_mb") if pending is Dictionary else pending
	if not (capacity is int or capacity is float) or not is_finite(capacity) or capacity!=floor(capacity) or capacity not in [8,32,64,150]:return 0
	return int(capacity)

static func valid_usb_pending(pending: Variant) -> bool:
	var capacity:=usb_capacity(pending)
	if capacity==0:return false
	if not pending is Dictionary:return true
	if pending.size()!=2 or quote(USB,0,pending.get("configuration")).is_empty():return false
	return value(USB,pending.configuration,"hardware","storage",0)==capacity
