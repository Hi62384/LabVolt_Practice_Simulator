extends RefCounted

const MAX_EMISSION:=16.0
const SECTIONS:={
	"smartphone":{"case":"Case","trim":"Buttons and trim"},
	"portable_laptop":{"case":"Base casing","lid":"Display lid","keys":"Keyboard","trackpad":"Trackpad","bezel":"Screen bezel"},
	"calculator":{"case":"Body","keys":"Keys","display":"Display panel","trim":"Trim"},
	"usb":{"case":"Body","connector":"Connector","trim":"Indicator trim"},
	"notebook":{"front":"Front cover","back":"Back cover","binding":"Spine and binding","paper":"Paper edges"},
	"backpack":{"case":"Main fabric","pocket":"Pockets","strap":"Straps and handle","zipper":"Zipper"},
	"kit":{"case":"Case","lid":"Lid","interior":"Interior","trim":"Trim and hardware"},
	"power_bank":{"case":"Casing","trim":"Front panel","ports":"Ports"},
}

static func labels(kind: String) -> Dictionary:
	return SECTIONS.get(kind,{})

static func clean(kind: String, raw: Variant) -> Variant:
	var supported:=labels(kind)
	if not raw is Dictionary or raw.size()>supported.size():return null
	var result:={}
	for key in raw:
		if key not in supported or not raw[key] is Dictionary or raw[key].size()!=5:return null
		var part: Dictionary=raw[key]
		var color: Variant=part.get("color")
		var emission: Variant=part.get("emission")
		for value in [color,emission]:
			if not value is String or value.length()!=6 or not Color.html_is_valid(value):return null
		var entry:={"color":str(color).to_lower(),"emission":str(emission).to_lower()}
		for field in ["roughness","metallic","strength"]:
			var value: Variant=part.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0.0 or float(value)>(MAX_EMISSION if field=="strength" else 1.0):return null
			entry[field]=snappedf(float(value),.001)
		result[key]=entry
	return result

static func defaults() -> Dictionary:
	return {"color":"71828a","roughness":.6,"metallic":0.0,"emission":"ffffff","strength":0.0}

static func tag(part: Node, segment: String) -> void:
	part.set_meta("material_segment",segment)

static func apply(model: Node3D, configuration: Dictionary) -> void:
	var choices: Dictionary=configuration.get("materials",{})
	for part in model.find_children("*","GeometryInstance3D",true,false):
		var segment: String=part.get_meta("material_segment","")
		if segment.is_empty():continue
		var material: Material=part.material_override
		if material==null and part is MeshInstance3D:material=part.get_active_material(0)
		if not material is StandardMaterial3D:continue
		var baseline: StandardMaterial3D=part.get_meta("material_baseline") if part.has_meta("material_baseline") else null
		if not choices.has(segment):
			if baseline!=null:
				part.material_override=baseline
				part.remove_meta("material_baseline")
			continue
		if baseline==null:
			part.set_meta("material_baseline",material)
			material=material.duplicate()
			part.material_override=material
		var patch: Dictionary=choices[segment]
		material.albedo_color=Color(patch.color)
		material.roughness=patch.roughness
		material.metallic=patch.metallic
		material.emission_enabled=float(patch.strength)>0.0
		material.emission=Color(patch.emission)
		material.emission_energy_multiplier=patch.strength

static func from_model(model: Node3D, segment: String) -> Dictionary:
	if not is_instance_valid(model):return defaults()
	for part in model.find_children("*","GeometryInstance3D",true,false):
		if part.get_meta("material_segment","")!=segment:continue
		var material: Material=part.get_meta("material_baseline") if part.has_meta("material_baseline") else part.material_override
		if material==null and part is MeshInstance3D:material=part.get_active_material(0)
		if material is StandardMaterial3D:
			return {"color":material.albedo_color.to_html(false),"roughness":material.roughness,"metallic":material.metallic,
				"emission":material.emission.to_html(false),"strength":material.emission_energy_multiplier if material.emission_enabled else 0.0}
	return defaults()
