"""Bounded source-contract audit; never imports/launches Godot."""
from pathlib import Path
import hashlib,json,re,collections

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
manifest=json.loads((HERE/'manifest.json').read_text())
checks=[]
def require(condition,message):
    assert condition,message
    checks.append(message)

def balanced(text):
    # Ignore strings and comments so electrical units and captions cannot mask syntax.
    pattern=r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*|[()\[\]{}]'
    stack=[]
    for m in re.finditer(pattern,text):
        token=m.group()
        if token in ['(','[','{']:stack.append(token)
        elif token in [')',']','}']:
            if not stack or stack.pop()!={')':'(',']':'[','}':'{'}[token]:return False
    return not stack

for item in manifest:
    path=ROOT/item['file']; raw=path.read_bytes(); text=raw.decode()
    before=(ROOT/item['backup']).read_text(encoding='utf-8')
    require(hashlib.sha256(raw).hexdigest()==item['new_sha256'],item['file']+' matches final hash')
    require(balanced(text),item['file']+' delimiters balanced outside strings/comments')
    if path.name=='dc_ui.gd':
        commands=lambda source:collections.Counter(re.findall(r'send\((\{[^\n]*?\})\)',source))
        require(commands(text)==commands(before),'All DC request dictionaries/callback payloads retained exactly')
        require('system.request(station,action)' in text,'Station request authority route retained')
        require('open(station)' not in text,'Voltage presets preserve panel/tab/focus tree')
        for contract in ['data.channels[i].voltage,0,30,.1','data.channels[i].limit,.001,1,.01','source.current,-1,1,.001','source.compliance,.1,30,.1','data.resistance[i],1,1e6,1','data.capacitance*1e6,.001,10000,.1']:
            require(contract in text,'DC numeric contract: '+contract)
        require('if not control.get_line_edit().has_focus()' in text,'DC snapshot projection preserves focused numeric drafts')
        require('set_pressed_no_signal' in text,'DC snapshot projection does not emit toggle requests')
    else:
        for start,end in [('func _send(', 'func _number(')]:
            extract=lambda v:v[v.index(start):v.index(end)]
            require(extract(text)==extract(before),'Scope request routing and source/probe conversion unchanged')
        for contract in ['float(config.timebase),0.0001,2.0,0.0001','float(config.trigger),-10000,10000,0.01','float(channel.scale),0.001,1000,0.001','float(channel.position),-4,4,0.1']:
            require(contract in text,'Scope numeric contract: '+contract)
        for contract in ['trace.samples=data.get("samples",[])','trace.cursors_changed.connect','stats.frequency_valid','not connected[index]','Legacy host:','auto.disabled=not modern']:
            require(contract in text,'Scope measurement/legacy/disconnect contract: '+contract)
    for resource in re.findall(r'(?:preload|load)\("res://([^"]+)"\)',text):
        require((ROOT/resource).is_file(),'Resource exists: '+resource)

helper=(ROOT/'scripts/ui/instrument_panels/layout.gd').read_text(encoding='utf-8')
helper_manifest=json.loads((HERE/'helper_manifest.json').read_text())
require(hashlib.sha256((ROOT/helper_manifest['file']).read_bytes()).hexdigest()==helper_manifest['new_sha256'],'New helper matches final hash')
require(balanced(helper),'Instrument layout helper delimiters balanced')
require('UI.card(' in helper and 'UI.icon(' in helper and 'responsive_grid.gd' in helper,'Uses shared cards/icons/responsive grid')
require('SCROLL_MODE_DISABLED' in helper and 'ScrollContainer.new()' in helper,'Local instrument tabs have vertical scrolling')
require('expression.parse(text) == OK' in helper and 'expression.execute' not in helper,'Numeric syntax feedback never executes typed expressions')
for resource in re.findall(r'preload\("res://([^"]+)"\)',helper):
    require((ROOT/resource).is_file(),'Helper resource exists: '+resource)
report={'scope':'Source-only checks; no Godot parse, engine, screenshots or runtime acceptance.', 'passed':len(checks),'checks':checks}
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(checks)} offline source-contract checks passed. No Godot/runtime validation performed.')
