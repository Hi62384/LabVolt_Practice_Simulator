"""Bounded source-contract checks, deliberately never launches Godot."""
from pathlib import Path
from collections import Counter
import hashlib, json, re

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
manifest = json.loads((HERE / 'manifest.json').read_text())

def methods(text):
    starts = list(re.finditer(r'^(?:static )?func (\w+)\(', text, re.M))
    return {m[1]: text[m.start():starts[i+1].start() if i+1<len(starts) else len(text)].strip()
            for i,m in enumerate(starts)}

def lexical_balance(text, path):
    stack=[]; quote=None; escaped=False; comment=False
    for char in text:
        if comment:
            if char=='\n': comment=False
            continue
        if quote:
            if escaped: escaped=False
            elif char=='\\': escaped=True
            elif char==quote: quote=None
            continue
        if char=='#': comment=True
        elif char in ['"', "'"]: quote=char
        elif char in '([{': stack.append(char)
        elif char in ')]}':
            assert stack and stack.pop() == {')':'(',']':'[','}':'{'}[char], path
    assert not stack and quote is None, path

checked_methods=0
for entry in manifest:
    path=entry['path']; current=(ROOT/path).read_bytes(); old=(HERE/'preimages'/path).read_bytes()
    assert hashlib.sha256(old).hexdigest()==entry['before_sha256'], path
    assert hashlib.sha256(current).hexdigest()==entry['after_sha256'], f'Unreviewed edit: {path}'
    before=old.decode().replace('\r\n','\n'); after=current.decode().replace('\r\n','\n')
    originals=methods(before); updated=methods(after)
    for name,body in originals.items():
        if name in ['build','button','action','spin','apply_studio_theme']: continue
        candidate=updated[name]
        if name=='change_mode':
            candidate=candidate.replace('\toutline_group.visible=index==0;copper_group.visible=index==1\n','')
        assert body == candidate, f'Behavior method changed: {path}:{name}'
        checked_methods+=1
    # Every authority/save/runtime signal statement in build must survive intact.
    protected = ['control_requested.emit(', 'save_requested.emit(', 'draft_requested.emit(',
                 'dc_lab.request(', 'ui.profile.save()', 'Document.store(', 'save_copy(profile)',
                 'document.resize(', 'document.move_pad(', 'document.rotate_component(',
                 'document.remove_route(', 'swap(index,', 'SourceProject.filename_ok(']
    for fragment in protected:
        lines=[line.strip() for line in before.splitlines() if fragment in line]
        for line in lines:
            # UI factory names and the two reorder action labels are intentional.
            normalized=line.replace('ui.button(', 'Chrome.action(').replace('"↑"','"Move pin up"').replace('"↓"','"Move pin down"')
            assert normalized in after, f'Protected statement changed: {path}: {line}'
    lexical_balance(after,path)
    for resource in re.findall(r'preload\("res://([^"\n]+)"\)',after):
        assert (ROOT/resource).is_file(), f'Missing resource {resource}'

helper=ROOT/'scripts/ui/circuit_editor_panels/chrome.gd'
lexical_balance(helper.read_text(), str(helper))
for relative in ['scripts/ui/design_system/widgets.gd','scripts/ui/design_system/theme.gd']:
    shared=(ROOT/relative).read_text()
    for resource in re.findall(r'preload\("res://([^"\n]+)"\)', shared):
        assert (ROOT/resource).is_file(), resource

package=(ROOT/'scripts/package_editor/package_form.gd').read_text()
assert 'list.get_child(index).visible=index<int(value)' in package
assert 'list.add_child(pin_card)' in package and 'pin_card.add_child(row)' in package
assert 'rows.append(fields)' in package
native=(ROOT/'scripts/firmware_backends/native_ide.gd').read_text()
assert 'source_tabs.add_child(editor)' in native
assert 'source_tabs.current_tab=editor.get_index()' in native
assert 'source_tabs.get_current_tab_control() as CodeEdit' in native
assert 'profile' not in helper.read_text() and 'multiplayer' not in helper.read_text()
report=f'PASS: 5 exact preimage/new hashes; {checked_methods} behavior methods unchanged; protected build statements; balanced source delimiters; local resources; pin-row and source-tab index contracts.\nSource-only checks; no Godot parsing, runtime tests or visual acceptance performed.\n'
(HERE/'validation.txt').write_text(report)
print(report)
