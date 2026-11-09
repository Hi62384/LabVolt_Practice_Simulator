from pathlib import Path
import hashlib,json,difflib
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
rows=[]
def stage(path,edits):
    raw=(ROOT/path).read_bytes();old=raw.decode().replace('\r\n','\n');new=old
    for a,b in edits:
        assert new.count(a)==1,(path,a)
        new=new.replace(a,b,1)
    (OUT/(Path(path).stem+'.patch')).write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+path,tofile='b/'+path)))
    rows.append(dict(path=path,sha256=hashlib.sha256(raw).hexdigest()))
stage('scripts/first_person.gd',[
('var seated: CharacterBody3D','var resting := false\nvar rest_anchor := Transform3D.IDENTITY\nvar seated: CharacterBody3D'),
('func _physics_process(delta: float) -> void:', '''func begin_rest(anchor: Transform3D) -> bool:
	if seated!=null or inspecting or not anchor.is_finite():return false
	resting=true;rest_anchor=anchor;velocity=Vector3.ZERO
	collider.set_deferred("disabled",true)
	global_position=anchor.origin;eyes.position.y=.12
	return true

func end_rest(destination: Vector3) -> void:
	resting=false;global_position=destination;velocity=Vector3.ZERO
	crouched=false;(collider.shape as CapsuleShape3D).height=1.7;collider.position.y=.85
	collider.set_deferred("disabled",false);eyes.position.y=1.65

func _physics_process(delta: float) -> void:
	if resting:
		global_position=rest_anchor.origin;velocity=Vector3.ZERO
		eyes.rotation.x=pitch_target
		return'''),
('if seated!=null or chair.rider!=null:', 'if resting or seated!=null or chair.rider!=null:')])
stage('scripts/avatar_model.gd',[
('static func animate(model: Node, walking: bool,seated := false) -> void:', '''static func animate(model: Node, walking: bool,seated := false,resting := false) -> void:
	preload("res://review_artifacts/persistent_dorms_20261107/rest/rest_pose.gd").apply(model as Node3D,resting)
	if resting:return''')])
stage('scripts/session.gd',[
('func accept_pose(id: int,data: Dictionary) -> void:', 'var rest_pose_guard: Callable\n\nfunc accept_pose(id: int,data: Dictionary) -> void:'),
('\tposes[id] = clean\n', '\tif rest_pose_guard.is_valid():clean=rest_pose_guard.call(id,clean)\n\tposes[id] = clean\n')])
stage('scripts/game.gd',[
('var dorm_interactions: Node','var dorm_rest: Node\nvar dorm_interactions: Node'),
('func activate() -> void:', 'func activate() -> void:\n\tif is_instance_valid(dorm_rest) and player.resting:return'),
('func _input(event: InputEvent) -> void:', '''func install_dorm_rest(authority: Object) -> void:
	if is_instance_valid(dorm_rest):return
	dorm_rest=preload("res://review_artifacts/persistent_dorms_20261107/rest/rest_controller.gd").new()
	dorm_rest.name="DormRest";add_child(dorm_rest);dorm_rest.configure(self,authority)
	session.rest_pose_guard=dorm_rest.canonical_pose

func _input(event: InputEvent) -> void:
	if is_instance_valid(dorm_rest) and player.resting and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE,KEY_SPACE,player.keys.interact]:
		dorm_rest.request("",true);get_viewport().set_input_as_handled();return'''),
('target.get("seated",false))','target.get("seated",false),target.get("resting",false))'),
('func _claim_chair(peer: int,index: int) -> void:', 'func _claim_chair(peer: int,index: int) -> void:\n\tif is_instance_valid(dorm_rest) and dorm_rest.state.resting.has(peer):return')])
stage('scripts/campus/facilities/avatar_activity.gd',[
('func restore() -> void:', 'func restore() -> void:\n\tif is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return'),
('func _process(delta: float) -> void:', 'func _process(delta: float) -> void:\n\tif is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return')])
(OUT/'PREIMAGES.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Staged player/avatar hooks without shared writes')
