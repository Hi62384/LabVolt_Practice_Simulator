"""Bounded offline invariants. This is not a GDScript parser or visual acceptance."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[3]
REVIEW=ROOT/'scripts/ui/hud_settings/review'
entries=json.loads((REVIEW/'manifest.json').read_text())
checks=[]
def check(value, label):
    assert value,label
    checks.append(label)
def functions(text):
    matches=list(re.finditer(r'^func (\w+)\(',text,re.M))
    return {m[1]:text[m.start():matches[i+1].start() if i+1<len(matches) else len(text)].strip() for i,m in enumerate(matches)}
old={};new={}
for e in entries:
    p=e['path']; before=(ROOT/e['preimage']).read_bytes();after=(ROOT/p).read_bytes()
    check(hashlib.sha256(before).hexdigest()==e['before'],p+' preimage')
    check(hashlib.sha256(after).hexdigest()==e['after'],p+' final image')
    old[p]=before.decode('utf-8-sig').replace('\r\n','\n')
    new[p]=after.decode('utf-8-sig').replace('\r\n','\n')

for p,ignore in {
 'scripts/campus/ui/graphics_settings.gd':{'build_controls'},
 'scripts/campus/ui/profile_visibility.gd':{'build_controls'},
 'scripts/lab_chat.gd':{'build'},
 'scripts/campus/performance/profiling_overlay.gd':{'_ready'},
 'scripts/campus/facilities/facility_panel.gd':{'_ready','open_for','redraw','button'},
 'scripts/lab_ui.gd':{'label','button','panel','build','update_records','update_roster'},
}.items():
    a,b=functions(old[p]),functions(new[p])
    for name in a.keys()-ignore:
        check(a[name]==b[name],p+' unchanged '+name)

p='scripts/lab_ui.gd'
requests=lambda t:re.findall(r'game\._request\((\{[^\n]+?\})\)',t)
check(requests(old[p])==requests(new[p]),'Lab check/record/submit/configure request payloads unchanged')
for call in ['game.session.chat(value)', 'game.session.leave()', 'game.session.host_game(name_input.text,int(port.value))', 'game.session.join_game(address.text,name_input.text,int(port.value))', 'game.session.ready_toggle()', 'game.toggle_fullscreen()', 'game.player.sensitivity=v; game.player.save_settings()', 'game.player.head_bob=v; game.player.save_settings()', 'binding=action; binding_button=key_button; key_button.text="Press a key…"']:
    check(new[p].count(call)==old[p].count(call),'Lab callback '+call)
check(functions(old[p])['update_records'].split('\trecords_label.text')[0]==functions(new[p])['update_records'].split('\trecords_label.text')[0],'XP and achievement calculations unchanged')
check('settings.tree_exiting.connect' in new[p] and 'settings.theme = HudTheme.create()' in new[p],'Reparented settings keep theme and remove empty wrapper')

p='scripts/campus/facilities/facility_panel.gd'
ops=lambda t:re.findall(r'\{"op":[^\n]+?\}',t)
check(ops(old[p])==ops(new[p]),'Every facility request and its station/item payload unchanged')
check('value.sequence=int(state.profile.last_sequence)+1' in new[p],'Facility sequence remains host snapshot + 1')
check('for action in service_actions: action.disabled=true' in new[p] and 'if pending or state.is_empty():return' in new[p],'Pending actions lock immediately')

p='scripts/campus/ui/profile_inspector.gd'
for line in old[p].splitlines():
    if any(x in line for x in ['safe.FIELDS','safe.project(','public_profile.has(']):
        check(line in new[p],'Public allowlist/projection: '+line.strip())
check('source.get(' not in new[p] and 'load_settings(' not in new[p],'Inspector does not read a local profile/save')
check('Signage.room_hud_identity(room)' in new['scripts/campus/ui/campus_hud.gd'],'Full registry room identity retained')

# Lex strings/comments and check nested delimiters in only owned GDScript files.
paths=[ROOT/e['path'] for e in entries]+list((ROOT/'scripts/ui/hud_settings').glob('*.gd'))
resources=set()
for file in paths:
    text=file.read_text(encoding='utf-8-sig');stack=[];quote=None;escape=False;comment=False
    for ch in text:
        if comment:
            if ch=='\n':comment=False
            continue
        if quote:
            if escape:escape=False
            elif ch=='\\':escape=True
            elif ch==quote:quote=None
            continue
        if ch=='#':comment=True
        elif ch in ['"',"'"]:quote=ch
        elif ch in '([{':stack.append(ch)
        elif ch in ')]}':
            check(bool(stack) and stack.pop()=='([{'[')]}'.index(ch)],str(file)+' balanced '+ch)
    check(not stack and quote is None,str(file)+' complete delimiters/strings')
    for path in re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)',text):resources.add(path)
for path in resources:check((ROOT/path).is_file(),'Resource exists: '+path)
report={'status':'PASS','checks':len(checks),'files':len(paths),'resources':len(resources),
 'scope':'Source invariants, delimiters and resource existence only. No engine, parser, runtime, visual or multiplayer execution.',
 'unchanged_logic':'Graphics apply/persistence, privacy persistence, chat receive/process, profiling cadence, lab refresh, request payloads and XP calculation compared to exact preimages.'}
(REVIEW/'offline_validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
