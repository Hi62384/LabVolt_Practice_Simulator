from pathlib import Path
import hashlib,json,math,re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
records=json.loads((HERE/'INTEGRATION.json').read_text())
for record in records:
    name=Path(record['path']).stem
    assert hashlib.sha256((ROOT/record['path']).read_bytes()).hexdigest()==record['preimage_sha256']
    assert hashlib.sha256((HERE/f'{name}.candidate.gd').read_bytes()).hexdigest()==record['candidate_sha256']
candidate=(HERE/'electronics_ui.candidate.gd').read_text(encoding='utf-8')
assert 'scroll.remove_child(body)' in candidate and 'page_scroll=null' in candidate
old=(HERE/'electronics_ui.preimage.gd').read_text(encoding='utf-8')
assert candidate[candidate.index('func deploy()'):]==old[old.index('func deploy()'):], 'Shared authority/simulation methods changed'
workspace=(HERE/'modules/workspace.gd').read_text(encoding='utf-8')
assert 'focused is LineEdit or focused is TextEdit' in workspace
assert 'ScrollContainer' not in workspace and 'TabBar' not in workspace
canvas=(HERE/'modules/workspace_canvas.gd').read_text(encoding='utf-8')
assert 'if not fitted:fit_board()' in canvas
assert 'super._gui_input(event)' in canvas and 'super._draw()' in canvas
placement=(HERE/'modules/placement.gd').read_text(encoding='utf-8')
assert 'Model.validate(result,{},true)' in placement and 'Geometry.holes_at' in placement
for width,height in [(1920,1080),(1366,768)]:
    # Deterministic fit math for 10/20/30/40 rows; actual visual QA remains required.
    available=(width-64,height-180)
    assert available[1]/(height-64)>=.80
    for rows in [10,20,30,40]:
        extent=(73+(rows-1)*23,377)
        zoom=max(.15,min(4,min((available[0]-48)/extent[0],(available[1]-48)/extent[1])))
        pan=((available[0]-extent[0]*zoom)/2,(available[1]-extent[1]*zoom)/2)
        assert all(math.isfinite(x) and x>=24-1e-6 for x in pan)
        assert extent[0]*zoom<=available[0] and extent[1]*zoom<=available[1]
for path in (HERE/'modules').glob('*.gd'):
    text=path.read_text(encoding='utf-8')
    for resource in re.findall(r'(?:preload|extends)\(?"res://([^"\n]+)"',text):
        if resource.startswith('scripts/electronics/circuit_workspace/'):
            assert (HERE/'modules'/Path(resource).name).exists(),resource
        elif resource.startswith('scripts/electronics/contextual_panels/'):
            assert (HERE.parent/'contextual_panels'/Path(resource).name).exists(),resource
        else:assert (ROOT/resource).exists(),resource
print('PASS: source preimages/candidates, unchanged authority/simulation tail, viewport mount, text-focus guard, model delegation, cached-view guard, 8 fit/layout cases. Godot model fixture and screenshots NOT executed.')
