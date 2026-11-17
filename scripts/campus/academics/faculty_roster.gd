extends RefCounted
static var GENERATED: Dictionary={}
const PEOPLE := {
 "bill_nye":{"name":"Bill Nye","courses":["MTH255"],"appearance":{"hair":"Sweep","hair_color":"a6a8a6","glasses":"Square","outfit":"Lab coat","top":"e2e8e4","expression":"Calm"}},
 "mr_apple":{"name":"Mr Apple","courses":["MTH147"],"appearance":{"skin":"54382e","hair":"Bald","beard":true,"hair_color":"969c9a","expression":"Smile"}},
 "ms_clocks":{"name":"Ms Clocks","courses":["ETY155"],"appearance":{"skin":"f3cbb1","hair":"Curls","hair_volume":1.35,"expression":"Calm","outfit":"Workwear","top":"65827c"}},
 "mr_phillips":{"name":"Mr Phillips","courses":["ETY155","ELM253"],"appearance":{"skin":"f3cbb1","glasses":"Square","expression":"Calm","outfit":"Workwear","top":"637787"}},
 "mr_gusto":{"name":"Mr Gusto","courses":["ELM253"],"appearance":{"skin":"f3cbb1","hair":"Bald","expression":"Smile","outfit":"Workwear","top":"597d7a"}},
 "mr_hamstrings":{"name":"Mr Hamstrings","courses":["DGS266"],"appearance":{"skin":"54382e","hair":"Crop","hair_color":"34363a","beard":true,"expression":"Calm"}},
 "mr_allu":{"name":"Mr Allu","courses":["DGS266","MTH147"],"appearance":{"skin":"deb08c","hair":"Curls","hair_color":"5b4e39","beard":true,"outfit":"Workwear","top":"71634b","pants":"5f5848","expression":"Curious"}},
 "bill":{"name":"Bill","courses":["MTH255","ETY155"],"appearance":{"hair":"Sweep","outfit":"Workwear","top":"263e50","accent":"d6d8d4","expression":"Stern"}},
 "chad":{"name":"Chad","courses":["MTH147","MTH255"],"appearance":{"skin":"c78e64","height":1.25,"build":1.3,"shoulders":1.3,"outfit":"Workwear","top":"284759","expression":"Grin"}},
 "brian":{"name":"Brian","courses":["DGS266"],"appearance":{"skin":"a86c49","expression":"Frown","top":"754d41"}},
 "ms_bird_heart":{"name":"Ms Bird Heart","courses":["MTH147","MTH255"],"appearance":{"build":1.35,"hair":"Bun","hair_color":"b8b7b1","glasses":"Round","expression":"Smile","top":"8a9a8b"}},
 "dr_volts":{"name":"Dr Volts","courses":["ETY155","ELM253","DGS266"],"appearance":{"hair":"Spikes","hair_color":"d1d5d0","outfit":"Lab coat","top":"e6e9e0","glasses":"Round","expression":"Curious"}},
 "stanley":{"name":"Stanley","courses":["MTH255"],"appearance":{"hair":"Bald","beard":true,"hair_color":"c1c3bd","expression":"Calm","outfit":"Workwear","top":"8a8d80","height":.88}},
 "ms_rivera":{"name":"Ms Rivera","courses":["MTH147","DGS266"],"appearance":{"hair":"Bob","expression":"Calm","top":"6f7887"}},
 "mr_blake":{"name":"Mr Blake","courses":["ELM253","DGS266"],"appearance":{"hair":"Spikes","expression":"Grin","top":"5d8b8c"}},
 "mr_stone":{"name":"Mr Stone","courses":["ETY155","ELM253"],"appearance":{"hair":"Crop","expression":"Stern","outfit":"Workwear","top":"4c5b43","pants":"394539"}},
 "josh_wildes":{"name":"Josh Wildes","courses":["DGS266","MTH147"],"appearance":{"hair":"Sweep","expression":"Grin","top":"675b77"}},
 "bradley":{"name":"Bradley","courses":["DGS266","ELM253"],"appearance":{"glasses":"Square","hair":"Sweep","outfit":"Workwear","top":"20272c","pants":"385c84","expression":"Calm"}},
 "jeff":{"name":"Jeff","courses":["ETY155"],"appearance":{"hair":"Bald","build":1.35,"shoulders":1.35,"outfit":"Tee","top":"686f72","expression":"Frown"}},
 "mr_bro":{"name":"Mr Bro","courses":["ETY155","MTH147"],"appearance":{"hair":"Crop","glasses":"Square","build":1.4,"shoulders":1.4,"height":1.2,"outfit":"Tee","top":"405f64","expression":"Calm"}},
 "ms_lunch":{"name":"Ms Lunch","courses":[],"appearance":{"skin":"deb08c","build":1.4,"waist":1.4,"shoulders":1.4,"body_depth":1.4,"hair":"Bun","outfit":"Workwear","top":"6b796c","expression":"Stern"}}
}
static func eligible(courses: Array,excluded: Array=[]) -> Array:
 var options:=[]
 for id in all_people():
  if id in excluded:continue
  if entry(id).courses.any(func(course):return course in courses):options.append(id)
 return options
static func all_people() -> Dictionary:
 var result:=PEOPLE.duplicate(true)
 result.merge(GENERATED,true)
 return result
static func has(id: String) -> bool:return PEOPLE.has(id) or GENERATED.has(id)
static func entry(id: String) -> Dictionary:return PEOPLE.get(id,GENERATED.get(id,{}))
static func add_generated(id: String,profile: Dictionary) -> bool:
 if not id.begins_with("generated_") or id.length()>48 or PEOPLE.has(id) or GENERATED.size()>=12:return false
 var name:=str(profile.get("name","")).strip_edges()
 var course:=str(profile.get("course",""))
 var style:=str(profile.get("style",""))
 if name.length()<3 or name.length()>32 or style.length()<3 or style.length()>120 or course not in ["MTH147","MTH255","ETY155","ELM253","DGS266"]:return false
 for character in name:
  if not (character.is_valid_identifier() or character==" " or character=="-"):return false
 var appearance_value: Variant=profile.get("appearance",{})
 if not appearance_value is Dictionary:return false
 var appearance: Dictionary=appearance_value
 var safe_appearance:={"expression":"Calm","outfit":"Workwear","top":"637787"}
 for key in ["hair","hair_color","skin","glasses","expression","top"]:
  if appearance.has(key) and str(appearance[key]).length()<=16:safe_appearance[key]=str(appearance[key])
 GENERATED[id]={"name":name,"courses":[course],"appearance":safe_appearance,"style":style}
 return true
static func config(id: String) -> Dictionary:
 var data: Dictionary=entry(id)
 if data.is_empty():return {}
 var config: Dictionary=preload("res://scripts/toon_character.gd").defaults()
 config.merge(data.appearance,true);config.name=data.name
 return config
