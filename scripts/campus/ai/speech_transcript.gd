extends RefCounted
## Conservative spoken-form equivalence, never fuzzy similarity. Values, signs,
## units, operators and negations must still match exactly after normalization.
const SMALL:={"zero":0,"oh":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19}
const TENS:={"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90}
const SCALES:={"thousand":1000,"million":1000000,"billion":1000000000}
const SI_PREFIXES:={"Y":"yotta","Z":"zetta","E":"exa","P":"peta","T":"tera","G":"giga","M":"mega","k":"kilo","K":"kilo","h":"hecto","da":"deca","d":"deci","c":"centi","m":"milli","µ":"micro","μ":"micro","u":"micro","n":"nano","p":"pico","f":"femto","a":"atto","z":"zepto","y":"yocto"}
const SI_UNITS:={"V":"volt","A":"ampere","W":"watt","F":"farad","H":"henry","Hz":"hertz","Ω":"ohm","ohm":"ohm","S":"siemens","J":"joule","N":"newton","Pa":"pascal","m":"meter","s":"second","g":"gram"}
const CONTRACTIONS:={"can't":"cannot","can not":"cannot","won't":"will not","don't":"do not","doesn't":"does not","didn't":"did not","isn't":"is not","aren't":"are not","wasn't":"was not","weren't":"were not","haven't":"have not","hasn't":"has not","hadn't":"had not","couldn't":"could not","wouldn't":"would not","shouldn't":"should not","mustn't":"must not","i'm":"i am","you're":"you are","we're":"we are","they're":"they are","i've":"i have","you've":"you have","we've":"we have","they've":"they have","i'll":"i will","you'll":"you will","we'll":"we will","they'll":"they will","let's":"let us","it's":"it is","that's":"that is","there's":"there is"}
const UNITS:={"v":"volt","volt":"volt","volts":"volt","a":"ampere","amp":"ampere","amps":"ampere","ampere":"ampere","amperes":"ampere","w":"watt","watt":"watt","watts":"watt","ohm":"ohm","ohms":"ohm","Ω":"ohm","hz":"hertz","hertz":"hertz","f":"farad","farad":"farad","farads":"farad","h":"henry","henry":"henry","henries":"henry","pound":"pound","pounds":"pound","lb":"pound","lbs":"pound","kg":"kilogram","kilogram":"kilogram","kilograms":"kilogram","cm":"centimeter","centimeter":"centimeter","centimeters":"centimeter","mm":"millimeter","millimeter":"millimeter","millimeters":"millimeter","mv":"millivolt","millivolt":"millivolt","millivolts":"millivolt","ma":"milliampere","milliamp":"milliampere","milliamps":"milliampere","milliampere":"milliampere","milliamperes":"milliampere","kv":"kilovolt","kilovolt":"kilovolt","kilovolts":"kilovolt","kohm":"kiloohm","kiloohm":"kiloohm","kiloohms":"kiloohm","microfarad":"microfarad","microfarads":"microfarad","megavolt":"megavolt","megavolts":"megavolt","megaampere":"megaampere","megaamperes":"megaampere","megohm":"megaohm","megohms":"megaohm","megaohm":"megaohm","megaohms":"megaohm","percent":"percent","percentage":"percent"}

static func matches(expected: String,actual: String) -> bool:
	if expected.strip_edges().is_empty() or actual.strip_edges().is_empty():return false
	var supplied:=canonical(expected)
	return not supplied.is_empty() and supplied==canonical(actual)

static func canonical(value: String) -> String:
	if value.length()>24000:return "oversized:"+value.sha256_text()
	value=value.replace("’","'").replace("‘","'").replace("−","-")
	# Unit symbols are case-sensitive: mW/MW, mF/MF and mHz/MHz must
	# never become equal just because surrounding speech is case-insensitive.
	value=_expand_si(value).replace("Ω"," ohm ")
	value=value.to_lower()
	for key: String in CONTRACTIONS:value=RegEx.create_from_string("\\b"+key+"\\b").sub(value,CONTRACTIONS[key],true)
	for pair: Array in [["dr.","doctor"],["mr.","mister"],["mrs.","missus"],["ms.","ms"],["a.c.","ac"],["d.c.","dc"]]:value=value.replace(str(pair[0]),str(pair[1]))
	for pair: Array in [["a c","ac"],["d c","dc"],["l e d","led"],["r m s","rms"]]:value=RegEx.create_from_string("\\b"+str(pair[0])+"\\b").sub(value,str(pair[1]),true)
	value=value.replace("="," equals ").replace("+"," plus ").replace("×"," times ").replace("*"," times ").replace("/"," divided by ").replace("%"," percent ").replace("^"," to the power of ")
	value=RegEx.create_from_string("\\b(equal to|is equal to)\\b").sub(value,"equals",true)
	value=RegEx.create_from_string("\\b(multiplied by)\\b").sub(value,"times",true)
	for pair: Array in [["(?:open|left) parenthes(?:is|es)","("],["(?:close|right) parenthes(?:is|es)",")"],["(?:open|left) (?:square )?bracket","["],["(?:close|right) (?:square )?bracket","]"]]:
		value=RegEx.create_from_string("\\b"+str(pair[0])+"\\b").sub(value,str(pair[1]),true)
	# Remove thousands separators only within valid grouped numeric tokens.
	var groups:=RegEx.create_from_string("\\b[0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]+)?\\b").search_all(value)
	for index in range(groups.size()-1,-1,-1):
		var item: RegExMatch=groups[index]
		value=value.substr(0,item.get_start())+item.get_string().replace(",","")+value.substr(item.get_end())
	value=RegEx.create_from_string("(?<=[a-z])-(?=[a-z])").sub(value," ",true)
	var tokens: Array[String]=[]
	var token_pattern:=RegEx.create_from_string("[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+|[\\p{L}]+(?:'[\\p{L}]+)?|[-<>()\\[\\]{}]|[^\\p{L}0-9\\s.,!?;:\"()\\[\\]{}]")
	for found in token_pattern.search_all(value):tokens.append(found.get_string())
	# Prose parentheses are punctuation; mathematical grouping changes the
	# calculation. Preserve it for operators and numeric/interval groups.
	var math_grouping:=tokens.any(func(token):return token in ["plus","minus","times","divided","equals","power","<",">"])
	if not math_grouping:
		for group in RegEx.create_from_string("[\\(\\[]([^()\\[\\]]+)[\\)\\]]").search_all(value):
			var inner:=str(group.get_string(1)).strip_edges()
			if RegEx.create_from_string("^[0-9.,\\s-]+$").search(inner)!=null:math_grouping=true;break
	var result: Array[String]=[]
	var cursor:=0
	while cursor<tokens.size():
		var parsed:=_number_at(tokens,cursor)
		if not parsed.is_empty():
			result.append(str(parsed.value));cursor=int(parsed.next)
			if cursor<tokens.size():
				var unit:=_unit(tokens[cursor])
				if not unit.is_empty():result.append("unit:"+unit);cursor+=1
			continue
		var token:=tokens[cursor]
		if token in ["(",")"] and not math_grouping:cursor+=1;continue
		if token=="negative" or token=="minus" or token=="-":token="minus"
		result.append(token);cursor+=1
	return " ".join(result)

static func _expand_si(value: String) -> String:
	var number_words:=SMALL.keys()+TENS.keys()+["hundred","thousand","million","billion"]
	var amount:="(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+|(?i:"+"|".join(number_words)+"))"
	# A preceding quantity keeps ordinary words such as 'am' and 'as' intact.
	var pattern:=RegEx.create_from_string("(?<![\\p{L}])("+amount+")\\s*(da|[YZEPTGMkKhdcmµμunpfazy])?(Hz|ohm|Pa|[VAWFHΩSJNmsg])(?![\\p{L}])")
	var found:=pattern.search_all(value)
	for index in range(found.size()-1,-1,-1):
		var item: RegExMatch=found[index]
		var prefix:=str(SI_PREFIXES.get(item.get_string(2),""))
		var unit:=str(SI_UNITS[item.get_string(3)])
		value=value.substr(0,item.get_start())+item.get_string(1)+" "+prefix+unit+value.substr(item.get_end())
	return value

static func _unit(token: String) -> String:
	if token in ["h","hour","hours"]:return "hour"
	if UNITS.has(token):return str(UNITS[token])
	for name: String in SI_UNITS.values():
		if token==name or token==name+"s":return name
	for prefix: String in SI_PREFIXES.values():
		if not token.begins_with(prefix):continue
		var suffix:=token.trim_prefix(prefix)
		if UNITS.has(suffix):return prefix+str(UNITS[suffix])
		for name: String in SI_UNITS.values():
			if suffix==name or suffix==name+"s":return prefix+name
	return ""

static func _number_at(tokens: Array[String],start: int) -> Dictionary:
	var cursor:=start
	var negative:=false
	if tokens[cursor] in ["negative","minus","-"]:
		negative=true;cursor+=1
		if cursor>=tokens.size():return {}
	var token:=tokens[cursor]
	if token.is_valid_float() and token.contains(".") or token.is_valid_int():
		return {"value":_decimal(token,negative),"next":cursor+1}
	# "Oh" alone is an interjection; it is a digit only after decimal point.
	if token=="oh" or (not SMALL.has(token) and not TENS.has(token)):return {}
	var total:=0
	var group:=0
	var last_scale:=1000000000000
	var previous:=""
	while cursor<tokens.size():
		token=tokens[cursor]
		if SMALL.has(token) and token!="oh":
			# Consecutive independent values remain distinct (one two != three).
			if previous in ["small","unit"]:break
			if previous=="tens" and int(SMALL[token])>=10:break
			group+=int(SMALL[token]);previous="unit" if previous=="tens" else "small";cursor+=1
		elif TENS.has(token):
			if previous in ["small","unit","tens"]:break
			group+=int(TENS[token]);previous="tens";cursor+=1
		elif token=="hundred":
			if previous!="small" or group<1 or group>9:break
			group*=100;previous="hundred";cursor+=1
		elif SCALES.has(token):
			var scale:=int(SCALES[token])
			if group<1 or scale>=last_scale:break
			total+=group*scale;group=0;last_scale=scale;previous="scale";cursor+=1
		elif token=="and" and previous in ["hundred","scale"] and cursor+1<tokens.size() and (SMALL.has(tokens[cursor+1]) or TENS.has(tokens[cursor+1])):
			cursor+=1
		else:break
	var rendered:=str(total+group)
	if cursor<tokens.size() and tokens[cursor]=="point":
		var fraction:="";var next:=cursor+1
		while next<tokens.size():
			var part:=tokens[next]
			if SMALL.has(part) and int(SMALL[part])<10:fraction+=str(SMALL[part])
			elif part.is_valid_int() and part.length()==1:fraction+=part
			else:break
			next+=1
		if not fraction.is_empty():rendered+="."+fraction;cursor=next
	return {"value":_decimal(rendered,negative),"next":cursor}

static func _decimal(value: String,negative: bool) -> String:
	var pieces:=value.split(".")
	var whole:=str(pieces[0]).trim_prefix("+")
	while whole.length()>1 and whole.begins_with("0"):whole=whole.substr(1)
	if whole.is_empty():whole="0"
	var fraction:=str(pieces[1]) if pieces.size()>1 else ""
	while fraction.ends_with("0"):fraction=fraction.left(-1)
	return ("-" if negative and (whole!="0" or not fraction.is_empty()) else "")+whole+("."+fraction if not fraction.is_empty() else "")
