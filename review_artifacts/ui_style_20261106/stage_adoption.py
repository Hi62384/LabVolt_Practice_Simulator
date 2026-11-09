from pathlib import Path
import hashlib,json,difflib,re
ROOT=Path.cwd()
OUT=ROOT/'review_artifacts/ui_style_20261106'
W='preload("res://scripts/ui/design_system/widgets.gd")'
S='preload("res://scripts/ui/design_system/theme.gd").create()'
plans=[]
def plan(path,owner,edits):
    raw=(ROOT/path).read_bytes(); old=raw.decode('utf-8-sig').replace('\r\n','\n'); new=old
    for before,after in edits:
        if new.count(before)!=1: raise ValueError(f'{path}: expected one preimage, got {new.count(before)}: {before!r}')
        new=new.replace(before,after,1)
    plans.append(dict(path=path,owner=owner,source_sha256=hashlib.sha256(raw).hexdigest(),normalized_before_sha256=hashlib.sha256(old.encode()).hexdigest(),normalized_after_sha256=hashlib.sha256(new.encode()).hexdigest(),edits=[dict(before=a,after=b) for a,b in edits]))
    return ''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+path,tofile='b/'+path,n=3))
diffs=[]
diffs.append(plan('scripts/lab_ui.gd','main / HUD pause',[
 ('\tnode.custom_minimum_size.y = 34\n',f'\tnode.custom_minimum_size.y = 44\n\t{W}.style_button(node, {W}.action_icon(text))\n'),
 ('\tnode.position = position\n',f'\tnode.theme = {S}\n\tnode.position = position\n'),
 ('settings.theme=preload("res://scripts/campus/ui/campus_theme.gd").create()',f'settings.theme={S}')]))
diffs.append(plan('scripts/dc_ui.gd','main / instruments',[
 ('\tadd_child(screen);screen.hide()\n',f'\tadd_child(screen);screen.hide()\n\tscreen.theme={S}\n'),
 ('var b := Button.new();b.text=label;b.custom_minimum_size.y=34;',f'var b := Button.new();b.text=label;{W}.style_button(b,{W}.action_icon(label));')]))
diffs.append(plan('scripts/electronics_ui.gd','main / electronics shared helper',[
 ('\tscreen.add_theme_stylebox_override("panel",skin)\n',f'\tscreen.add_theme_stylebox_override("panel",skin)\n\tscreen.theme={S}\n'),
 ('var b := Button.new();b.text=text;b.custom_minimum_size.y=34;',f'var b := Button.new();b.text=text;{W}.style_button(b,{W}.action_icon(text));')]))
diffs.append(plan('scripts/lab_chat.gd','main / HUD chat',[
 ('\tvar style := StyleBoxFlat.new();',f'\tpanel.theme={S}\n\tgame.ui.chat_input.theme=panel.theme\n\tvar style := StyleBoxFlat.new();')]))
diffs.append(plan('scripts/package_editor/package_form.gd','circuit package form',[
 ('func build(profile: RefCounted,draft: Dictionary) -> void:\n',f'func build(profile: RefCounted,draft: Dictionary) -> void:\n\ttheme={S}\n'),
 ('var button := Button.new();button.text=title;',f'var button := Button.new();button.text=title;{W}.style_button(button,{W}.action_icon(title));')]))
diffs.append(plan('scripts/pcb_design/editor.gd','circuit PCB toolbar',[
 ('func build(profile: RefCounted,bp: Dictionary) -> void:\n',f'func build(profile: RefCounted,bp: Dictionary) -> void:\n\ttheme={S}\n'),
 ('var b:=Button.new();b.text=title;b.custom_minimum_size.y=34;',f'var b:=Button.new();b.text=title;{W}.style_button(b,{W}.action_icon(title));')]))
diffs.append(plan('scripts/firmware_ide.gd','firmware IDE',[
 ('func build(studio: Node) -> void:\n',f'func build(studio: Node) -> void:\n\ttheme={S}\n')]))
p='scripts/firmware_backends/native_ide.gd'; src=(ROOT/p).read_text(encoding='utf-8-sig')
old=re.search(r'func apply_studio_theme\(\) -> void:\n.*?(?=\nfunc )',src,re.S).group()
new='func apply_studio_theme() -> void:\n\tvar skin := '+S+'\n\t# Keep a dedicated, legible code surface; the shared theme owns the chrome.\n\tskin.set_color("font_color","CodeEdit",Color("edf6fa"))\n\tskin.set_color("background_color","CodeEdit",Color("0b1b25"))\n\tskin.set_stylebox("normal","CodeEdit",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("0b1b25")))\n\ttheme=skin\n'
diffs.append(plan(p,'firmware native IDE',[
 (old,new),
 ('var item := Button.new();item.custom_minimum_size.y=34;item.text=text;',f'var item := Button.new();item.text=text;{W}.style_button(item,{W}.action_icon(text));'),
 ('compile_button.custom_minimum_size.y=34;',f'{W}.style_button(compile_button,"check",true);')]))
diffs.append(plan('scripts/campus/facilities/facility_panel.gd','facilities owner',[
 ('func _ready() -> void:\n',f'func _ready() -> void:\n\ttheme={S}\n'),
 ('var node:=Button.new();node.text=text;node.custom_minimum_size.y=38',f'var node:=Button.new();node.text=text;{W}.style_button(node,{W}.action_icon(text))')]))
diffs.append(plan('scripts/campus/facilities/clothing_store/store_panel.gd','existing clothing store owner',[
 ('func _ready() -> void:\n',f'func _ready() -> void:\n\ttheme={S}\n'),
 ('close.text = "Close";',f'close.text = "Close"; {W}.style_button(close,"close");'),
 ('tab.text = pair[0];',f'tab.text = pair[0]; {W}.style_button(tab,"palette");'),
 ('buy_button.text = "Select an item";',f'buy_button.text = "Select an item"; {W}.style_button(buy_button,"cart",true);')]))
(OUT/'adoption_patches.json').write_text(json.dumps({'version':1,'policy':'STAGED ONLY. Do not apply across owner changes. Each complete file SHA must match before any mutation; dry-run every edit first. Preserve source newline/BOM. No partial application.','patches':plans},indent=2)+'\n',encoding='utf-8')
(OUT/'adoption.patch').write_text('\n'.join(diffs),encoding='utf-8')
print('Staged',len(plans),'preimage-bound files; no shared source modified')
