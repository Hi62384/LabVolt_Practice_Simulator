from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3]; here=Path(__file__).resolve().parent
manifest=json.loads((here/'manifest.json').read_text())
for item in manifest:
    path=root/item['file']; before=path.read_bytes()
    assert hashlib.sha256(before).hexdigest()==item['new_sha256'],'Concurrent source edit'
    text=before.decode('utf-8')
    if path.name=='dc_ui.gd':
        text=text.replace('var live_controls: Array = []','var live_controls: Array = []\nvar wire_snapshot: Array = []\nvar remove_lead: Button')
        text=text.replace('source_readouts.clear();live_controls.clear()','source_readouts.clear();live_controls.clear();wire_snapshot.clear()')
        text=text.replace('channels_text.append(label(c,""))','var channel_readout := label(c,"");channel_readout.add_theme_font_size_override("font_size",24);channels_text.append(channel_readout)')
        text=text.replace('choice(Layout.selector(meter_tab,"Full-scale range · V / A"),','var range_control := choice(Layout.selector(meter_tab,"Full-scale range · V / A"),')
        text=text.replace('\tlabel(meter_tab,"Manual full-scale range', '\t_watch(range_control,["meter_range"])\n\tlabel(meter_tab,"Manual full-scale range')
        text=text.replace('\tbutton(tools,"Remove selected lead",','\tremove_lead=button(tools,"Remove selected lead",')
        text=text.replace('\tbutton(tools,"Disconnect all / outputs off",func():send({"op":"clear"}))','\tbutton(tools,"Disconnect all / outputs off",func():send({"op":"clear"})).theme_type_variation="DangerButton"')
        old='\tvar selected := wiring.get_selected_items();wiring.clear()\n\tfor wire in data.wires:wiring.add_item("%s  →  %s"%wire)\n\tif selected.size()>0 and selected[0]<wiring.item_count:wiring.select(selected[0])'
        new='''\tif data.wires!=wire_snapshot:
		var selected := wiring.get_selected_items();wiring.clear()
		for wire in data.wires:wiring.add_item("%s  →  %s"%wire)
		if selected.size()>0 and selected[0]<wiring.item_count:wiring.select(selected[0])
		wire_snapshot=data.wires.duplicate(true)
	remove_lead.disabled=wiring.get_selected_items().is_empty()
	wiring.tooltip_text="No leads connected. Choose two terminals and attach a lead." if data.wires.is_empty() else "Select a connected lead, then choose Remove selected lead."
'''.rstrip()
        assert old in text; text=text.replace(old,new)
        text=text.replace('if control.get_item_metadata(i)==value:control.select(i);break','var target: Variant=control.get_item_metadata(i)\n\t\t\t\tif entry.path==["meter_range"]:target=0.0 if target=="Auto" else float(target)\n\t\t\t\tif target==value:control.select(i);break')
    else:
        text=text.replace('or not str(probe.get("warning","")).is_empty() else "MutedLabel"','or not str(probe.get("warning","")).is_empty() or not str(status.get("warning","")).is_empty() or false in connected else "MutedLabel"')
    after=text.encode('utf-8')
    assert path.read_bytes()==before
    (here/(path.name+'.revision2')).write_bytes(before)
    item['revision2_sha256']=item['new_sha256']; path.write_bytes(after)
    item['new_sha256']=hashlib.sha256(after).hexdigest()
(here/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Shared-file changes are staged, never applied over another owner's edits.
shared=root/'scripts/electronics_ui.gd'; raw=shared.read_bytes(); text=raw.decode('utf-8').replace('\r\n','\n')
old='\tbutton(tools,"Interact with I/O",func():canvas.selected_type="interact")'
assert old in text
hook={'file':'scripts/electronics_ui.gd','observed_file_sha256':hashlib.sha256(raw).hexdigest(),'apply_policy':'Owner reviews and applies only if exact old snippet still matches; do not overwrite whole shared file. No patch applied.','old':old,'new':'\tvar io_action := button(tools,"Interact with I/O",func():canvas.selected_type="interact")\n\tpreload("res://scripts/ui/design_system/widgets.gd").style_button(io_action,"switch")\n\tio_action.tooltip_text="Operate the selected device controls on this board. Direct gestures retain the device command/acknowledgment path."'}
(here/'shared_device_hook.json').write_text(json.dumps(hook,indent=2)+'\n',encoding='utf-8')
item={'file':'scripts/ui/instrument_panels/layout.gd','preimage_sha256':None,'new_sha256':hashlib.sha256((root/'scripts/ui/instrument_panels/layout.gd').read_bytes()).hexdigest(),'backup':None,'kind':'new helper'}
(here/'helper_manifest.json').write_text(json.dumps(item,indent=2)+'\n')
print('Saved final hashes, guarded revisions and unapplied shared device hook.')
