from pathlib import Path
import hashlib
import json
ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT/'scripts/ui/hud_settings/review/manifest.json'
manifest=json.loads(MANIFEST.read_text())
raw={e['path']:(ROOT/e['path']).read_bytes() for e in manifest}
for e in manifest:
    assert hashlib.sha256(raw[e['path']]).hexdigest()==e['after'], f"Concurrent modification: {e['path']}"
src={p:b.decode().replace('\r\n','\n') for p,b in raw.items()}
out=dict(src)
def swap(s,a,b):
    assert s.count(a)==1,(a,s.count(a))
    return s.replace(a,b)

p='scripts/lab_ui.gd';s=src[p]
s=swap(s,'var records_label: Label','var records_label: Label\nvar records_body: VBoxContainer\nvar roster_body: VBoxContainer')
s=swap(s,'\tvar node := Label.new()','\tvar node := preload("res://scripts/ui/hud_settings/readout.gd").new() if parent == self and text != "·" else Label.new()')
s=swap(s,'\tvar experiment_card := Layout.section(lobby, "Experiment setup", "Host controls • applies through the existing session request", "circuit")\n\trow = Layout.flow(lobby)', '\troster_body = VBoxContainer.new()\n\tteam_card.add_child(roster_body)\n\trow = Layout.flow(team_card)')
s=swap(s,'\tmodes = OptionButton.new()', '\tvar experiment_card := Layout.section(lobby, "Experiment setup", "Host controls • applies through the existing session request", "circuit")\n\tmodes = OptionButton.new()')
s=swap(s,'\trow = Layout.flow(lobby)\n\tlabel("Experiment seed",row,14)', '\trow = Layout.flow(experiment_card)\n\tlabel("Experiment seed",row,14)')
s=swap(s,'\trow.add_child(seed_input)', '\tseed_input.custom_minimum_size.y = 44\n\trow.add_child(seed_input)')
s=swap(s,'\tnote.modulate = Color("a8b9ba")', '\tnote.theme_type_variation = "MutedLabel"\n\tnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART')
s=swap(s,'\tcontrols_card.add_child(slider)', '\tslider.custom_minimum_size.y = 36\n\tcontrols_card.add_child(slider)')
s=swap(s,'\tcontrols_card.add_child(bob)', '\tbob.custom_minimum_size.y = 44\n\tcontrols_card.add_child(bob)')
s=swap(s,'\tcontrols_card.add_child(assists)', '\tassists.custom_minimum_size.y = 44\n\tcontrols_card.add_child(assists)')
s=swap(s,'\trecords_label.custom_minimum_size = Vector2(0,260)', '\trecords_body = VBoxContainer.new()\n\trecord_card.add_child(records_body)')
a=s.index('\t\tvar input := LineEdit.new()',s.index('for key in ["v","i","p"]'))
b=s.index('\t\trow.add_child(field)',a)
s=s[:a]+'''\t\tvar field := UI.field({"v":"Voltage · V RMS","i":"Current · A RMS","p":"Real power · W"}[key], {"v":"Measured V RMS","i":"Measured A RMS","p":"Total watts (W1 + W2)"}[key])
\t\tfield.custom_minimum_size.x = 190
\t\tvar input := field.get_node("Input") as LineEdit
'''+s[b:]
s=swap(s,'\thud.add_theme_stylebox_override("normal", Skin.card_style())', '\thud.add_theme_stylebox_override("normal", Skin.card_style())\n\thud.icon_key = "switch"\n\tobjective.icon_key = "course"\n\tprompt.icon_key = "play"\n\tlog_label.icon_key = "info"')
s=swap(s,'\tobjective.position = Vector2(28, 78)', '\thud.position = Vector2(52, 24)\n\tobjective.position = Vector2(52, 88)')
s=swap(s,'objective.custom_minimum_size.x = minf(580, area.x - 56)', 'objective.custom_minimum_size.x = minf(580, area.x - 80)')
s=swap(s,'log_label.position = Vector2(28, area.y - 100)', 'log_label.position = Vector2(52, area.y - 112)')
a=s.index('\trecords_label.text = "PERSONAL LAB RECORD')
b=s.index('\nfunc update_roster()',a)
s=s[:a]+'''\trecords_label.text = "%d XP • %d experiment records" % [xp,best.size()]
\tfor child in records_body.get_children():
\t\trecords_body.remove_child(child); child.queue_free()
\trecords_body.add_child(UI.badge("Accurate measurements earned" if perfect else "Earn 100/100 to unlock Accurate measurements", "check" if perfect else "course"))
\trecords_body.add_child(UI.text("Personal bests improve XP once per mode / task / seed. All training equipment remains available in Free Laboratory.", "MutedLabel"))
\tif history.is_empty():
\t\trecords_body.add_child(UI.text("No submissions yet. Complete an experiment to start your record.", "MutedLabel"))
\tfor i in range(maxi(0,history.size()-5),history.size()):
\t\tvar item: Dictionary = history[i]
\t\tvar card := UI.card(str(item.mode), "Seed %s • %s/100" % [str(item.seed),str(item.result).get_slice("/",0)], "course")
\t\tcard.get_node("Content/Copy/Rarity").hide()
\t\trecords_body.add_child(card)
'''+s[b:]
a=s.index('\troster_label.text = "PLAYERS')
b=s.index('\nfunc log_message',a)
s=s[:a]+'''\troster_label.text = "%d players in this session" % game.session.roster.size()
\tfor child in roster_body.get_children():
\t\troster_body.remove_child(child); child.queue_free()
\tfor id in game.session.roster:
\t\tvar entry: Dictionary = game.session.roster[id]
\t\tvar card := UI.card(str(entry.name), ("Ready" if entry.ready else "Waiting") + (" • Host" if id==1 else ""), "check" if entry.ready else "network")
\t\tcard.get_node("Content/Copy/Rarity").hide()
\t\troster_body.add_child(card)
'''+s[b:]
out[p]=s

