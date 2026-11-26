extends RefCounted
## Versioned product options. Clients and the inventory authority use the same quote.

const Materials = preload("res://scripts/campus/items/material_segments.gd")
const VERSION := 2
const DEVICE_VERSION := 3
const DESIGN_VERSION := 3
const BACKLIGHT_NAMES := ["Ice white","Cyan","Blue","Violet","Pink","Red","Amber","Green"]
const BACKLIGHT_COLORS := ["d3f3ff","36ddf5","507bff","a774ff","ff73be","ff584e","ffc458","5ae99f"]
const BACKLIGHT_PRICE := 12
const CAMERA_SIZES := [Vector2i(480,360),Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080)]
const CAMERA_JPEG := [.40,.61,.78,.92]
const CAMERA_QUALITY := {"label":"Camera quality","labels":["480 × 360 · Basic","800 × 600 · Standard","1280 × 720 · HD","1920 × 1080 · Full HD"],"values":[0,1,2,3],"prices":[0,32,80,150]}
const AUDIO_QUALITY := {"label":"Audio quality","labels":["Muffled","Basic","Clear","Full range"],"values":[0,1,2,3],"prices":[0,25,65,125]}
const PERFORMANCE := {"label":"Performance","labels":["Very slow","Low","Standard","Fast","Unlimited"],"values":[0,1,2,3,4],"prices":[0,45,120,230,400]}
const PHONE := "smartphone"
const LAPTOP := "portable_laptop"
const USB := "usb"
const NOTEBOOK := "notebook"
const BACKPACK := "backpack"
const CALCULATOR := "calculator"
const KIT := "kit"
const POWER_BANK := "power_bank"
const Keypad = preload("res://scripts/campus/items/calculator_layout.gd")
const Decoration = preload("res://scripts/campus/items/decoration_document.gd")
const CASE_OPTIONS := {"label":"Case","labels":["Slate","Deep blue","Jade","Coral"],"values":["667b84","25457a","27745e","b95755"],"prices":[0,18,18,18]}
const TRIM_OPTIONS := {"label":"Trim","labels":["Silver","Copper","Black"],"values":["b7c2ca","b6764b","222831"],"prices":[0,12,12]}
const FINISH_OPTIONS := {"label":"Finish","labels":["Satin","Matte","Brushed metal"],"values":[Vector2(.45,0),Vector2(.78,0),Vector2(.32,.65)],"prices":[0,0,35]}
const DEFINITIONS := {
	POWER_BANK: {
		"hardware": {
			"capacity":{"label":"Battery capacity","labels":["10 Wh","20 Wh","32 Wh"],"values":[10.0,20.0,32.0],"prices":[0,28,59]},
			"input":{"label":"Wall input","labels":["10 W","20 W","45 W"],"values":[10.0,20.0,45.0],"prices":[0,12,28]},
			"output":{"label":"Total output","labels":["12 W","30 W","65 W"],"values":[12.0,30.0,65.0],"prices":[0,20,43]},
			"connector":{"label":"Connectors","labels":["USB-C for phones","USB-C PD for phones and laptops"],"values":["usb_c","usb_pd"],"prices":[0,18]},
			"ports":{"label":"Output ports","labels":["1 port","2 ports"],"values":[1,2],"prices":[0,15]},
			"efficiency":{"label":"Transfer efficiency","labels":["78%","90%"],"values":[.78,.90],"prices":[0,14]},
		},
		"appearance": {"shell":CASE_OPTIONS,"trim":TRIM_OPTIONS,"finish":FINISH_OPTIONS}
	},
	KIT: {
		"hardware": {
			"size":{"label":"Component capacity","labels":["20 spaces","40 spaces","70 spaces","120 spaces"],"values":["compact","standard","extended","large"],"prices":[0,13,33,83]},
			"tray":{"label":"Passive component tray","labels":["Open compartment","Reserve 20%","Reserve 35%"],"values":[0.0,.20,.35],"prices":[0,5,11]},
		},
		"appearance": {
			"shell":CASE_OPTIONS,
			"lid":{"label":"Lid","labels":["Slate","Deep blue","Jade","Coral"],"values":["667b84","25457a","27745e","b95755"],"prices":[0,3,3,3]},
			"interior":{"label":"Interior","labels":["Charcoal","Sand","Mint"],"values":["343e47","c0a783","83ad99"],"prices":[0,3,3]},
			"trim":TRIM_OPTIONS,
			"handle":{"label":"Handle","labels":["Compact grip","Reinforced grip"],"values":[false,true],"prices":[0,6]},
			"finish":FINISH_OPTIONS,
		},
	},
	CALCULATOR: {
		"hardware": {
			"model":{"label":"Functions","labels":["Basic","Scientific","Financial"],"values":Keypad.MODELS,"prices":[0,14,22]},
			"size":{"label":"Body size","labels":["Compact","Standard","Wide"],"values":[Vector3(.122,.027,.182),Vector3(.151,.033,.219),Vector3(.181,.039,.235)],"prices":[0,2,6]},
			"screen":{"label":"Display size","labels":["Standard","Large"],"values":[1.0,1.28],"prices":[0,6]},
			"columns":{"label":"Key columns","labels":["4","5","6"],"values":[4,5,6],"prices":[0,0,0]},
		},
		"appearance": {
			"shell":CASE_OPTIONS,
			"keys":{"label":"Key color","labels":["Slate","Ivory","Jade"],"values":["60747e","d1c6a9","35765f"],"prices":[0,3,3]},
			"key_style":{"label":"Key shape","labels":["Soft square","Round"],"values":[false,true],"prices":[0,3]},
			"screen_color":{"label":"Display","labels":["Green LCD","Blue LCD","Amber LCD"],"values":["b0c398","93c9da","e4bd75"],"prices":[0,3,3]},
			"finish":FINISH_OPTIONS,
		},
	},
	BACKPACK: {
		"hardware": {
			"size":{"label":"Capacity","labels":["12 slots","24 slots","40 slots","60 slots"],"values":["backpack_small","backpack_medium","backpack_large","backpack_giant"],"prices":[0,18,44,77]},
			"pockets":{"label":"Component pockets","labels":["None","One 2-slot pocket","Two 2-slot pockets"],"values":[0,2,4],"prices":[0,7,13]},
			"straps":{"label":"Shoulder straps","labels":["Standard","Padded"],"values":[1.0,.7],"prices":[0,9]},
		},
		"appearance": {
			"shell":{"label":"Fabric","labels":["Forest","Midnight blue","Rust","Violet"],"values":["607b58","3b7283","8e5544","645780"],"prices":[0,3,3,3]},
			"trim":TRIM_OPTIONS,
			"handle":{"label":"Top handle","labels":["With handle","Without handle"],"values":[true,false],"prices":[0,0]},
			"finish":{"label":"Material","labels":["Canvas","Ripstop"],"values":[Vector2(.90,0),Vector2(.57,0)],"prices":[0,8]},
		},
	},
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

const DISPLAY := {"label":"Display quality","labels":["Analog · Grain and scanlines","Low · Soft and grainy","Standard","Sharp","Full resolution"],"values":[.38,.54,.70,.85,1.0],"prices":[0,35,95,180,300]}
const SPEED := {"label":"Screen speed","labels":["12 FPS","20 FPS","30 FPS","45 FPS","60 FPS"],"values":[12,20,30,45,60],"prices":[0,40,100,190,320]}
const CHARGING := {"label":"Charge speed","labels":["0.50%/s","0.83%/s","1.25%/s","1.82%/s","2.50%/s"],"values":[200.0,120.0,80.0,55.0,40.0],"prices":[0,35,75,145,235]}
const HARDWARE := {
	LAPTOP:{
		"display":DISPLAY,"speed":SPEED,
		"battery":{"label":"Battery drain","labels":["0.222%/s","0.111%/s","0.067%/s","0.043%/s","0.028%/s","0.019%/s"],"values":[450.0,900.0,1500.0,2300.0,3600.0,5400.0],"prices":[0,80,160,280,440,650]},
		"charging":CHARGING
	},
	PHONE:{
		"storage":{"label":"Photo storage","labels":["4 MB","8 MB","16 MB","32 MB","64 MB","128 MB"],"values":[4,8,16,32,64,128],"prices":[0,25,65,115,185,280]},
		"display":DISPLAY,"speed":SPEED,
		"battery":{"label":"Battery drain","labels":["0.167%/s","0.083%/s","0.051%/s","0.034%/s","0.023%/s","0.014%/s"],"values":[600.0,1200.0,1950.0,2900.0,4350.0,7200.0],"prices":[0,60,110,200,310,445]},
		"charging":CHARGING
	},
	USB:{"storage":DEFINITIONS[USB].hardware.storage},
	BACKPACK:{
		"size":DEFINITIONS[BACKPACK].hardware.size,
		"reduction":{"label":"Contents weight reduction","labels":["0%","15%","30%","45%","60%"],"values":[0.0,.15,.30,.45,.60],"prices":[0,14,32,58,95]}
	},
	POWER_BANK:{
		"capacity":{"label":"Battery capacity","labels":["100%","250%","500%","750%","1000%"],"values":[100.0,250.0,500.0,750.0,1000.0],"prices":[0,25,55,95,145]},
		"charging":{"label":"Charge speed","labels":["0.50%/s","1%/s","2%/s","4%/s","8%/s"],"values":[.5,1.0,2.0,4.0,8.0],"prices":[0,14,33,58,96]},
		"connector":{"label":"Connector","labels":["Phones","Laptops","Phones and laptops"],"values":["usb_c","laptop","usb_pd"],"prices":[0,10,18]},
		"ports":{"label":"Output ports","labels":["1 port","2 ports","3 ports","4 ports"],"values":[1,2,3,4],"prices":[0,15,29,45]},
		"efficiency":{"label":"Transfer efficiency","labels":["20%","40%","60%","80%","100%"],"values":[.2,.4,.6,.8,1.0],"prices":[0,8,19,36,59]}
	},
	KIT:{"capacity":{"label":"Component capacity","labels":["5","10","20","40","70","120","250","500","750","1000"],"values":[5,10,20,40,70,120,250,500,750,1000],"prices":[0,3,8,18,32,55,95,160,225,300]}},
	CALCULATOR:{
		"equation":{"label":"Equation entry","labels":["Off","On"],"values":[false,true],"prices":[0,8]},
		"algebra":{"label":"Symbolic algebra","labels":["Off","On"],"values":[false,true],"prices":[0,19]},
		"complex":{"label":"Complex numbers","labels":["Off","On"],"values":[false,true],"prices":[0,12]},
		"graph":{"label":"Graphing","labels":["Off","2D and polar","2D, polar and 3D"],"values":[0,1,2],"prices":[0,24,42]}
	}
}

static func latest_version(kind: String) -> int:
	if kind==CALCULATOR:return DESIGN_VERSION
	return DEVICE_VERSION if kind in [PHONE,LAPTOP] else VERSION

static func definitions(kind: String, version := 0) -> Dictionary:
	if not DEFINITIONS.has(kind):return {}
	if version==0:version=latest_version(kind)
	if version==1:return DEFINITIONS[kind]
	if version not in [VERSION,latest_version(kind)]:return {}
	var hardware: Dictionary=HARDWARE.get(kind,DEFINITIONS[kind].hardware)
	if version==DEVICE_VERSION and kind in [PHONE,LAPTOP]:
		hardware=hardware.duplicate()
		if kind==PHONE:hardware.camera_quality=CAMERA_QUALITY
		hardware.audio_quality=AUDIO_QUALITY
		hardware.performance=PERFORMANCE
	return {"hardware":hardware,"appearance":DEFINITIONS[kind].appearance}

static func phone_or_laptop_fps(kind: String, configuration: Dictionary) -> int:
	return int(value(kind,configuration,"hardware","speed",60))

static func screen_noise(kind: String, configuration: Dictionary) -> float:
	var scale := float(value(kind,configuration,"hardware","display",1.0))
	return .23 if scale<.4 else .09 if scale<.6 else 0.0

const BODY_DEFAULT := {"width":.122,"height":.027,"weight":.10}
const BODY_LIMITS := {"width":Vector2(.122,.21),"height":Vector2(.027,.065),"weight":Vector2(.10,.60)}

static func body_size(configuration: Dictionary) -> Vector3:
	var body: Dictionary=configuration.get("body",BODY_DEFAULT)
	var length:=.182
	if int(configuration.get("version",1))==DESIGN_VERSION:
		var layout: Array=configuration.get("keypad",[])
		length=.062+.020*Keypad.occupied_rows(layout,Keypad.COLUMNS)
	return Vector3(body.width,body.height,length)

static func kit_capacity(configuration: Dictionary, fallback: int) -> int:
	return int(value(KIT,configuration,"hardware","capacity",fallback))

static func defaults(kind: String,version := 0) -> Dictionary:
	if version==0:version=latest_version(kind)
	var definition:=definitions(kind,version)
	if definition.is_empty():return {}
	var result := {"version": version}
	for group in definition:
		var choices := {}
		for property in definition[group]:choices[property] = 0
		result[group] = choices
	if kind==CALCULATOR:
		result.keypad=Keypad.keys("calculator_basic")
		if version==VERSION:result.keypad=Keypad.REQUIRED.duplicate()
		elif version==DESIGN_VERSION:result.keypad=Keypad.default_slots()
		if version>=VERSION:result.body=BODY_DEFAULT.duplicate()
	return result

static func quote(kind: String,base_price: int,selection: Variant,owned := false) -> Dictionary:
	if not selection is Dictionary:return {}
	var version:=_index(selection.get("version"),latest_version(kind)+1)
	if version<1:return {}
	var definition:=definitions(kind,version)
	var custom_body:=version>=VERSION and kind==CALCULATOR
	var full_design:=version==DESIGN_VERSION and kind==CALCULATOR
	if definition.is_empty() or selection.size()!=definition.size()+1+int(kind==CALCULATOR)+int(custom_body)+int(selection.has("decoration"))+int(kind==LAPTOP and selection.has("backlight"))+int(selection.has("materials")):return {}
	var hardware_cost:=0
	var appearance_cost:=0
	var keypad_cost:=0
	var normalized:={"version":version}
	for group in definition:
		var choices: Variant = selection.get(group)
		if not choices is Dictionary or choices.size() != definition[group].size():return {}
		var indices := {}
		for property in definition[group]:
			var entry: Dictionary = definition[group][property]
			var index := _index(choices.get(property), entry.values.size())
			if index<0:return {}
			indices[property]=index
			if group=="hardware":hardware_cost+=int(entry.prices[index])
			else:appearance_cost+=int(entry.prices[index])
		normalized[group]=indices
	if kind==CALCULATOR:
		if custom_body:
			if full_design:
				keypad_cost=Keypad.design_price(selection.get("keypad"),normalized.hardware)
				if keypad_cost<0:return {}
			elif not Keypad.valid_custom(selection.get("keypad")):return {}
			var picked: Dictionary=normalized.hardware
			if ((picked.complex>0 or (picked.algebra>0 and not owned)) and picked.equation==0) or (picked.graph>0 and picked.algebra==0):return {}
			var body: Variant=selection.get("body")
			if not body is Dictionary or body.size()!=BODY_LIMITS.size():return {}
			var dimensions:={}
			for field in BODY_LIMITS:
				var amount: Variant=body.get(field)
				var limits: Vector2=BODY_LIMITS[field]
				if not (amount is int or amount is float) or not is_finite(amount) or float(amount)<limits.x-.00001 or float(amount)>limits.y+.00001:return {}
				dimensions[field]=snappedf(float(amount),.001)
			normalized.body=dimensions
			if not full_design:
				var optional_count: int=selection.keypad.filter(func(key):return key not in Keypad.REQUIRED).size()
				keypad_cost=2*optional_count
		else:
			var model: String=value(CALCULATOR,normalized,"hardware","model","")
			if not Keypad.valid(model,selection.get("keypad")):return {}
		normalized.keypad=Keypad.with_required(selection.keypad) if custom_body and not full_design else selection.keypad.duplicate()
	if kind==LAPTOP and selection.has("backlight"):
		var raw: Variant=selection.backlight
		if not raw is Array or raw.size()>BACKLIGHT_COLORS.size():return {}
		var colors: Array[int]=[]
		for value in raw:
			var color:=_index(value,BACKLIGHT_COLORS.size())
			if color<0 or color in colors:return {}
			colors.append(color)
		if not colors.is_empty():
			normalized.backlight=colors
			appearance_cost+=BACKLIGHT_PRICE*colors.size()
	if selection.has("materials"):
		var parts: Variant=Materials.clean(kind,selection.materials)
		if parts==null:return {}
		if not parts.is_empty():
			normalized.materials=parts
			appearance_cost+=4*parts.size()
	if selection.has("decoration"):
		var design: Variant=Decoration.clean(selection.decoration)
		if design==null:return {}
		if not design.is_empty():
			normalized.decoration=design
			appearance_cost+=3*design.size()
	return {"price":base_price+hardware_cost+keypad_cost+appearance_cost,"configuration":normalized,
		"hardware_cost":hardware_cost,"keypad_cost":keypad_cost,"appearance_cost":appearance_cost}

static func value(kind: String, configuration: Dictionary, group: String, key: String, fallback: Variant) -> Variant:
	var version:=int(configuration.get("version",1))
	if version>=VERSION and group=="hardware":
		if kind==CALCULATOR:
			if key=="model":return "calculator_basic"
			if key=="size":return body_size(configuration)
			if key=="columns":return 6
		if kind==KIT and key=="size":
			var capacity:=kit_capacity(configuration,5)
			return "compact" if capacity<=20 else "standard" if capacity<=40 else "extended" if capacity<=70 else "large"
	var options: Dictionary=definitions(kind,version).get(group,{}).get(key,{})
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
	var configuration: Dictionary=item.get("configuration",{})
	var appearance: Dictionary=configuration.get("appearance",{}).duplicate()
	if configuration.has("decoration"):appearance.decoration=configuration.decoration
	if configuration.has("materials"):appearance.materials=configuration.materials
	return appearance

static func same_phone_configuration(left: Dictionary, right: Dictionary) -> bool:
	return same_configuration(PHONE,left,right)

static func same_configuration(kind: String, left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():return left.is_empty() and right.is_empty()
	var canonical := quote(kind,0,left,true)
	return not canonical.is_empty() and canonical==quote(kind,0,right,true)

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
