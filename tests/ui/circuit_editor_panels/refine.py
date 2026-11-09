from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
manifest = json.loads((HERE / 'manifest.json').read_text())

def revise(path, replacements):
    target = ROOT / path
    before = target.read_bytes()
    entry = next(e for e in manifest if e['path'] == path)
    assert hashlib.sha256(before).hexdigest() == entry['after_sha256'], f'Concurrent edit: {path}'
    text = before.decode().replace('\r\n', '\n')
    for old, new in replacements:
        assert text.count(old) == 1, (path, old)
        text = text.replace(old, new)
    assert target.read_bytes() == before
    data = text.replace('\n','\r\n').encode()
    target.write_bytes(data)
    entry['after_sha256'] = hashlib.sha256(data).hexdigest()

revise('scripts/package_editor/package_form.gd', [
    ('\tvar label := Label.new();label.text=title;parent.add_child(label)\n\tvar field := SpinBox.new();field.min_value=minimum;field.max_value=maximum;field.step=step_size;field.value=value;field.custom_minimum_size.x=90;parent.add_child(field);return field',
     '\tvar field := SpinBox.new();field.min_value=minimum;field.max_value=maximum;field.step=step_size;field.value=value;field.custom_minimum_size.x=90;parent.add_child(field);Chrome.labeled(field,title);return field'),
    ('\tnote("Expose individual IC surface devices.', '\tvar exposed_start := get_child_count()\n\tnote("Expose individual IC surface devices.'),
    ('\tvar tools := HFlowContainer.new();add_child(tools)', '\tChrome.section(self,"Surface controls", "switch", get_child(exposed_start), get_child(get_child_count()-1))\n\tvar tools := HFlowContainer.new();add_child(tools)'),
    ('\t\tvar row := HFlowContainer.new();list.add_child(row);row.visible=index<int(count.value)',
     '\t\tvar pin_card := PanelContainer.new();pin_card.theme_type_variation="CardPanel";pin_card.visible=index<int(count.value);list.add_child(pin_card)\n\t\tvar row := HFlowContainer.new();pin_card.add_child(row)'),
    ('\t\taction(row,"Move up",', '\t\taction(row,"Move pin up",'),
    ('\t\taction(row,"Move down",', '\t\taction(row,"Move pin down",'),
    ('\tChrome.finish(self)\n\taction(self,"Save circuit package",',
     '\tvar result := Label.new();result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.text="Ready to validate and save package.";add_child(result)\n\tChrome.finish(self)\n\taction(self,"Save circuit package",'),
    ('\t\tsaved.emit(preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pin_map))',
     '\t\tvar message: String=preload("res://scripts/package_editor/package_store.gd").save_package(profile,options,pin_map)\n\t\tresult.text=message\n\t\tsaved.emit(message)')
])

revise('scripts/firmware_backends/native_ide.gd', [
    ('\tadd_child(help)\n', '\tadd_child(help)\n\tvar guide := CheckButton.new();guide.text="Workflow and compatibility guide";add_child(guide);move_child(guide,help.get_index());help.visible=false;guide.toggled.connect(func(on):help.visible=on)\n'),
    ('var row := HBoxContainer.new();add_child(row);var explanation', 'var row := HFlowContainer.new();add_child(row);var explanation'),
    ('\tChrome.section(self,"Source workspace",', '\tChrome.section(self,"Board pin reference", "chip", pin_help, pin_help)\n\tChrome.section(self,"Source workspace",'),
    ('\tsource_tabs=TabContainer.new();source_tabs.custom_minimum_size.y=180;', '\tsource_tabs=TabContainer.new();source_tabs.custom_minimum_size.y=320;')
])

revise('scripts/firmware_ide.gd', [
    ('\tui.label(self,"One instruction per line;', '\tvar guide := CheckButton.new();guide.text="Language and wiring reference";add_child(guide)\n\tvar reference := ui.label(self,"One instruction per line;'),
    ('Connect a resistor in series with each LED.")\n', 'Connect a resistor in series with each LED.")\n\treference.visible=false;guide.toggled.connect(func(on):reference.visible=on)\n')
])

(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Refined pin cards, local package feedback and optional reference guides.')
