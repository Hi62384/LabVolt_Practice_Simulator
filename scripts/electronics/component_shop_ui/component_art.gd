extends RefCounted

const Bands = preload("res://scripts/electronics/component_shop_ui/resistor_bands.gd")
const METAL := "c7d1d4"

static func texture(entry: Dictionary) -> Texture2D:
	return _texture(_drawing(entry))

static func bundle(entries: Array, color: String, opened := false) -> Texture2D:
	if opened:
		return _texture('<path d="M13 48 24 16H83L75 48Z" fill="#263745" stroke="#91a8ad" stroke-width="2"/><path d="M11 48H86L80 80H17Z" fill="#%s" stroke="#91a8ad" stroke-width="2"/><path d="M11 48H86L75 59H21Z" fill="#15232d" stroke="#91a8ad" stroke-width="2"/>' % color)
	var art := '<path d="M10 34 20 21H77L87 34V76Q87 82 81 82H16Q10 82 10 76Z" fill="#263745" stroke="#91a8ad" stroke-width="2"/>'
	art += _rect(13, 37, 71, 38, color, 4) + _rect(27, 27, 42, 5, color, 2)
	for i in entries.size():
		art += '<g transform="translate(%d %d) scale(.38)">' % [12 + (i % 2) * 33, 26 + (i / 2) * 18]
		art += _drawing(entries[i]) + "</g>"
	return _texture(art)

static func _texture(art: String) -> Texture2D:
	var image := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" width="96" height="96">' + art + "</svg>"
	if image.load_svg_from_string(svg) != OK: return null
	return ImageTexture.create_from_image(image)

