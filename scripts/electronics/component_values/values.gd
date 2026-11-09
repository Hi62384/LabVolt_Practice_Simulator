extends RefCounted
## Pure purchase preparation. Authority, receipts, balances and persistence stay in ledger.
const PREFIX := "cv1:"
const MAX_STACK := 100000
const MAX_COST := 1000000000
const SCALE := {"":0,"k":3,"M":6,"m":-3,"u":-6,"µ":-6,"μ":-6,"n":-9,"p":-12}
# Bounds are representation/solver limits, not a preferred-value catalog.
const PARAMETERS := {
	"vf":["Forward voltage","V",0.0,1e9], "vz":["Reverse knee","V",1e-12,1e9],
	"ron":["On resistance","Ω",1e-12,1e12], "resistance":["Internal / coil resistance","Ω",1e-12,1e12],
	"vth":["Gate threshold","V",0.0,1e9], "pinch":["Pinch-off voltage","V",-1e9,-1e-12],
	"current":["Rated current","A",1e-12,1e9], "i2t":["Fuse energy integral","A²s",1e-12,1e12],
	"pickup":["Pickup current","A",1e-12,1e9], "release":["Release current","A",0.0,1e9],
	"delay":["Switching delay","s",0.0,1e9], "coil_inductance":["Coil inductance","H",1e-12,1e9],
	"target":["Regulated voltage","V",0.0,1e9], "dropout":["Dropout voltage","V",0.0,1e9],
	"limit":["Current limit","A",1e-12,1e9], "iq":["Quiescent current","A",0.0,1e9],
	"vmin":["Minimum supply","V",0.0,1e9], "vmax":["Maximum supply","V",1e-12,1e9],
	"driver":["Driver resistance","Ω",0.001,1e12],
	"power_rating_w":["Power rating","W",1e-12,100.0],
	"resistance_tolerance":["Resistance tolerance (fraction)","",1e-12,0.2]
}

static func fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func _decimal(number: String, shift: int = 0) -> String:
	var lower := number.to_lower()
	var exponent := shift
	if "e" in lower:
		var pieces := lower.split("e")
		exponent += int(pieces[1]); lower = pieces[0]
	var negative := lower.begins_with("-")
	lower = lower.trim_prefix("-").trim_prefix("+")
	if "." in lower:
		exponent -= lower.length()-lower.find(".")-1
		lower = lower.replace(".","")
	while lower.begins_with("0") and lower.length()>1:lower=lower.substr(1)
	if lower=="0":return "0"
	while lower.ends_with("0"):
		lower=lower.left(-1);exponent+=1
	return ("-" if negative else "")+lower+("e"+str(exponent) if exponent!=0 else "")

static func _canonical(value: float) -> String:
	var exact := _decimal(JSON.stringify(value,"",true,true))
	if value==0.0:return "0"
	var pieces := exact.trim_prefix("-").split("e")
	var digits := pieces[0]
	var exponent := int(pieces[1]) if pieces.size()==2 else 0
	# Choose the shortest decimal that round-trips to this stored double. This
	# avoids exposing binary tails (e.g. 0.10000000000000001) in fields and IDs.
	for length in range(1,digits.length()+1):
		var head := int(digits.left(length))
		if length<digits.length() and int(digits.substr(length,1))>=5:head+=1
		var candidate := ("-" if value<0 else "")+str(head)+"e"+str(exponent+digits.length()-length)
		if candidate.to_float()==value:return _decimal(candidate)
	return exact

static func _plain(canonical: String, shift: int = 0) -> String:
	var pieces := _decimal(canonical,shift).split("e")
	var negative := pieces[0].begins_with("-")
	var digits := pieces[0].trim_prefix("-")
	var exponent := int(pieces[1]) if pieces.size()==2 else 0
	var point := digits.length()+exponent
	var result := ""
	if point<=0:result="0."+"0".repeat(-point)+digits
	elif point>=digits.length():result=digits+"0".repeat(point-digits.length())
	else:result=digits.left(point)+"."+digits.substr(point)
	return ("-" if negative else "")+result

static func parse(raw: Variant, unit: String = "") -> Dictionary:
	if raw is int or raw is float:
		var numeric := float(raw)
		if not is_finite(numeric):return fail("Value must be finite")
		if absf(numeric)>1e12 or (numeric!=0.0 and absf(numeric)<1e-12):return fail("Value must be zero or between 1e-12 and 1e12 in base units")
		return {"ok":true,"value":numeric,"canonical":_canonical(numeric)}
	if not raw is String:return fail("Enter a number with an optional SI prefix")
	var input: String = raw.strip_edges()
	if input.is_empty() or input.length()>96:return fail("Value is empty or too long")
	var expression := RegEx.new()
	expression.compile("^([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?)\\s*([kMmuµμnp]?)(.*)$")
	var found := expression.search(input)
	if found==null:return fail("Invalid number or scientific notation")
	var suffix := found.get_string(3).strip_edges()
	if not suffix.is_empty() and (unit.is_empty() or suffix!=unit):
		if not (unit=="Ω" and suffix in ["ohm","ohms","Ω"]):return fail("Expected unit "+unit)
	var canonical := _decimal(found.get_string(1),int(SCALE[found.get_string(2)]))
	var magnitude_parts := canonical.trim_prefix("-").split("e")
	if magnitude_parts[0]!="0":
		var magnitude := magnitude_parts[0].length()-1+(int(magnitude_parts[1]) if magnitude_parts.size()==2 else 0)
		if magnitude>12 or magnitude< -12:return fail("Value must be between 1e-12 and 1e12 in base units")
	var value := canonical.to_float()
	if not is_finite(value) or absf(value)>1e12 or (value==0.0 and canonical!="0") or (value!=0.0 and absf(value)<1e-12):return fail("Value must be zero or between 1e-12 and 1e12 in base units")
	# Canonicalize through the stored float once, so distinct spellings that round
	# to the same simulation number cannot generate different identities.
	canonical=_canonical(value)
	return {"ok":true,"value":value,"canonical":canonical}

