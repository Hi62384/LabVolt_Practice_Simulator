"""One-shot exact-preimage migration. No engine, user data or external services."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
paths = ['scripts/firmware_ide.gd', 'scripts/firmware_backends/native_studio.gd', 'scripts/firmware_backends/native_ide.gd', 'scripts/package_editor/package_form.gd', 'scripts/pcb_design/editor.gd']
before = {p: (ROOT / p).read_bytes() for p in paths}
texts = {p: data.decode('utf-8').replace('\r\n', '\n') for p, data in before.items()}

def replace(p, old, new):
    assert texts[p].count(old) == 1, (p, old)
    texts[p] = texts[p].replace(old, new)

for p in paths:
    replace(p, 'extends VBoxContainer\n', 'extends VBoxContainer\nconst Chrome = preload("res://scripts/ui/circuit_editor_panels/chrome.gd")\n')

p = paths[0]
replace(p, '\tui=studio;kit_id=', '\tChrome.setup(self)\n\tui=studio;kit_id=')
replace(p, '\tui.label(self,"LV MICRO / PROGRAMMING STUDIO")', '\tChrome.heading(self,"LV Micro · programming", "Write → validate → upload → run", "chip")')
texts[p] = texts[p].replace('ui.button(', 'Chrome.action(').replace('HBoxContainer.new()', 'HFlowContainer.new()')
replace(p, 'Vector2(850,360)', 'Vector2(280,360)')
replace(p, '\tload_source()\nfunc kit()', '''	Chrome.labeled(picker,"Target LV Micro")
	Chrome.labeled(examples,"Insert template")
	Chrome.labeled(find,"Find in active file")
	Chrome.labeled(replacement,"Replacement text")
	Chrome.labeled(file_name,"New project filename")
	Chrome.section(self,"Device and deployment", "chip", choices, actions)
	Chrome.section(self,"Search and project files", "search", searchbar, file_actions)
	Chrome.section(self,"Source editor", "circuit", file_tabs, parameter_hint)
	Chrome.section(self,"Validation and serial output", "info", notice, monitor)
	Chrome.finish(self)
	load_source()
func kit()''')

p = paths[1]
replace(p, ' ui=studio;kit_id=', ' Chrome.setup(self)\n Chrome.heading(self,"Native board · target", "Select a placed board to edit its source and compiled image.", "chip")\n ui=studio;kit_id=')
replace(p, ' select(picker.get_item_metadata(0))\nfunc select', ' Chrome.labeled(picker,"Target native board")\n Chrome.finish(self)\n select(picker.get_item_metadata(0))\nfunc select')

p = paths[2]
replace(p, '\tvar item := Button.new();item.custom_minimum_size.y=34;item.text=text;item.pressed.connect(action);parent.add_child(item)', '\tChrome.action(parent,text,action)')
start = texts[p].index('\tvar skin := Theme.new();', texts[p].index('func apply_studio_theme'))
end = texts[p].index('\nfunc active_editor()', start)
texts[p] = texts[p][:start] + '\tChrome.setup(self)\n' + texts[p][end:]
replace(p, 'var add_bar := HBoxContainer.new()', 'var add_bar := HFlowContainer.new()')
replace(p, '\tcompile_button=Button.new();compile_button.text="Compile source";compile_button.custom_minimum_size.y=34;compile_button.pressed.connect(compile_sources);compile_bar.add_child(compile_button)', '\tcompile_button=Chrome.action(compile_bar,"Compile source",compile_sources)')
replace(p, '\tsource_map=Document.load_compiler_map', '''	Chrome.labeled(file_name,"New source filename")
	Chrome.labeled(find,"Find in active source")
	Chrome.labeled(replace,"Replacement text")
	Chrome.labeled(address,"Instruction breakpoint · byte PC")
	Chrome.labeled(serial_input,"UART0 input · byte")
	Chrome.section(self,"Source workspace", "circuit", source_tabs, search)
	Chrome.section(self,"Build and diagnostics", "chip", compile_bar, diagnostic_list)
	Chrome.section(self,"Compiled image and deployment", "save", label, actions)
	Chrome.section(self,"Debug and serial controls", "settings", debug_bar, debug_output)
	Chrome.finish(self)
	source_map=Document.load_compiler_map''')

p = paths[3]
replace(p, '\tvar button := Button.new();button.text=title;button.pressed.connect(callback);parent.add_child(button)', '\tChrome.action(parent,title,callback)')
replace(p, '\tvar design: Dictionary=', '\tChrome.setup(self)\n\tChrome.heading(self,"Circuit package", "Define its body, exposed controls and stable external pin map.", "chip")\n\tvar design: Dictionary=')
# Field wrappers retain the original LineEdit/OptionButton instances used by save.
replace(p, '\tvar exposed: Array=', '''	Chrome.labeled(kind,"Package type")
	Chrome.labeled(title,"Circuit name")
	Chrome.labeled(description,"Description")
	Chrome.labeled(marking,"Surface marking")
	Chrome.labeled(marker,"Orientation marker")
	Chrome.labeled(color,"Body color")
	Chrome.section(self,"Body and identity", "chip", kind.get_parent(), marker.get_parent())
	var exposed: Array=''')
replace(p, '\t\trows.append(fields)', '''		Chrome.labeled(fields.name,"Pin name")
		Chrome.labeled(fields.hole,"Board hole")
		Chrome.labeled(fields.role,"Electrical role")
		Chrome.labeled(fields.connector,"Connector")
		rows.append(fields)''')
replace(p, '\taction(row,"↑",', '\taction(row,"Move up",')
replace(p, '\taction(row,"↓",', '\taction(row,"Move down",')
replace(p, '\taction(self,"Save circuit package",', '\tChrome.section(self,"External pins", "circuit", tools, list)\n\tChrome.finish(self)\n\taction(self,"Save circuit package",')

p = paths[4]
replace(p, '\tvar b:=Button.new();b.text=title;b.custom_minimum_size.y=34;parent.add_child(b);b.pressed.connect(action);return b', '\treturn Chrome.action(parent,title,action)')
replace(p, '\tdocument.open(bp)', '\tChrome.setup(self)\n\tdocument.open(bp)')
replace(p, '\tchange_mode(0)', '''	Chrome.labeled(mode,"Editing workflow")
	Chrome.labeled(vertex_list,"Outline point")
	Chrome.labeled(route_list,"Copper trace")
	Chrome.labeled(pads,"Component or land")
	Chrome.section(self,"Board workflow", "circuit", tools, status)
	Chrome.section(self,"Outline geometry", "settings", outline_tools, dimensions)
	Chrome.section(self,"Copper and placement", "component", trace_tools, component_tools)
	Chrome.section(self,"Edit feedback", "info", feedback, feedback)
	Chrome.finish(self)
	change_mode(0)''')

# Verify every preimage again immediately before writing; never overwrite a new edit.
for p in paths:
    assert (ROOT / p).read_bytes() == before[p], f'Concurrent edit: {p}'
manifest = []
for p in paths:
    snapshot = HERE / 'preimages' / p
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    assert not snapshot.exists(), f'Already migrated: {p}'
    snapshot.write_bytes(before[p])
    data = texts[p].replace('\n', '\r\n').encode('utf-8')
    (ROOT / p).write_bytes(data)
    manifest.append({'path':p,'before_sha256':hashlib.sha256(before[p]).hexdigest(),'after_sha256':hashlib.sha256(data).hexdigest()})
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Migrated five assigned editors; exact preimages and SHA-256 manifest retained.')
