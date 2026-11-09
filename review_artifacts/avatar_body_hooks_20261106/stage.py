"""Produce review-only, SHA-bound integration changes; never edit shared files."""
from pathlib import Path
import difflib, hashlib, json
ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
def stage(path, edits):
    source = ROOT / path
    data = source.read_bytes()
    old = data.decode('utf-8').replace('\r\n', '\n')
    new = old
    for before, after in edits:
        assert new.count(before) == 1, (path, before[:90])
        new = new.replace(before, after, 1)
    (OUT / (source.stem + '.patch')).write_text(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/'+path, tofile='b/'+path)), encoding='utf-8')
    return {'path':path, 'sha256':hashlib.sha256(data).hexdigest()}
hashes = []
hashes.append(stage('scripts/toon_character.gd', [
 ('extends RefCounted\n','extends RefCounted\nconst BodyDeformation = preload("res://scripts/avatar_cosmetics/body_deformation/rig_adapter.gd")\n'),
 ('static func build(raw: Dictionary) -> Node3D:', 'static func build(raw: Dictionary, modern_body: Dictionary = {}) -> Node3D:'),
 ('\t_glasses(head,c,dark,accent)\n\t_animations(root)', '\t_glasses(head,c,dark,accent)\n\tBodyDeformation.apply(root,modern_body,c)\n\t_animations(root)'),
 ('static func save_glb(config: Dictionary,path: String) -> Error:\n\tvar model := build(config)', 'static func save_glb(config: Dictionary,path: String,modern_body: Dictionary = {}) -> Error:\n\tvar model := build(config,modern_body)')]))
hashes.append(stage('scripts/avatar_cosmetics/core/avatar_renderer.gd', [
 ('extends RefCounted\n','extends RefCounted\nconst BodyFit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")\nconst BodyDeformation = preload("res://scripts/avatar_cosmetics/body_deformation/rig_adapter.gd")\n'),
 ('var avatar := Toon.build(legacy)', 'var avatar := Toon.build(legacy,body)\n\tbody = BodyFit.provider_context(body,Toon.sanitize(legacy))'),
 ('\treturn avatar\n', '\tBodyDeformation.finish(avatar)\n\treturn avatar\n'),
 ('static func _hide_matching', '''static func save_glb(state: Dictionary,catalog: Dictionary,path: String) -> Error:
	var model := render_avatar(state,catalog)
	var document := GLTFDocument.new(); var gltf_state := GLTFState.new()
	var error := document.append_from_scene(model,gltf_state)
	if error==OK: error=document.write_to_filesystem(gltf_state,path)
	model.free()
	return error

static func _hide_matching''')]))
for path, name, signature, call in [
 ('scripts/avatar_cosmetics/clothing/clothing_provider.gd','Clothing','static func _apply_fit(root: Node, definition: Dictionary, body: Dictionary, parameters: Dictionary) -> void:', '\tBodyFit.fit_clothing(root as Node3D,definition,body,parameters)\n'),
 ('scripts/avatar_cosmetics/accessories/accessory_provider.gd','Accessory','static func _apply_fit(item: Node3D, slot: String, parameters: Dictionary, body: Dictionary) -> void:', '\tBodyFit.fit_accessory(item,slot,body,parameters)\n')]:
    text = (ROOT/path).read_text(encoding='utf-8')
    start = text.index(signature)
    end = text.index('\nstatic func ',start+len(signature))
    hashes.append(stage(path,[('extends RefCounted\n','extends RefCounted\nconst BodyFit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")\n'),(text[start:end], signature+'\n'+call)]))
(OUT/'PREIMAGES.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
print('Staged four preimage-bound review patches; shared sources untouched.')