static func format_value(value: float, unit: String = "") -> String:
	var result := parse(value,unit)
	if not result.ok:return ""
	var exponent := 0
	var prefix := ""
	if value!=0.0 and not unit.is_empty():
		for pair in [["M",6],["k",3],["",0],["m",-3],["µ",-6],["n",-9],["p",-12]]:
			if absf(value)>=pow(10.0,int(pair[1])):prefix=pair[0];exponent=int(pair[1]);break
	return _plain(str(result.canonical),-exponent)+(" "+prefix+unit if not unit.is_empty() else "")

static func fields(entry: Dictionary) -> Dictionary:
	var out := {}
	var kind := str(entry.get("kind",""))
	if kind=="portable_source":
		var source_label := "Peak voltage" if entry.has("frequency") else "DC voltage"
		out.value={"label":source_label,"unit":"V","minimum":0.0,"maximum":30.0,"default":entry.value}
		if entry.has("frequency"):
			out.frequency={"label":"Frequency","unit":"Hz","minimum":.1,"maximum":200.0,"default":entry.frequency}
	if kind in ["R","C","L","V","pot"]:
		var unit := str(entry.get("unit",""))
		var minimum := 0.001 if kind=="R" else (0.01 if kind=="pot" else 1e-12)
		if kind=="V":minimum=-1e9
		out.value={"label":"Nominal value","unit":unit,"minimum":minimum,"maximum":1e9,"default":entry.get("value",0.0)}
	for key in PARAMETERS:
		# Only parameters consumed by the existing worker/base model are editable.
		if not entry.has(key):continue
		if kind!="worker_model" and not (kind in ["D","LED"] and key in ["vf","ron"]) and not (kind=="V" and key=="resistance") and not (kind=="R" and key in ["power_rating_w","resistance_tolerance"]):continue
		var spec: Array=PARAMETERS[key]
		out[key]={"label":spec[0],"unit":spec[1],"minimum":spec[2],"maximum":spec[3],"default":entry[key]}
	return out

static func _price(base: Dictionary, entry: Dictionary) -> int:
	# Retain the established physical-resistor price formula; all other model
	# parameter variants retain the host catalog's type/rarity price.
	if entry.get("physical_resistor",false):return 2+int(float(entry.power_rating_w)*2)+(1 if float(entry.resistance_tolerance)<0.02 else 0)
	return int(base.get("price",0))

static func _family(a: Dictionary, b: Dictionary) -> bool:
	var a_fields := fields(a)
	if a_fields.keys()!=fields(b).keys():return false
	var keys := a.keys()
	for key in b:
		if not key in keys:keys.append(key)
	for key in keys:
		if key in ["name","rating","price"] or a_fields.has(key):continue
		if key=="value" and a.get("kind","") in ["D","LED"]:continue
		if a.get(key)!=b.get(key):return false
	return true

