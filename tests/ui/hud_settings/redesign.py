"""Preimage-bound source migration; never starts Godot or reads user saves."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
OWNED = ['scripts/lab_ui.gd', 'scripts/lab_chat.gd',
 'scripts/campus/ui/campus_hud.gd', 'scripts/campus/ui/profile_inspector.gd',
 'scripts/campus/ui/profile_visibility.gd', 'scripts/campus/ui/graphics_settings.gd',
 'scripts/campus/facilities/facility_panel.gd', 'scripts/campus/performance/profiling_overlay.gd']
BACKUP = ROOT / 'scripts/ui/hud_settings/review'
BACKUP.mkdir(parents=True, exist_ok=True)
raw = {p: (ROOT / p).read_bytes() for p in OWNED}
src = {p: b.decode('utf-8-sig').replace('\r\n', '\n') for p, b in raw.items()}
out = dict(src)
IMPORTS = '''const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Skin = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
'''
def swap(s, before, after):
    assert s.count(before) == 1, (before, s.count(before))
    return s.replace(before, after)

p = 'scripts/lab_ui.gd'
s = src[p].replace('extends CanvasLayer\n', 'extends CanvasLayer\n' + IMPORTS, 1)
a=s.index('\tvar node := Button.new()', s.index('func button'))
b=s.index('\tparent.add_child(node)',a)
s=s[:a]+'''\tvar node := UI.action(text, UI.action_icon(text), callback, text in ["Enter / Resume", "Submit"])
'''+s[b:]
a=s.index('\tvar style := StyleBoxFlat.new()',s.index('func panel'))
b=s.index('\tadd_child(node)',a)
s=s[:a]+'''\tnode.theme = Skin.create()
\tnode.add_theme_stylebox_override("panel", Skin.card_style())
'''+s[b:]
s=swap(s,'menu = panel(Vector2(340,30),Vector2(600,660))','menu = panel(Vector2(160,30),Vector2(0,0))')
s=swap(s,'\tlabel("LAB / VOLT",box,34)\n\tlabel("Cooperative electrical laboratory",box,17)', '\tbox.add_child(UI.header("Laboratory", "Your session, experiment and personal settings", func(): game.capture()))')
s=swap(s,'\tlobby = VBoxContainer.new()\n\tlobby.name = "Laboratory"\n\ttabs.add_child(lobby)', '\tlobby = Layout.page(tabs, "Session", "network")\n\tvar session_card := Layout.section(lobby, "Connect with your team", "Direct IP • 2–8 players • UDP", "network")')
s=swap(s,'\tlobby.add_child(name_input)', '\tLayout.field(session_card, "Player name", name_input)')
s=swap(s,'\tvar network := HBoxContainer.new()\n\tlobby.add_child(network)', '\tvar network := VBoxContainer.new()\n\tsession_card.add_child(network)')
s=swap(s,'\tnetwork.add_child(address)', '\tLayout.field(network, "Host address", address)')
s=swap(s,'\tnetwork.add_child(port)', '\tLayout.field(network, "UDP port", port)')
s=swap(s,'\tvar row := HBoxContainer.new()\n\tlobby.add_child(row)', '\tvar row := Layout.flow(session_card)')
s=s.replace('row = HBoxContainer.new()\n\tlobby.add_child(row)', 'row = Layout.flow(lobby)')
s=swap(s,'\troster_label = label("",lobby,15)', '\tvar team_card := Layout.section(lobby, "Team roster", "Ready up when your team is prepared.", "network")\n\troster_label = label("",team_card,15)\n\troster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n\tvar experiment_card := Layout.section(lobby, "Experiment setup", "Host controls • applies through the existing session request", "circuit")')
s=swap(s,'\tlobby.add_child(modes)', '\tLayout.field(experiment_card, "Laboratory mode", modes)')
s=swap(s,'\tlobby.add_child(tasks)', '\tLayout.field(experiment_card, "Experiment", tasks)')
s=swap(s,'button("Assign experiment (host)",lobby,', 'button("Assign experiment (host)",experiment_card,')
s=swap(s,'\tsettings = VBoxContainer.new()\n\tsettings.name = "Settings"\n\tsettings.theme=preload("res://scripts/campus/ui/campus_theme.gd").create()', '\tsettings = Layout.page(tabs, "Settings", "settings")')
s=swap(s,'\ttabs.add_child(settings)\n', '')
s=swap(s,'\tlabel("Mouse sensitivity",settings)', '\tvar controls_card := Layout.section(settings, "Movement & input", "Changes save with your existing player settings.", "settings")\n\tlabel("Mouse sensitivity",controls_card)')
for target in ['slider','bob','assists']:
    s=swap(s,f'\tsettings.add_child({target})',f'\tcontrols_card.add_child({target})')
s=swap(s,'\tlabel("Click an action, then press a new key:",settings,14)', '\tvar keys_card := Layout.section(settings, "Keyboard bindings", "Select an action, then press a new key.", "settings")')
s=swap(s,'game.player.keys[action]),settings,', 'game.player.keys[action]),keys_card,')
s=swap(s,'\t\tkey_button.custom_minimum_size.y = 27', '\t\tkey_button.custom_minimum_size.y = 44')
s=swap(s,'\tvar records_tab := VBoxContainer.new()\n\trecords_tab.name = "Records"\n\ttabs.add_child(records_tab)', '\tvar records_tab := Layout.page(tabs, "Records", "course")\n\tvar record_card := Layout.section(records_tab, "Personal lab record", "Your best results and recent submissions", "course")')
s=swap(s,'records_label = label("No submissions yet.",records_tab,16)', 'records_label = label("No submissions yet.",record_card,16)')
s=swap(s,'records_label.custom_minimum_size = Vector2(510,360)', 'records_label.custom_minimum_size = Vector2(0,260)')
s=s.replace('row = HBoxContainer.new()\n\tbox.add_child(row)', 'row = Layout.flow(box)')
s=swap(s,'sheet = panel(Vector2(250,36),Vector2(780,646))','sheet = panel(Vector2(160,36),Vector2.ZERO)')
s=swap(s,'\tsheet.add_child(box)\n\tlabel("EXPERIMENT / RECORD",box,28)', '''\tvar sheet_scroll := ScrollContainer.new()
\tsheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
\tsheet_scroll.follow_focus = true
\tsheet.add_child(sheet_scroll)
\tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
\tsheet_scroll.add_child(box)
\tbox.add_child(UI.header("Experiment record", "Measure • record • submit", func(): sheet.hide(); game.capture()))''')
s=swap(s,'sheet_text.custom_minimum_size = Vector2(720,255)', 'sheet_text.custom_minimum_size = Vector2(0,180)')
s=swap(s,'\t\trow.add_child(input)', '\t\tvar field := UI.field({"v":"Voltage · V RMS","i":"Current · A RMS","p":"Real power · W"}[key], input.placeholder_text)\n\t\tfield.custom_minimum_size.x = 190\n\t\tinput.free()\n\t\tinput = field.get_node("Input")\n\t\trow.add_child(field)')
s=swap(s,'\tupdate_roster()\n', '''\tfor overlay in [hud, objective, prompt, log_label]:
\t\toverlay.theme = menu.theme
\t\toverlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t\toverlay.add_theme_color_override("font_shadow_color", Color.BLACK)
\t\toverlay.add_theme_constant_override("shadow_outline_size", 3)
\thud.add_theme_stylebox_override("normal", Skin.card_style())
\tobjective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tlog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tchat_input.theme = menu.theme
\tget_viewport().size_changed.connect(_fit_layout)
\t_fit_layout()
\tupdate_roster()

func _fit_layout() -> void:
\tvar area := get_viewport().get_visible_rect().size
\tfor window in [menu, sheet]:
\t\twindow.size = Vector2(minf(960, area.x - 32), minf(660, area.y - 32))
\t\twindow.position = (area - window.size) * 0.5
\tcrosshair.position = area * 0.5 - Vector2(6, 18)
\tobjective.position = Vector2(28, 78)
\tobjective.custom_minimum_size.x = minf(580, area.x - 56)
\tprompt.position = Vector2(maxf(16, (area.x - 560) * 0.5), area.y * 0.56)
\tprompt.custom_minimum_size.x = minf(560, area.x - 32)
\tlog_label.position = Vector2(28, area.y - 100)
\tlog_label.custom_minimum_size.x = minf(580, area.x - 56)
''')
out[p]=s

p='scripts/campus/ui/profile_visibility.gd';s=src[p].replace('extends RefCounted\n','extends RefCounted\n'+IMPORTS,1)
s=swap(s,'\tvar label := Label.new(); label.text="Public player card · shared fields"; parent.add_child(label)', '\tvar body := Layout.section(parent, "Public player card", "Choose what other players may see. Grades and notes outside the public projection stay private.", "lock")\n\tvar feedback := UI.text("Changes save immediately.", "MutedLabel")\n\tbody.add_child(feedback)')
s=swap(s,'toggle.text=key.capitalize(); toggle.button_pressed=values[key]; parent.add_child(toggle)', 'toggle.text="Share "+key.capitalize(); toggle.button_pressed=values[key]; toggle.custom_minimum_size.y=44; body.add_child(toggle)')
s=swap(s,'toggle.toggled.connect(func(enabled):values[key]=enabled; save_settings())', 'toggle.toggled.connect(func(enabled):\n\t\t\tvalues[key]=enabled\n\t\t\tvar error := save_settings()\n\t\t\tfeedback.text="Visibility saved" if error==OK else "Could not save visibility: "+error_string(error)\n\t\t\tfeedback.theme_type_variation="MutedLabel" if error==OK else "ErrorLabel")')
out[p]=s

p='scripts/campus/ui/graphics_settings.gd';s=src[p].replace('extends Node\n','extends Node\n'+IMPORTS,1)
s=swap(s,'\tvar title := Label.new(); title.text="Graphics · applies immediately"; parent.add_child(title)\n\tvar presets := HBoxContainer.new(); parent.add_child(presets)', '\tvar body := Layout.section(parent, "Graphics", "Applies immediately • choose a preset or tune each setting", "palette")\n\tvar presets := Layout.flow(body)')
s=swap(s,'var b := Button.new(); b.text=level; presets.add_child(b); b.pressed.connect(func():preset(level))', 'var b := UI.action(level, "palette", func():preset(level)); presets.add_child(b)')
s=swap(s,'\tfor key in DEFAULTS:\n\t\tvar row := HBoxContainer.new(); parent.add_child(row)', '\tvar quality := Layout.section(body, "Image quality", "Resolution, filtering and anti-aliasing", "settings")\n\tvar environment := Layout.section(body, "World detail", "Lighting, effects and local presentation", "home")\n\tfor key in DEFAULTS:\n\t\tvar row := VBoxContainer.new(); (quality if key in ["render_scale","resolution","texture","aa"] else environment).add_child(row)')
s=swap(s,'label.custom_minimum_size.x=150; row.add_child(label)', 'label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; row.add_child(label)')
s=swap(s,'select.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(select)', 'select.size_flags_horizontal=Control.SIZE_EXPAND_FILL; select.custom_minimum_size.y=44; select.tooltip_text=label.text; row.add_child(select)')
out[p]=s

p='scripts/campus/ui/profile_inspector.gd';s=src[p].replace('extends PanelContainer\n','extends PanelContainer\n'+IMPORTS,1)
a=s.index('\ttheme=');b=s.index('\tvar box :=',a)
s=s[:a]+'''\ttheme=Skin.create()
\tadd_theme_stylebox_override("panel", Skin.card_style())
\tcustom_minimum_size=Vector2(300,240)
\tsize=Vector2(minf(560,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
\tvar scroll := ScrollContainer.new()
\tscroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
\tscroll.follow_focus=true
\tadd_child(scroll)
'''+s[b:]
s=swap(s,'\tvar name_label := Label.new(); name_label.text=projected.name; name_label.add_theme_font_size_override("font_size",24); box.add_child(name_label)', '\tbox.add_child(UI.header(projected.name, "Public player card • shared by this player", hide))\n\tvar shared_sections := 0')
s=swap(s,'\t\tvar label := Label.new(); label.text=section.capitalize(); label.modulate=Color("80dfc5"); box.add_child(label)', '\t\tshared_sections += 1\n\t\tvar section_body := Layout.section(box, section.capitalize(), "Shared information", {"appearance":"palette","kit":"inventory","parts":"component","money":"cart","course":"course","gym":"play","emotes":"play"}.get(section,"info"))')
s=swap(s,'detail.custom_minimum_size.x=340; box.add_child(detail)', 'detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; section_body.add_child(detail)')
s=swap(s,'\tvar close := Button.new(); close.text="Close"; close.pressed.connect(hide); box.add_child(close)', '\tif shared_sections == 0:\n\t\tbox.add_child(UI.card("Private profile", "This player has not shared additional fields.", "lock"))\n\tbox.add_child(UI.action("Close player card", "close", hide))')
out[p]=s

p='scripts/lab_chat.gd';s=src[p].replace('extends CanvasLayer\n','extends CanvasLayer\n'+IMPORTS,1)
a=s.index('\tvar style :=');b=s.index('\tgame.ui.chat_input.set_',a)
s=s[:a]+'''\tpanel.theme=Skin.create()
\tpanel.add_theme_stylebox_override("panel",Skin.card_style())
\tvar box := VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(box)
\tvar channel := UI.badge("Team channel · T to chat", "network");channel.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(channel)
\tlog_view=RichTextLabel.new();log_view.bbcode_enabled=false;log_view.scroll_following=true;log_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
\tlog_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
\tlog_view.add_theme_font_size_override("normal_font_size",15);box.add_child(log_view)
\tgame.ui.chat_input.theme=panel.theme
\tgame.ui.chat_input.tooltip_text="Team chat • Enter sends • Escape closes"
'''+s[b:]
s=swap(s,'\tgame.session.chat_received.connect(receive)', '\tgame.session.chat_received.connect(receive)\n\tget_viewport().size_changed.connect(_fit_chat)\n\t_fit_chat()\n\nfunc _fit_chat() -> void:\n\tvar area := get_viewport().get_visible_rect().size\n\tpanel.position=Vector2(24,area.y-245);panel.size=Vector2(minf(430,area.x-48),175)\n\tgame.ui.chat_input.position=Vector2(24,area.y-60);game.ui.chat_input.size=Vector2(minf(430,area.x-48),44)')
out[p]=s

p='scripts/campus/ui/campus_hud.gd';s=src[p].replace('extends HBoxContainer\n','extends HBoxContainer\n'+IMPORTS,1)
a=s.index('\tfor field in');b=s.index('func update_state',a)
s=s[:a]+'''\ttheme=Skin.create()
\t# Flow inside the existing HBox root preserves front_menu's typed reference.
\tvar flow := HFlowContainer.new()
\tflow.custom_minimum_size.x=minf(1000,get_viewport_rect().size.x-56)
\tflow.mouse_filter=Control.MOUSE_FILTER_IGNORE
\tadd_child(flow)
\tfor field in ["location","activity","timer","guidance"]:
\t\tvar card := PanelContainer.new();card.mouse_filter=Control.MOUSE_FILTER_IGNORE
\t\tcard.add_theme_stylebox_override("panel",Skin.card_style())
\t\tvar badge := UI.badge("", {"location":"home","activity":"course","timer":"info","guidance":"play"}[field])
\t\tcard.add_child(badge);flow.add_child(card)
\t\tvar label := badge.get_child(1) as Label
\t\tlabel.custom_minimum_size.x=100
\t\tlabel.autowrap_mode=TextServer.AUTOWRAP_OFF
\t\tset(field,label)
\tget_viewport().size_changed.connect(func():flow.custom_minimum_size.x=minf(1000,get_viewport_rect().size.x-56))
'''+s[b:]
s += '\n\tfor label in [location,activity,timer,guidance]:\n\t\tlabel.get_parent().get_parent().visible=not label.text.is_empty()\n'
out[p]=s

p='scripts/campus/facilities/facility_panel.gd';s=src[p].replace('extends PanelContainer\n','extends PanelContainer\n'+IMPORTS,1)
a=s.index('\tcustom_minimum_size=');b=s.index('\nfunc bind',a)
s=s[:a]+'''\ttheme=Skin.create()
\tcustom_minimum_size=Vector2(300,240)
\tsize=Vector2(minf(600,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
\tadd_theme_stylebox_override("panel",Skin.card_style())
\tvar scroll := ScrollContainer.new()
\tscroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
\tscroll.follow_focus=true
\tadd_child(scroll)
\tbody.size_flags_horizontal=Control.SIZE_EXPAND_FILL
\tscroll.add_child(body)
\tbody.add_theme_constant_override("separation",12)
'''+s[b:]
s=swap(s,'station_id=id;station_kind=kind;visible=true\n\tcontroller.refresh()', 'station_id=id;station_kind=kind;visible=true\n\tredraw()\n\tcontroller.refresh()')
s=swap(s,'var node:=Button.new();node.text=text;node.custom_minimum_size.y=38', 'var node:=UI.action(text, {"buy":"cart","start":"play","beat":"play","finish":"save","cancel":"back","consume":"check","sit":"home","place":"inventory","pickup":"inventory","emote":"play","stop":"back"}.get(str(request.get("op","")),"info"), Callable(), request.get("op","") in ["start","beat","buy"])')
s=swap(s,'\t\tcontroller.request(value))', '\t\tcontroller.request(value)\n\t\tredraw())')
s=swap(s,'\tvar title:=Label.new();title.text="Campus facilities";title.add_theme_font_size_override("font_size",24);body.add_child(title)', '\tvar title := station_kind.trim_prefix("counter:").replace("_"," ").capitalize()\n\tbody.add_child(UI.header(title if not title.is_empty() else "Campus service", "Local services • "+station_id, hide))')
s=swap(s,'\tif state.is_empty():status.text="Connecting to campus host…";return', '\tif state.is_empty():status.text="Connecting to campus host…";return\n\tbody.add_child(UI.badge("Waiting for host…" if pending else "Service ready", "network"))')
s=swap(s,'\tvar close:=Button.new();close.text="Close";close.pressed.connect(func():hide());body.add_child(close)', '\tbody.add_child(UI.action("Close", "close", hide))')
s=swap(s,'if entry.venue==venue:button("%s • $%d"%[entry.name,entry.price],{"op":"buy","station":station_id,"item":item})', 'if entry.venue==venue:\n\t\t\t\tvar card := UI.card(str(entry.name), "$%d • Available here"%entry.price, "cart")\n\t\t\t\tcard.get_node("Content/Copy/Rarity").hide()\n\t\t\t\tbody.add_child(card)\n\t\t\t\tbutton("Buy %s • $%d"%[entry.name,entry.price],{"op":"buy","station":station_id,"item":item})')
out[p]=s

p='scripts/campus/performance/profiling_overlay.gd';s=src[p].replace('extends CanvasLayer\n','extends CanvasLayer\n'+IMPORTS,1)
s=swap(s,'\t_label = Label.new()', '\t_label = Label.new()\n\t_label.theme = Skin.create()\n\t_label.add_theme_stylebox_override("normal", Skin.card_style())\n\t_label.add_theme_font_size_override("font_size", 14)')
out[p]=s

manifest=[]
for p in OWNED:
    assert (ROOT/p).read_bytes()==raw[p], f'Concurrent modification: {p}'
    data=out[p].replace('\n','\r\n').encode('utf-8')
    backup=BACKUP/(p.replace('/','__')+'.preimage')
    assert not backup.exists(), f'Already migrated: {p}'
    backup.write_bytes(raw[p])
    manifest.append({'path':p,'before':hashlib.sha256(raw[p]).hexdigest(),'after':hashlib.sha256(data).hexdigest(),'preimage':str(backup.relative_to(ROOT))})
for entry in manifest:
    p=entry['path']
    assert (ROOT/p).read_bytes()==raw[p], f'Concurrent modification: {p}'
    (ROOT/p).write_bytes(out[p].replace('\n','\r\n').encode('utf-8'))
(BACKUP/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'written':len(manifest),'manifest':str(BACKUP/'manifest.json')}))
