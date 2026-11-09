"""Preimage-bound, reversible source migration. No engine invocation."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FILES = ['scripts/dc_ui.gd', 'scripts/dc_scope/scope_panel.gd']
original = {f: (ROOT/f).read_bytes() for f in FILES}
sources = {f: b.decode('utf-8').replace('\r\n', '\n') for f,b in original.items()}

def change(file, old, new):
    assert old in sources[file], (file, old)
    sources[file] = sources[file].replace(old,new)

d, s = FILES
imports = '\nconst UI = preload("res://scripts/ui/design_system/widgets.gd")\nconst Skin = preload("res://scripts/ui/design_system/theme.gd")\nconst Layout = preload("res://scripts/ui/instrument_panels/layout.gd")\n'
change(d,'extends CanvasLayer\n','extends CanvasLayer'+imports)
change(d,'var current_source_readout: Label','var current_source_readout: Label\nvar master_button: Button\nvar channel_inputs: Array[SpinBox] = []\nvar source_readouts: Array[Label] = []')
change(d,'\tvar skin := StyleBoxFlat.new();skin.bg_color=Color("10222c");skin.set_corner_radius_all(12);skin.set_content_margin_all(20);screen.add_theme_stylebox_override("panel",skin)','\tscreen.theme=Skin.create()')
change(d,'\tvar b := Button.new();b.text=label;b.custom_minimum_size.y=34;b.pressed.connect(callback);parent.add_child(b);return b','\tvar key := "switch" if "output" in label.to_lower() else "circuit" if "lead" in label.to_lower() else UI.action_icon(label)\n\tvar b := UI.action(label,key,callback);parent.add_child(b);return b')
change(d,'\tvar l := Label.new();l.text=value;parent.add_child(l);return l','\tvar l := UI.text(value);parent.add_child(l);return l')
a=sources[d].index('func number('); b=sources[d].index('func choice(',a)
sources[d]=sources[d][:a]+'''func number(parent: Node,name: String,value: float,minimum: float,maximum: float,increment: float,callback: Callable) -> SpinBox:
	var spin := Layout.number(parent,name,value,minimum,maximum,increment)
	spin.value_changed.connect(callback)
	return spin
'''+sources[d][b:]
change(d,'var option := OptionButton.new()','var option := OptionButton.new();option.custom_minimum_size.y=44;option.size_flags_horizontal=Control.SIZE_EXPAND_FILL')
change(d,'\tchannels_text.clear()','\tchannels_text.clear();channel_inputs.clear();source_readouts.clear()')
a=sources[d].index('\tvar top := HBoxContainer.new()'); b=sources[d].index('\tnotice=label',a)
sources[d]=sources[d][:a]+'''\tcolumn.add_child(UI.header("DC lab · Station %02d"%(index+1),"Bench instruments · isolated supplies, measurements and leads",close))
'''+sources[d][b:]
change(d,'\tbutton(supply,"Master output ON / OFF",func():send({"op":"master"}))','\tmaster_button=button(supply,"Master output",func():send({"op":"master"}))')
for var,title,icon in [('supply','Power supply','switch'),('current','Current source','circuit'),('meter_tab','Multimeter','search'),('gen','Function generator','settings'),('osc','Oscilloscope','circuit')]:
    change(d,f'var {var} := VBoxContainer.new();{var}.name="{title}";tabs.add_child({var})',f'var {var} := Layout.page(tabs,"{title}","{icon}")')
change(d,'var columns := HBoxContainer.new();supply.add_child(columns)','var columns := Layout.grid(supply)')
change(d,'var c := VBoxContainer.new();c.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(c)\n\t\tlabel(c,"CHANNEL %d · isolated"%(i+1))','var c := Layout.section(columns,"Channel %d"%(i+1),"Isolated · CH%d+ / CH%d−"%[i+1,i+1],"switch")')
change(d,'\t\tnumber(c,"Voltage · V",','\t\tvar voltage_input := number(c,"Voltage · V",')
change(d,'\t\tnumber(c,"Current limit · A",','\t\tchannel_inputs.append(voltage_input)\n\t\tnumber(c,"Current limit · A",')
change(d,';open(station))', ';voltage_input.set_value_no_signal(voltage)))')
change(d,'var current_columns := HBoxContainer.new();current.add_child(current_columns)','var current_columns := Layout.grid(current,280,4)')
change(d,'var source_column := VBoxContainer.new();source_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;current_columns.add_child(source_column)','var source_column := Layout.section(current_columns,"Source %d"%(source_index+1),"Independent current regulator","circuit")\n\t\tsource_readouts.append(label(source_column,""))')
change(d,'\treadout=label(meter_tab,"")','\tmeter_tab=Layout.section(meter_tab,"Digital multimeter","Live reading · VΩ / A / COM","search")\n\treadout=label(meter_tab,"")')
change(d,'choice(meter_tab,["DC V"','choice(Layout.selector(meter_tab,"Measurement mode"),["DC V"')
change(d,'choice(meter_tab,ranges,','choice(Layout.selector(meter_tab,"Full-scale range · V / A"),ranges,')
change(d,'\tvar en := CheckButton.new()','\tgen=Layout.section(gen,"Signal output","GEN / REF · open-circuit peak amplitude","settings")\n\tvar en := CheckButton.new()')
change(d,'choice(gen,["Sine"','choice(Layout.selector(gen,"Waveform"),["Sine"')
change(d,'var leads := HBoxContainer.new();leads.name="Leads & components";tabs.add_child(leads)\n\tvar tools := VBoxContainer.new();leads.add_child(tools)\n\tlabel(tools,"Connect two terminals")','var leads := Layout.page(tabs,"Leads & components","circuit")\n\tvar tools := Layout.section(leads,"Patch leads","Choose source and destination terminals","circuit")')
change(d,'wire_a=choice(tools,ports,"CH1+",func(_v):pass);wire_b=choice(tools,ports,"R1a",func(_v):pass)','wire_a=choice(Layout.selector(tools,"From terminal"),ports,"CH1+",func(_v):pass);wire_b=choice(Layout.selector(tools,"To terminal"),ports,"R1a",func(_v):pass)')
change(d,'wiring.custom_minimum_size.x=350','wiring.custom_minimum_size=Vector2(0,180)')
change(d,'leads.add_child(wiring)','Layout.section(leads,"Connected leads","Select a lead to remove it","network").add_child(wiring)')
change(d,'\trefresh()\nfunc refresh()', '\trefresh()\n\tmaster_button.call_deferred("grab_focus")\nfunc refresh()')
change(d,'\t\tcurrent_source_readout.text="\\n".join(source_lines)','\t\tcurrent_source_readout.text="Live source measurements · master-controlled outputs"\n\t\tfor i in source_readouts.size():source_readouts[i].text=source_lines[i]')
change(d,'\treadout.text=data.meter','\tmaster_button.text="Master output · ON" if data.get("master",false) else "Master output · OFF"\n\tmaster_button.theme_type_variation="PrimaryButton" if data.get("master",false) else "Button"\n\tfor i in channel_inputs.size():\n\t\tif not channel_inputs[i].get_line_edit().has_focus():channel_inputs[i].set_value_no_signal(float(data.channels[i].voltage))\n\treadout.text=data.meter')
change(d,'\tif not result.get("ok",true):notice.text=result.get("error","Solve failed")','\tnotice.text="Connect terminals in Leads & components. Master controls supplies and current sources; generator has its own output switch." if result.get("ok",true) else str(result.get("error","Solve failed"))\n\tnotice.theme_type_variation="MutedLabel" if result.get("ok",true) else "ErrorLabel"')
change(s,'extends VBoxContainer\n','extends VBoxContainer'+imports)
change(s,'theme=preload("res://scripts/campus/ui/campus_theme.gd").create()','theme=Skin.create()')
change(s,'var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation",18); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(columns)','var columns := Layout.grid(self,420,2); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL')
change(s,'var view := VBoxContainer.new(); view.size_flags_horizontal=Control.SIZE_EXPAND_FILL; columns.add_child(view)','var view := Layout.section(columns,"Waveform monitor","CH1 · gold   /   CH2 · cyan · shared time axis","circuit"); view.size_flags_vertical=Control.SIZE_EXPAND_FILL')
change(s,'scroll.custom_minimum_size.x=340','scroll.custom_minimum_size=Vector2(0,340); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL')
change(s,'\t_label(settings_box,"ACQUISITION · shared time axis")','\tsettings_box=Layout.section(settings_box,"Acquisition","Run, trigger and timebase","settings")')
change(s,'var actions := HBoxContainer.new()','var actions := HFlowContainer.new()')
change(s,'\tfor index in 2:\n\t\tvar channel: Dictionary=config.channels[index]','\tvar channel_parent := settings_box\n\tfor index in 2:\n\t\tsettings_box=Layout.section(channel_parent,"Channel %d"%(index+1),"S%d / common GND"%(index+1),"circuit")\n\t\tvar channel: Dictionary=config.channels[index]')
change(s,'var button := Button.new(); button.text=value; button.custom_minimum_size.y=38; parent.add_child(button); button.pressed.connect(callback); return button','var button := UI.action(value,"play" if value in ["Run","Single"] else "settings" if value=="Autoset" else "switch",callback); parent.add_child(button); return button')
old='\tvar row := HBoxContainer.new(); parent.add_child(row)\n\tvar label := _label(row,caption); label.custom_minimum_size.x=165\n\tvar spin := SpinBox.new(); spin.name="CH%d_%s"%[channel+1,key] if channel>=0 else "Scope_"+key; spin.min_value=minimum; spin.max_value=maximum; spin.step=step; spin.set_value_no_signal(value); spin.editable=enabled; spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(spin)'
change(s,old,'\tvar spin := Layout.number(parent,caption,value,minimum,maximum,step)\n\tspin.name="CH%d_%s"%[channel+1,key] if channel>=0 else "Scope_"+key; spin.editable=enabled')
change(s,'\tvar row := HBoxContainer.new(); parent.add_child(row)\n\tvar label := _label(row,caption); label.custom_minimum_size.x=165','\tvar row := Layout.selector(parent,caption)')
change(s,'option.size_flags_horizontal=Control.SIZE_EXPAND_FILL','option.size_flags_horizontal=Control.SIZE_EXPAND_FILL; option.custom_minimum_size.y=44')
change(s,'\trun_button.text="Stop" if settings.running else "Run"','\trun_button.text="Stop" if settings.running else "Run"\n\trun_button.icon=UI.icon("switch" if settings.running else "play")\n\tstatus_label.theme_type_variation="ErrorLabel" if not data.get("result",{}).get("ok",true) or not str(probe.get("warning","")).is_empty() else "MutedLabel"')

manifest = []
for file in FILES:
    before = original[file]
    after = sources[file].encode('utf-8')
    assert (ROOT/file).read_bytes() == before, f'Concurrent change: {file}'
    backup = HERE / (Path(file).name + '.preimage')
    assert not backup.exists(), f'Backup already exists: {backup}'
    backup.write_bytes(before)
    (ROOT/file).write_bytes(after)
    manifest.append(dict(file=file, preimage_sha256=hashlib.sha256(before).hexdigest(), new_sha256=hashlib.sha256(after).hexdigest(), backup=str(backup.relative_to(ROOT))))
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