static func configure(base_id: String, settings: Variant, catalog: Dictionary) -> Dictionary:
	if not catalog.has(base_id) or base_id.begins_with(PREFIX):return fail("Unknown base component")
	if not settings is Dictionary or settings.size()>24:return fail("Invalid component settings")
	var base: Dictionary=catalog[base_id]
	var specs := fields(base)
	var entry := base.duplicate(true)
	var normalized := {}
	for key in settings:
		if not key is String or not specs.has(key):return fail("Unsupported component field: "+str(key))
		var spec: Dictionary=specs[key]
		var parsed := parse(settings[key],str(spec.unit))
		if not parsed.ok:return fail(str(spec.label)+": "+str(parsed.error))
		if parsed.value<float(spec.minimum) or parsed.value>float(spec.maximum):return fail(str(spec.label)+" is outside supported model bounds")
		entry[key]=parsed.value
		if float(parsed.value)!=float(spec.default):normalized[key]=parsed.canonical
	if entry.get("kind","") in ["D","LED"]:entry.value=entry.get("vf",entry.get("value",0.0))
	if entry.has("vmin") and entry.has("vmax") and float(entry.vmin)>float(entry.vmax):return fail("Minimum supply exceeds maximum supply")
	if entry.has("release") and entry.has("pickup") and float(entry.release)>float(entry.pickup):return fail("Relay release exceeds pickup current")
	var id := base_id
	if not normalized.is_empty():
		var keys := normalized.keys();keys.sort()
		var tokens: PackedStringArray=[]
		for key in keys:tokens.append(str(key)+"="+str(normalized[key]))
		id=PREFIX+base_id+":"+";".join(tokens)
		# Reuse existing inventory identity for an exact supported catalog match.
		var candidates := catalog.keys();candidates.sort()
		for candidate in candidates:
			if str(candidate).begins_with(PREFIX):continue
			var other: Dictionary=catalog[candidate]
			if not _family(base,other):continue
			var comparable := base.duplicate(true)
			for key in specs:comparable[key]=entry[key]
			var same := true
			# Preserve model/firmware/pin distinctions: only presentation and supported
			# numeric fields may differ when reusing a legacy ID.
			for key in comparable:
				if key in ["name","rating","price"]:continue
				if comparable[key]!=other.get(key):same=false;break
			if same:id=str(candidate);entry=other.duplicate(true);break
		if id.begins_with(PREFIX):
			# Every variant in a structural model family uses one deterministic base.
			# Thus 333 Ω requested from r100 or r220 has one identity.
			for candidate in candidates:
				if str(candidate).begins_with(PREFIX) or not _family(base,catalog[candidate]):continue
				base_id=str(candidate);base=catalog[candidate];break
			specs=fields(base);normalized={};tokens=[]
			keys=specs.keys();keys.sort()
			for key in keys:
				if float(entry[key])==float(specs[key].default):continue
				var parsed := parse(entry[key],str(specs[key].unit))
				normalized[key]=parsed.canonical
				tokens.append(str(key)+"="+str(parsed.canonical))
			id=PREFIX+base_id+":"+";".join(tokens)
	entry.price=_price(base,entry)
	if id.begins_with(PREFIX):
		var descriptions: PackedStringArray=[]
		for key in normalized:descriptions.append(str(specs[key].label)+" "+format_value(float(entry[key]),str(specs[key].unit)))
		entry.name=str(base.get("name",base_id))+" · "+", ".join(descriptions)
	return {"ok":true,"id":id,"base_id":base_id,"settings":normalized,"entry":entry}

static func resolve(id: String, catalog: Dictionary) -> Dictionary:
	if not id.begins_with(PREFIX):return configure(id,{},catalog)
	if id.length()>2048:return fail("Component identity too long")
	var split := id.substr(PREFIX.length()).split(":")
	if split.size()!=2:return fail("Invalid component identity")
	var settings := {}
	for token in split[1].split(";"):
		var pair := token.split("=")
		if pair.size()!=2 or settings.has(pair[0]):return fail("Invalid component identity settings")
		settings[pair[0]]=pair[1]
	var result := configure(split[0],settings,catalog)
	if result.ok and result.id!=id:return fail("Noncanonical component identity")
	return result

static func augment(catalog: Dictionary, ids: Array) -> Dictionary:
	var result := catalog.duplicate(true)
	for id in ids:
		if not id is String or not id.begins_with(PREFIX):continue
		var resolved := resolve(id,catalog)
		if resolved.ok:result[id]=resolved.entry
	return result

static func quantity(raw: Variant) -> Dictionary:
	if raw is String:
		if raw.is_empty() or raw.length()>6:return fail("Quantity must be a positive integer through 100000")
		for character in raw:
			if character<"0" or character>"9":return fail("Quantity must contain only digits")
		raw=raw.to_int()
	if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw)<1 or float(raw)>MAX_STACK or float(raw)!=floor(float(raw)):return fail("Quantity must be a positive integer through 100000")
	return {"ok":true,"quantity":int(raw)}

static func intent(base_id: String, settings: Variant, amount: Variant, catalog: Dictionary, owned: int = 0, free_space: int = -1) -> Dictionary:
	var q := quantity(amount)
	if not q.ok:return q
	var configured := configure(base_id,settings,catalog)
	if not configured.ok:return configured
	if owned<0 or owned>MAX_STACK or q.quantity>MAX_STACK-owned:return fail("Purchase exceeds inventory stack limit")
	var price: Variant=configured.entry.get("price",-1)
	var space: Variant=configured.entry.get("space",-1)
	if not (price is int or price is float) or not is_finite(float(price)) or price<0 or price>MAX_COST or float(price)!=floor(float(price)):return fail("Invalid authoritative price")
	if not (space is int or space is float) or not is_finite(float(space)) or space<0 or space>MAX_STACK or float(space)!=floor(float(space)):return fail("Invalid authoritative space")
	if price>0 and q.quantity>MAX_COST/int(price):return fail("Purchase exceeds transaction cost limit")
	var used := int(space)*int(q.quantity)
	if free_space < -1 or (free_space>=0 and used>free_space):return fail("Purchase exceeds available capacity")
	configured.quantity=q.quantity;configured.unit_price=int(price)
	configured.total_price=int(price)*int(q.quantity);configured.space_required=used
	return configured