p='scripts/campus/facilities/facility_panel.gd';s=src[p]
s=swap(s,'var pending:=false','var pending:=false\nvar service_actions: Array[Button]=[]')
s=swap(s,'\t\tcontroller.request(value)\n\t\tredraw())','\t\tstatus.text="Waiting for campus host…"\n\t\tfor action in service_actions: action.disabled=true\n\t\tcontroller.request(value))')
s=swap(s,'\tbody.add_child(node)\n', '\tservice_actions.append(node)\n\tbody.add_child(node)\n')
s=swap(s,'func redraw() -> void:\n', 'func redraw() -> void:\n\tservice_actions.clear()\n')
out[p]=s

p='scripts/campus/ui/profile_inspector.gd';s=src[p]
s=swap(s,'\t\tbox.add_child(UI.card("Private profile", "This player has not shared additional fields.", "lock"))', '\t\tvar private_card := UI.card("Private profile", "This player has not shared additional fields.", "lock")\n\t\tprivate_card.get_node("Content/Copy/Rarity").hide()\n\t\tbox.add_child(private_card)')
out[p]=s

p='scripts/campus/ui/campus_hud.gd';s=src[p]
s=swap(s,'label.autowrap_mode=TextServer.AUTOWRAP_OFF', 'label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART\n\t\tlabel.custom_minimum_size.x=minf(240,get_viewport_rect().size.x-160)\n\t\tlabel.tooltip_text=""')
s=swap(s,'\t\tlabel.get_parent().get_parent().visible=not label.text.is_empty()', '\t\tlabel.get_parent().get_parent().visible=not label.text.is_empty()\n\t\tlabel.tooltip_text=label.text')
out[p]=s

for e in manifest:
    p=e['path'];data=out[p].replace('\n','\r\n').encode()
    assert (ROOT/p).read_bytes()==raw[p],f'Concurrent modification: {p}'
    (ROOT/p).write_bytes(data)
    e['after']=hashlib.sha256(data).hexdigest()
MANIFEST.write_text(json.dumps(manifest,indent=2)+'\n')
print('Refined layouts; preimage hashes retained and final hashes updated.')