static func _drawing(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	if kind == "worker_model": kind = str(entry.get("worker_model", ""))
	if kind == "module" and entry.get("category") == "PCB":
		return _pcb()
	var pins: int = entry.get("pins", []).size()
	var axial := '<path d="M9 59H29M67 59H87" stroke="#c7d1d4" stroke-width="4" stroke-linecap="round"/>'
	match kind:
		"R", "resistor":
			var result := axial + _rect(26, 47, 44, 23, "d3ad79", 8) + _rect(31, 49, 33, 5, "ead0a0", 2)
			var bands := Bands.bands(float(entry.get("value",1000.0)), float(entry.get("resistance_tolerance",.05)))
			for i in bands.size():
				var x := 32 + i * 6 + (4 if i == bands.size() - 1 else 0)
				result += _rect(x, 48, 3, 21, bands[i].color, 1)
			return result
		"D", "diode", "zener", "tvs":
			return axial + _rect(27, 49, 42, 20, "262a32", 6) + _rect(60, 50, 4, 18, "c0baba", 1)
		"fuse":
			return axial + _rect(24, 49, 48, 20, "5c828e", 7) + _rect(24, 50, 10, 18, METAL, 4) + _rect(62, 50, 10, 18, METAL, 4) + _rect(35, 57, 26, 2, "ead3a5", 1)
		"LED", "io_rgb":
			var tint := str(entry.get("color", "e8524c"))
			var art := _header(pins, 70) + _rect(30, 42, 36, 26, tint, 7) + _circle(48, 44, 18, tint)
			art += _circle(41, 38, 5, "fbe8cc")
			if kind == "io_rgb":
				for i in 3: art += _circle(39+i*9, 55, 4, ["f77a79","81e28c","72b6ff"][i])
			return art
		"V","portable_source":
			return _rect(32, 23, 33, 10, METAL, 3) + _rect(22, 30, 53, 46, "31485d", 6) + _rect(27, 35, 43, 22, "be8148", 2) + '<path d="M35 46h10m-5 -5v10m14 -5h9" stroke="#fff1c6" stroke-width="3"/>'
		"C", "capacitor":
			return _header(pins, 70) + _rect(29, 30, 38, 39, "386276", 6) + _circle(48, 31, 16, "9aadb3") + _rect(35, 48, 4, 16, "6595a7", 2)
		"polar_cap":
			return _header(pins, 75) + _rect(28, 26, 40, 48, "294758", 7) + _rect(54, 27, 9, 44, "b7c5c4", 2) + '<ellipse cx="48" cy="26" rx="20" ry="8" fill="#b7c5c4"/><path d="M42 24l12 4m-8 3l4-10m6 23h5m-5 11h5" stroke="#647881" stroke-width="2"/>'
		"variable_cap":
			var art := _header(pins, 76) + _rect(24, 67, 48, 9, "527183", 3)
			for i in 5:
				art += _rect(28 + i * 9, 34 + (i % 2) * 8, 4, 33, "c7d1d4", 2)
			return art + _rect(18, 47, 59, 6, "8599a5", 2) + _rect(44, 17, 8, 31, "bc8e56", 2) + _circle(48, 17, 7, "e5bd81")
		"L", "inductor", "variable_inductor":
			var art := '<path d="M9 59H20L25 53M71 53l5 6h11" fill="none" stroke="#c7d1d4" stroke-width="4" stroke-linecap="round"/>'
			for i in 7:
				var x := 25 + i * 7
				art += '<ellipse cx="%d" cy="51" rx="5" ry="15" fill="none" stroke="#8f482c" stroke-width="4"/>' % x
				art += '<path d="M%d 36c6 0 7 22 1 29" fill="none" stroke="#edab67" stroke-width="3" stroke-linecap="round"/>' % x
			if kind == "variable_inductor":
				art += '<path d="M55 31l9-12" stroke="#aebdc6" stroke-width="4"/><circle cx="66" cy="17" r="7" fill="#537b91"/><path d="M62 19l8-4" stroke="#d8e4e6" stroke-width="2"/>'
			return art
		"solar_panel":
			var art := _header(pins, 78) + _rect(14, 20, 68, 56, "a2b5c5", 4)
			for row in 2:
				for column in 2:
					var x := 19 + column * 30
					var y := 25 + row * 24
					art += _rect(x, y, 28, 22, "284c7a", 2)
					for trace in 3:
						art += _rect(x + 3, y + 5 + trace * 5, 22, 1, "6a9bc0", 0)
			return art
		"pot", "io_encoder", "io_joystick", "io_selector":
			var art := _header(pins, 72) + _rect(21, 46, 54, 26, "425368", 5) + _circle(48, 45, 19, "718794")
			if kind == "io_joystick":
				return art + _rect(43, 22, 10, 24, "46545c", 3) + _circle(48, 22, 12, "283339") + _circle(44, 19, 4, "677883")
			return art + _circle(48, 38, 13, "293744") + _rect(46, 28, 4, 13, "ccdee1", 2)
		"button", "toggle", "io_slider":
			var art := _header(pins, 71) + _rect(20, 43, 56, 28, "3e4d58", 5)
			if kind == "io_slider":
				return art + _rect(28, 52, 40, 7, "17262c", 3) + _rect(47, 43, 10, 23, "c7d1d4", 2)
			if kind == "toggle": return art + '<path d="M47 53 58 28" stroke="#d67a59" stroke-width="8" stroke-linecap="round"/>'
			return art + _circle(48, 50, 13, "d56155") + _circle(47, 46, 9, "ed8773")
		"io_keypad":
			var art := _header(pins, 77) + _rect(27, 14, 42, 64, "4f6680", 5)
			for i in 12: art += _rect(31+(i%3)*12, 20+(i/3)*13, 9, 10, "bbced5" if i<9 else "e2ac64", 2)
			return art
		"seven_segment", "spi_display", "io_graphic", "hd44780", "ssd1306", "ili9341", "xpt2046":
			var art := _header(pins, 71) + _rect(13, 24, 70, 47, "416b62", 5) + _rect(19, 29, 58, 33, "172a39", 4)
			if kind == "seven_segment":
				return art + '<path d="M39 34h17v23H39zm0 11h17" fill="none" stroke="#eb6558" stroke-width="4"/>'
			for row in range(2 if kind in ["hd44780","spi_display"] else 4):
				art += _rect(26+row*3, 35+row*5, 37-row*3, 2, "8fd3ba" if kind != "ili9341" else "83bdf3", 1)
			return art
		"io_pixels", "io_bar", "io_matrix", "ws2812":
			var art := _header(pins, 71) + _rect(14, 32, 68, 38, "263c46", 5)
			var matrix := kind == "io_matrix"
			for i in range(16 if matrix else 4):
				art += _rect(24+(i%4)*13, 37+(i/4)*7 if matrix else 44, 8, 5 if matrix else 16, ["83e5a4","ffb950","f47e68","7ad7e9"][i%4], 2)
			return art
		"io_motor", "io_vibration", "io_servo":
			var art := _header(pins, 71) + _rect(21, 36, 51, 32, "72858d", 6) + _rect(24, 39, 16, 26, "3b4f5a", 4)
			if kind == "io_servo": return art + _rect(45, 25, 36, 8, "c5d5d2", 3) + _circle(51, 29, 10, "a1b3bd")
			return art + _rect(70, 47, 15, 8, METAL, 3) + (_circle(82, 44, 8, "d2aa67") if kind == "io_vibration" else "")
		"speaker", "buzzer":
			return _header(pins, 72) + _circle(48, 48, 25, "3c4956") + _circle(48, 48, 19, "697985") + _circle(48, 48, 11, "283138")
		"bjt", "jfet", "mosfet", "npn", "pnp", "regulator":
			return _header(pins, 70) + _rect(30, 26, 36, 40, "28343e", 5) + _rect(34, 32, 28, 8, "546875", 3)
		"io_bridge", "io_relay", "relay", "controller", "native_controller":
			return _header(pins, 74) + _rect(16, 27, 64, 44, "387460", 6) + _rect(34, 36, 31, 23, "273644" if kind != "io_relay" else "587ba6", 3) + _rect(21, 35, 8, 25, "84a2a6", 2) + _circle(72, 35, 3, "e6c46e")
	return _chip(pins, str(entry.get("name","")).get_slice(" ",0))

static func _pcb() -> String:
	var art := _rect(10, 23, 76, 54, "347d64", 6)
	art += '<path d="M24 38H37V48H48M24 62H38V56H54M54 48H66V38H73M54 56H73V62" fill="none" stroke="#a2d5a5" stroke-width="3" stroke-linejoin="round"/>'
	for x in [24, 73]:
		for y in [38, 62]:
			art += _circle(x, y, 4.5, "efcf82") + _circle(x, y, 1.8, "254c47")
	return art + _rect(44, 43, 16, 18, "253641", 3)

static func _chip(pins: int, marking: String) -> String:
	var art := ""
	for side in range(2):
		var count := ceili(pins / 2.0) if side == 0 else floori(pins / 2.0)
		for i in count:
			var x := 26 + 44.0 * (i + .5) / count
			art += _rect(x-1.7, 29 if side == 0 else 61, 3.4, 10, METAL, 1)
	art += _rect(20, 37, 56, 27, "202c36", 4) + _rect(23, 39, 50, 3, "485a66", 1)
	art += _circle(26, 47, 2, "f5dd99")
	var safe := marking.left(10).xml_escape()
	return art + '<text x="48" y="55" text-anchor="middle" font-family="sans-serif" font-size="9" fill="#ccd7d8">%s</text>' % safe

static func _header(pins: int, y: float) -> String:
	var art := ""
	var spacing := minf(9, 55.0 / maxf(pins, 1))
	for i in pins: art += _rect(47+(i-(pins-1)*.5)*spacing, y-5, 2.7, 12, METAL, 1)
	return art

static func _rect(x: float, y: float, w: float, h: float, fill: String, roundness: float) -> String:
	return '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="#%s"/>' % [x,y,w,h,roundness,fill]

static func _circle(x: float, y: float, r: float, fill: String) -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="#%s"/>' % [x,y,r,fill]

