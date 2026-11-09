"""Read-only M101 AC equipment baseline check. Run from any working directory."""
from pathlib import Path
import hashlib, json, re, sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
FILES=['scripts/equipment_builder.gd','scripts/campus/performance/equipment_builder_adapter.gd',
       'scripts/campus/performance/equipment_mesh_cache.gd','scripts/equipment_catalog.gd',
       'scripts/lab_state.gd','scripts/equipment_guide.gd',
       *[p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/panels').glob('*.svg*')]]
FUNCTIONS={'scripts/equipment_builder.gd':[
 '_mat','_box','_cylinder','_sphere','_line','_text3','_make_module','_socket',
 '_decorative_socket','_switch','_control','_meter','_build_station','_make_ammeters',
 '_make_wattmeters','_make_voltmeters','_make_load','_face','_small_port','_make_daq',
 '_make_switch_board','_make_transformer','_make_supply','_ring','_machine',
 '_make_dynamometer','_make_motor'],
 'scripts/game.gd':['_build_station','_build_room','_get_target','_physics_process',
                    '_port_position','_render_wires','_render_stations','_sync_supply_controls',
                    'toggle_inspection','_input','activate','_request'],
 'scripts/campus/performance/equipment_builder_adapter.gd':['_instance','_box','_cylinder','_sphere']}

def sha(data):return hashlib.sha256(data).hexdigest()
def sections(text):
    matches=list(re.finditer(r'^func ([A-Za-z_0-9]+)\(',text,re.M))
    return {m.group(1):text[m.start():matches[i+1].start() if i+1<len(matches) else len(text)]
            for i,m in enumerate(matches)}
def capture():
    data={'files':{},'functions':{}}
    for relative in FILES:
        p=ROOT/relative
        if not p.exists():raise FileNotFoundError(relative)
        data['files'][relative]=sha(p.read_bytes())
    for relative,names in FUNCTIONS.items():
        text=(ROOT/relative).read_text(encoding='utf-8-sig')
        mapping=sections(text)
        data['functions'][relative]={name:sha(mapping[name].encode('utf-8')) for name in names if name in mapping}
    return data

def main():
    baseline=json.loads((HERE/'AC_BASELINE.json').read_text(encoding='utf-8'))
    now=capture()
    changes=[]
    for category in ('files','functions'):
        for path,want in baseline[category].items():
            got=now[category].get(path)
            if isinstance(want,dict):
                for name,digest in want.items():
                    if not got or got.get(name)!=digest:changes.append(f'{category}:{path}::{name}')
            elif want!=got:changes.append(f'{category}:{path}')
    if changes:
        print('AC BASELINE DIFFERENCES:\n'+'\n'.join(changes));return 1
    print('AC equipment source and panel asset baseline unchanged');return 0
if __name__=='__main__':sys.exit(main())
