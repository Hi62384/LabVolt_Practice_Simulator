extends RefCounted
## Visual mapping only; identifiers and all electrical definitions are retained.
const ROOT := "res://assets/electronics/component_shop_ui/"
static func family(entry: Dictionary) -> String:
	var kind := str(entry.get("kind",""))
	if kind=="worker_model":kind=str(entry.get("worker_model",kind))
	if kind in ["resistor"]:kind="R"
	if kind in ["capacitor"]:kind="C"
	if kind in ["inductor"]:kind="L"
	if kind in ["diode","zener"]:kind="D"
	if kind in ["npn","pnp","mosfet"]:kind="bjt"
	if kind in ["R","pot"]:return "Resistors"
	if kind in ["C","polar_cap","variable_cap"]:return "Capacitors"
	if kind in ["L","variable_inductor","signal_transformer"]:return "Inductors"
	if kind in ["V","portable_source","photodiode","solar_panel"]:return "Power"
	if kind in ["D","LED","bjt"]:return "Semiconductors"
	if str(entry.get("category",""))=="Input":return "Inputs"
	if str(entry.get("category",""))=="Output":return "Outputs"
	return "Chips & boards"

static func icon(entry: Dictionary) -> String:
	var kind := str(entry.get("kind",""))
	if kind=="worker_model":kind=str(entry.get("worker_model",kind))
	var aliases := {"resistor":"R","capacitor":"C","inductor":"L","diode":"D","zener":"D","npn":"bjt","pnp":"bjt","mosfet":"bjt","polar_cap":"C","variable_cap":"C","variable_inductor":"L","signal_transformer":"L","photodiode":"D","solar_panel":"V"}
	kind=aliases.get(kind,kind)
	if kind=="portable_source":kind="V"
	var known := {"R":"resistor","pot":"potentiometer","C":"capacitor","L":"inductor","D":"diode","LED":"led","bjt":"transistor","V":"battery","button":"button","toggle":"switch","speaker":"speaker","buzzer":"speaker","seven_segment":"display","spi_display":"display","opamp":"opamp","controller":"board"}
	if kind == "LED":
		var color_name: String = {"62e68d":"led_green", "69aaff":"led_blue", "ffd45b":"led_yellow"}.get(str(entry.get("color","")).to_lower(), "led")
		return _art(color_name, "led")
	if known.has(kind):return _art(known[kind], known[kind])
	if str(entry.get("category",""))=="Input":return ROOT+"input.svg"
	if str(entry.get("category",""))=="Output":return ROOT+"display.svg"
	if str(entry.get("category",""))=="PCB":return _art("board", "board")
	return _art("chip", "chip")

static func _art(name: String, fallback: String) -> String:
	var preview := ROOT + name + ".png"
	return preview if ResourceLoader.exists(preview) else ROOT + fallback + ".svg"

static func rarity_color(rarity: String) -> Color:
	var tokens=preload("res://scripts/ui/design_system/tokens.gd")
	return tokens.rarity_color(rarity).lerp(tokens.SURFACE,0.83)

static func preview(entry: Dictionary) -> Texture2D:
	return preload("res://scripts/electronics/component_shop_ui/component_art.gd").texture(entry)
