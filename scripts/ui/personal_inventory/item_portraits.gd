extends RefCounted

const Components = preload("res://scripts/electronics/component_shop_ui/component_art.gd")
var cache: Dictionary = {}

func texture(item: Dictionary, profile: RefCounted) -> Texture2D:
	var kind := str(item.get("kind",""))
	if kind.is_empty():return null
	var type := str(item.get("type",""))
	if kind == "kit":
		type = str(item.get("tier",profile.data.get("kit_tiers",{}).get(item.get("id",""),"standard")))
	var key := kind+(type if not type.is_empty() else str(item.get("color","")))
	if not cache.has(key):
		if kind == "component":
			cache[key]=Components.texture(profile.catalog().get(item.type,{}))
		elif kind == "food":
			cache[key]=load("res://assets/ui/food_menu/%s.svg" % type) as Texture2D
		else:
			var art := _draw(kind,int(item.get("color",0)),type)
			var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="96" viewBox="0 0 128 96">'+art+'</svg>'
			var image := Image.new()
			if image.load_svg_from_string(svg)!=OK:return null
			cache[key]=ImageTexture.create_from_image(image)
	return cache[key]

func _draw(kind: String, color_index: int, type: String) -> String:
	match kind:
		"paper", "notebook":
			var art := '<g transform="rotate(-13 64 48)"><rect x="36" y="14" width="56" height="73" rx="4" fill="#142230" opacity=".65"/>'
			if kind=="notebook":
				art += '<rect x="35" y="12" width="56" height="70" rx="4" fill="#416b78"/><path d="M40 14v65" stroke="#254854" stroke-width="8"/><rect x="54" y="29" width="25" height="14" rx="2" fill="#ddd2b8"/><path d="M43 78h43" stroke="#a7b9ae" stroke-width="2"/>'
			else:
				art += '<path d="M35 10h43l12 12v58H35z" fill="#e7dfc8"/><path d="M78 10v12h12" fill="#b4b29f"/><path d="M44 29h26m-26 10h36m-36 9h36m-36 9h36m-36 9h28" stroke="#768994" stroke-width="2"/>'
			return art+"</g>"
		"calculator":
			if type=="calculator_basic":
				return '<rect x="37" y="12" width="54" height="73" rx="7" fill="#16191d"/><rect x="44" y="20" width="40" height="19" rx="3" fill="#a6b997"/><path d="M49 51h7m8 0h7m8 0h5m-35 10h7m8 0h7m8 0h5m-35 11h7m8 0h7m8 0h5" stroke="#dbe5e8" stroke-width="5" stroke-linecap="round"/>'
			if type=="calculator_financial":
				return '<rect x="32" y="12" width="64" height="73" rx="7" fill="#3c5345"/><rect x="39" y="20" width="50" height="15" rx="3" fill="#cedbaf"/><path d="M43 46h9m9 0h9m9 0h7" stroke="#e3a954" stroke-width="5" stroke-linecap="round"/><path d="M43 56h9m9 0h9m9 0h7m-43 11h9m9 0h9m9 0h7m-43 11h9m9 0h9m9 0h7" stroke="#d8e5df" stroke-width="5" stroke-linecap="round"/>'
			var art := '<g transform="rotate(-12 64 48)"><rect x="43" y="9" width="43" height="79" rx="7" fill="#192833"/><rect x="43" y="9" width="41" height="75" rx="6" fill="#3b4656"/><rect x="49" y="18" width="29" height="14" rx="2" fill="#a0b391"/><path d="M66 27h8" stroke="#3d4d42" stroke-width="2"/>'
			for row in 6:
				for col in 4:
					art += '<rect x="%d" y="%d" width="5" height="5" rx="1" fill="#%s"/>' % [49+col*8,39+row*7,"d5a969" if row==0 else "bec9d2"]
			return art+"</g>"
		"lab_goggles":
			return '<path d="M25 47Q16 30 36 29h56q20 0 11 18" fill="none" stroke="#334b57" stroke-width="5"/><path d="M23 39h30l11 8 11-8h30l-4 23q-4 7-15 7H78q-8 0-14-12-6 12-14 12h-8q-11 0-15-7z" fill="#9cdaec" fill-opacity=".75" stroke="#2a5c70" stroke-width="5"/><path d="M34 47h15m30 0h15" stroke="#edf9fb" stroke-width="3" stroke-linecap="round"/>'
		"pencil_case":
			return '<g transform="rotate(-13 64 48)"><rect x="19" y="32" width="90" height="36" rx="11" fill="#452b31"/><rect x="19" y="27" width="90" height="35" rx="10" fill="#a45652"/><path d="M26 39h75" stroke="#633736" stroke-width="4"/><path d="M26 39h75" stroke="#d9a982" stroke-width="2" stroke-dasharray="2 2"/><rect x="94" y="40" width="8" height="7" rx="2" fill="#deb78a"/></g>'
		"flashlight":
			return '<g transform="rotate(-20 64 48)"><rect x="22" y="39" width="66" height="21" rx="6" fill="#314652"/><path d="M76 39l14-10h18v41H90L76 60z" fill="#546972"/><path d="M104 33v33" stroke="#f8db93" stroke-width="6"/><rect x="60" y="43" width="12" height="7" rx="2" fill="#dbb16e"/></g>'
		"whiteboard":
			return '<rect x="18" y="19" width="92" height="59" rx="4" fill="#647881"/><rect x="23" y="24" width="82" height="48" rx="2" fill="#e9eee8"/><path d="M35 58l14-13 12 7 17-17" fill="none" stroke="#3a7784" stroke-width="4" stroke-linecap="round"/><path d="M53 76h39" stroke="#9aa9aa" stroke-width="5"/>'
		"marker":
			return '<g transform="rotate(-28 64 48)"><rect x="22" y="39" width="83" height="18" rx="5" fill="#dedbd1"/><path d="M22 39h21v18H22zM85 39h20v18H85z" fill="#31596b"/><path d="M50 48h26" stroke="#657d86" stroke-width="3"/></g>'
		"backpack":
			var color: String={"backpack_small":"607b58","backpack_medium":"3b7283","backpack_large":"8e5544","backpack_giant":"645780"}.get(type,"3b7283")
			return '<path d="M52 19v-7h24v7" fill="none" stroke="#c4af8d" stroke-width="5"/><rect x="32" y="17" width="64" height="70" rx="16" fill="#%s"/><rect x="40" y="50" width="48" height="27" rx="7" fill="#253b48"/><path d="M44 53h39M40 37h48" stroke="#dcc399" stroke-width="3"/><path d="M33 42l-6 34m68-34 6 34" stroke="#293644" stroke-width="5"/>' % color
		"kit":
			match type:
				"compact":
					return '<rect x="33" y="36" width="62" height="36" rx="10" fill="#263d37"/><rect x="33" y="32" width="62" height="33" rx="10" fill="#667d55"/><path d="M37 45h54M52 32v-7h24v7" fill="none" stroke="#afbb88" stroke-width="4"/><rect x="59" y="43" width="10" height="10" rx="2" fill="#e0bb73"/>'
				"extended":
					return '<path d="M17 41l10-13h74l10 13v38H17z" fill="#213e60"/><path d="M17 41l10-13h74l10 13z" fill="#5b8cb4"/><rect x="20" y="44" width="88" height="29" rx="4" fill="#38658f"/><path d="M47 29V19h34v10M24 65h80" fill="none" stroke="#82a4c2" stroke-width="5"/><path d="M31 43v13m66-13v13" stroke="#e9c984" stroke-width="7"/><rect x="53" y="49" width="22" height="9" rx="2" fill="#c5dde4"/>'
				"large":
					return '<rect x="12" y="31" width="104" height="48" rx="8" fill="#342c4d"/><rect x="12" y="27" width="104" height="40" rx="8" fill="#685286"/><path d="M46 28V17h36v11M17 43h94" fill="none" stroke="#a48bbb" stroke-width="5"/><path d="M28 32v40m72-40v40" stroke="#4a3b68" stroke-width="8"/><path d="M28 41v13m72-13v13" stroke="#ebbc73" stroke-width="7"/><path d="M52 54h24v9H52z" fill="#d7c0e3"/><circle cx="24" cy="76" r="6" fill="#242733"/><circle cx="104" cy="76" r="6" fill="#242733"/>'
			return '<path d="M22 40l11-13h62l11 13v35H22z" fill="#1c3946"/><path d="M22 40l11-13h62l11 13z" fill="#527282"/><rect x="22" y="41" width="84" height="28" rx="3" fill="#305866"/><path d="M49 28v-8h29v8" fill="none" stroke="#607888" stroke-width="5"/><path d="M37 44v11m54-11v11" stroke="#d6ab70" stroke-width="6"/><rect x="50" y="52" width="27" height="9" rx="2" fill="#b9b79f"/>'
		"board":
			if type=="pcb":
				return '<rect x="18" y="23" width="92" height="56" rx="6" fill="#142e2b"/><rect x="18" y="18" width="92" height="56" rx="6" fill="#358164"/><path d="M29 30h19l11 11h19m-49 20h19l11-11h27l13-18m0 28H80" fill="none" stroke="#dab75f" stroke-width="3"/><rect x="52" y="34" width="28" height="24" rx="3" fill="#25333e"/><path d="M30 30h.1m0 31h.1m69-29h.1m0 28h.1" stroke="#f5d48d" stroke-width="7" stroke-linecap="round"/>'
			var art := '<g transform="translate(13 18) skewX(-9)"><rect x="9" y="11" width="98" height="49" rx="6" fill="#485c62"/><rect x="9" y="7" width="98" height="48" rx="5" fill="#e3e0cc"/><path d="M14 14h87m-87 34h87" stroke="#b45e58" stroke-width="2"/><path d="M14 17h87m-87 34h87" stroke="#5887a4" stroke-width="2"/><path d="M14 32h87" stroke="#a0a79b" stroke-width="4"/>'
			for row in [22,26,38,42]:
				for col in 19:
					art += '<circle cx="%d" cy="%d" r="1.2" fill="#53656a"/>' % [15+col*4.7,row]
			return art+"</g>"
		"wire","dc_wire":
			var tint: String = ["d95c54","5895d2","e9b74d","5f6571"][clampi(color_index,0,3)]
			var path := "M23 54C8 21 91 15 95 46s-72 34-68 9 77-28 78 4l-1 9"
			return '<path d="%s" stroke="#172730" stroke-width="10" fill="none"/><path d="%s" stroke="#%s" stroke-width="6" fill="none"/><path d="M23 53l5 8m76 6-1 10" stroke="#d6c4a5" stroke-width="5" stroke-linecap="round"/>' % [path,path,tint]
	return ""
