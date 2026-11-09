from pathlib import Path
import difflib
import hashlib
import json

root = Path.cwd()
stage = root / "review_artifacts/menu_campus_flythrough_20261107/core"
manifest = {}

def stage_patch(relative, changes):
    path = root / relative
    original = path.read_bytes()
    encoding = "utf-8-sig" if original.startswith(b"\xef\xbb\xbf") else "utf-8"
    source = original.decode(encoding).replace("\r\n", "\n")
    updated = source
    anchors = []
    for before, after in changes:
        assert updated.count(before) == 1, (relative, before)
        updated = updated.replace(before, after, 1)
        anchors.append({"before": before, "after": after})
    label = relative.replace("/", "__")
    (stage / (label + ".patch")).write_text("".join(difflib.unified_diff(
        source.splitlines(keepends=True), updated.splitlines(keepends=True),
        "a/" + relative, "b/" + relative)), encoding="utf-8")
    if b"\r\n" in original:
        updated = updated.replace("\n", "\r\n")
    manifest[relative] = {
        "preimage_sha256": hashlib.sha256(original).hexdigest(),
        "postimage_sha256": hashlib.sha256(updated.encode(encoding)).hexdigest(),
        "anchors": anchors,
    }

stage_patch("scripts/game.gd", [
    ('var front: CanvasLayer\n', 'var front: CanvasLayer\nvar menu_campus: Node\n'),
    ('\tadd_child(lab_challenges);lab_challenges.build(self)\n\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE\n',
     '\tadd_child(lab_challenges);lab_challenges.build(self)\n'
     '\tmenu_campus = preload("res://scripts/campus/presentation/menu_flythrough/campus_presentation.gd").new()\n'
     '\tmenu_campus.name = "MenuCampusPresentation"\n\tadd_child(menu_campus)\n'
     '\tmenu_campus.install(self)\n\tmenu_campus.show_menu()\n'
     '\tInput.mouse_mode = Input.MOUSE_MODE_VISIBLE\n'),
    ('func capture() -> void:\n\tif is_instance_valid(front):front.entered()\n',
     'func capture() -> void:\n\tif is_instance_valid(menu_campus):menu_campus.enter_game()\n'
     '\tif is_instance_valid(front):front.entered()\n'),
])

stage_patch("scripts/campus/world/zone_streamer.gd", [
    ('var viewer := Vector3(13,0,-18)\n',
     'var viewer := Vector3(13,0,-18)\nvar _menu_mode := false\nvar _menu_rooms := PackedStringArray()\n'),
    ('func set_viewer_position(point: Vector3) -> void:\n\tviewer=point\n\tfor id in registry.rooms:\n',
     'func set_menu_rooms(rooms: PackedStringArray) -> void:\n'
     '\t_menu_mode = true\n\t_menu_rooms = rooms\n\t_update_desired_rooms()\n\n'
     'func clear_menu_rooms() -> void:\n'
     '\t_menu_mode = false\n\t_menu_rooms = PackedStringArray()\n\t_update_desired_rooms()\n\n'
     'func set_viewer_position(point: Vector3) -> void:\n\tviewer=point\n'
     '\tif not _menu_mode:\n\t\t_update_desired_rooms()\n\n'
     'func _update_desired_rooms() -> void:\n\tvar point := viewer\n\tfor id in registry.rooms:\n'),
    ('\t\tvar wanted := same_floor and Vector2(point.x-center.x,point.z-center.z).length()<view_distance\n',
     '\t\tvar wanted := _menu_rooms.has(id) if _menu_mode else (same_floor and Vector2(point.x-center.x,point.z-center.z).length()<view_distance)\n'),
])

stage_patch("scripts/front_menu.gd", [
    ('var preview_camera: Camera3D\n', ''),
    ('var clock := 0.0\n', ''),
    ('\tpreview_camera=Camera3D.new()\n\tpreview_camera.fov=60\n\tgame.add_child(preview_camera)\n', ''),
    ('\t\tif joining and game.session.online and game.session.roster.has(multiplayer.get_unique_id()):\n'
     '\t\t\tjoining=false\n\t\t\tgame.capture()\n',
     '\t\tif not joining:return\n'
     '\t\tif not game.session.online:\n\t\t\tjoining=false\n'
     '\t\t\tgame.menu_campus.hold(false)\n'
     '\t\telif game.session.roster.has(multiplayer.get_unique_id()):\n'
     '\t\t\tjoining=false\n\t\t\tgame.capture()\n'),
    ('\tif joining:\n\t\tjoining=false\n\t\tgame.session.leave()\n',
     '\tif joining:\n\t\tjoining=false\n\t\tgame.session.leave()\n'
     '\tif not in_game and is_instance_valid(game.menu_campus):game.menu_campus.show_menu()\n'),
    ('\t\tbutton("Connect",func():\n', '\t\tbutton("Connect",func():\n\t\t\tif joining:return\n'),
    ('\t\t\tvar result: int=game.session.join_game(address_field.text,name_field.text,int(port.value))\n'
     '\t\t\tif result!=OK:status.text=error_string(result)\n',
     '\t\t\tgame.menu_campus.hold(true)\n'
     '\t\t\tvar result: int=game.session.join_game(address_field.text,name_field.text,int(port.value))\n'
     '\t\t\tif result!=OK:\n\t\t\t\tgame.menu_campus.hold(false)\n'
     '\t\t\t\tstatus.text=error_string(result)\n'),
    ('\tif not is_instance_valid(host_start) or host_start.disabled:return\n',
     '\tif not is_instance_valid(host_start) or host_start.disabled:return\n'
     '\tif host_mode!="Freeplay" and not _ensure_campus_adapter():\n'
     '\t\tstatus.text="Course services are unavailable."\n\t\treturn\n'
     '\tgame.menu_campus.hold(true)\n'),
    ('\t\tif error!=OK:status.text=error_string(error);return\n',
     '\t\tif error!=OK:\n\t\t\tgame.menu_campus.hold(false)\n'
     '\t\t\tstatus.text=error_string(error)\n\t\t\treturn\n'),
    ('\tif not _ensure_campus_adapter():status.text="Course services are unavailable.";return\n'
     '\tvar result: Dictionary=campus_adapter.call("request_activity"',
     '\tvar result: Dictionary=campus_adapter.call("request_activity"'),
    ('\telse:status.text=str(result.get("error","Unable to start the selected class."))\n',
     '\telse:\n\t\tif not host_alone.button_pressed:game.session.leave()\n'
     '\t\tgame.menu_campus.hold(false)\n'
     '\t\tstatus.text=str(result.get("error","Unable to start the selected class."))\n'),
    ('\tpreview_camera.current=true\n\thome()\n', '\thome()\n'),
    ('\tif preview_camera==null:return\n\tclock+=delta\n', ''),
    ('\t\tif campus_tick>=0.25 and is_instance_valid(campus_adapter) and is_instance_valid(campus_adapter.registry):\n',
     '\t\tif in_game and campus_tick>=0.25 and is_instance_valid(campus_adapter) and is_instance_valid(campus_adapter.registry):\n'),
    ('\tif not in_game:\n\t\tpreview_camera.position=Vector3(4.5+sin(clock*.08)*.5,2.6,4.5)\n'
     '\t\tpreview_camera.look_at(Vector3(-.4,2.1,-2.8))\n\t\tpreview_camera.current=true\n', ''),
])

(stage / "PREIMAGES.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("Staged", sum(len(entry["anchors"]) for entry in manifest.values()), "exact anchors in", len(manifest), "files.")
