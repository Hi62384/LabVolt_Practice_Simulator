from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3]
here=Path(__file__).resolve().parent
manifest=json.loads((here/'manifest.json').read_text())
updates={}
for item in manifest:
    path=root/item['file']; before=path.read_bytes()
    assert hashlib.sha256(before).hexdigest()==item['new_sha256'], 'Concurrent change'
    text=before.decode()
    if path.name=='dc_ui.gd':
        text=text.replace('voltage_input.set_value_no_signal(voltage)))','voltage_input.set_value_no_signal(voltage))')
        text=text.replace('var source_readouts: Array[Label] = []','var source_readouts: Array[Label] = []\nvar live_controls: Array = []')
        text=text.replace('source_readouts.clear()','source_readouts.clear();live_controls.clear()')
        text=text.replace('for s in values:option.add_item(s)','for s in values:\n\t\toption.add_item(s);option.set_item_metadata(option.item_count-1,s)')
        lines=text.splitlines()
        revised=[]
        for line in lines:
            # Retain exact callbacks/ranges while registering snapshot projection paths.
            paths=[]
            if line.startswith('\t\tnumber(c,"Current limit'): paths=['channels','i','limit']
            elif line.startswith('\t\tnumber(source_column,"Setpoint'): paths=['current_sources','source_index','current']
            elif line.startswith('\t\tnumber(source_column,"Compliance'): paths=['current_sources','source_index','compliance']
            elif line.startswith('\t\tnumber(gen,spec'): paths=['generator','spec[0]']
            elif line.startswith('\tnumber(tools,"Capacitor'): paths=['capacitance']
            if paths:
                prefix=line[:len(line)-len(line.lstrip())]
                expr=line.strip()
                if paths==['capacitance']:
                    line=prefix+'_watch('+expr+',["capacitance"],1e6)'
                else:
                    def literal(p): return p if p in ['i','source_index','spec[0]'] else json.dumps(p)
                    line=prefix+'_watch('+expr+',['+','.join(literal(p) for p in paths)+'])'
            if line.startswith('\tfor i in range(2):number(tools,'):
                line=line.replace(':number(tools,',':_watch(number(tools,')+',["resistance",i])'
            revised.append(line)
            if 'channel_inputs.append(voltage_input)' in line: revised.append('\t\t_watch(voltage_input,["channels",i,"voltage"])')
            if 'enabled.toggled.connect' in line and '"op":"channel"' in line: revised.append('\t\t_watch(enabled,["channels",i,"enabled"])')
            if 'source_enabled.toggled.connect' in line: revised.append('\t\t_watch(source_enabled,["current_sources",source_index,"enabled"])')
            if 'en.toggled.connect' in line and '"op":"generator"' in line: revised.append('\t_watch(en,["generator","enabled"])')
        text='\n'.join(revised)+'\n'
        text=text.replace('choice(Layout.selector(meter_tab,"Measurement mode"),','var meter_mode_control := choice(Layout.selector(meter_tab,"Measurement mode"),')
        text=text.replace('\tlabel(meter_tab,"VΩ + COM:', '\t_watch(meter_mode_control,["meter_mode"])\n\tlabel(meter_tab,"VΩ + COM:')
        text=text.replace('choice(Layout.selector(gen,"Waveform"),','var waveform_control := choice(Layout.selector(gen,"Waveform"),')
        text=text.replace('\tfor spec in [["frequency"','\t_watch(waveform_control,["generator","wave"])\n\tfor spec in [["frequency"')
        text=text.replace('\tfor i in channel_inputs.size():\n\t\tif not channel_inputs[i].get_line_edit().has_focus():channel_inputs[i].set_value_no_signal(float(data.channels[i].voltage))','\t_sync_controls(data)')
        text+='''
func _watch(control: Control, path: Array, multiplier := 1.0) -> void:
	live_controls.append({"control":control,"path":path,"multiplier":multiplier})

func _sync_controls(data: Dictionary) -> void:
	for entry in live_controls:
		var control: Control=entry.control
		var value: Variant=data
		for key in entry.path:value=value[key]
		if control is SpinBox:
			if not control.get_line_edit().has_focus():control.set_value_no_signal(float(value)*float(entry.multiplier))
		elif control is CheckButton:control.set_pressed_no_signal(bool(value))
		elif control is OptionButton and not control.has_focus():
			for i in control.item_count:
				if control.get_item_metadata(i)==value:control.select(i);break
'''
    else:
        text=text.replace('Layout.grid(self,420,2)','Layout.grid(self,480,2)')
        text=text.replace('var settings_box := VBoxContainer.new(); settings_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;', 'var settings_box := VBoxContainer.new(); settings_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;')
        text=text.replace('settings_box=Layout.section(settings_box,"Acquisition"','var settings_root := settings_box\n\tsettings_box=Layout.section(settings_root,"Acquisition"')
        text=text.replace('var channel_parent := settings_box','var channel_parent := settings_root')
        text=text.replace('\t_label(settings_box,"Direct leads:', '\t_label(settings_root,"Direct leads:')
    updates[item['file']]=(before,text.encode())
for item in manifest:
    before,after=updates[item['file']]
    path=root/item['file']
    assert path.read_bytes()==before
    (here/(path.name+'.revision1')).write_bytes(before)
    item['revision1_sha256']=item['new_sha256']
    path.write_bytes(after)
    item['new_sha256']=hashlib.sha256(after).hexdigest()
(here/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Refined layouts and authoritative control projections; exact revision backups saved.')
