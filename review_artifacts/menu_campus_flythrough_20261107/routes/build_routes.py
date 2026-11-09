"""Offline authoring and coarse clearance audit for the existing campus menu tour.

This script reads source contracts only. It never opens Godot or writes production files.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
REGISTRY = json.loads((ROOT / "assets/campus/world/room_registry.json").read_text())
ROOMS = {room["id"]: room for room in REGISTRY["rooms"]}


def route(route_id, location_id, points, targets, speed=0.68, weight=1.0,
          transition="crossfade", note=""):
    assert len(points) == len(targets) and len(points) >= 3
    return {
        "id": route_id,
        "location_id": location_id,
        "points": points,
        "look_targets": targets,
        "speed_mps": speed,
        "weight": weight,
        "transition": transition,
        "hold_seconds": 1.5,
        "note": note,
    }


routes = [
    route("entrance_reveal", "entrance",
          [[12.1, 1.85, -22.0], [12.7, 1.88, -20.0], [13.3, 1.9, -17.5], [13.0, 1.9, -14.0]],
          [[13, 2.5, -11.5], [13, 2.4, -11.5], [13, 2.2, -9], [13, 2, -7]],
          .62, 1.4, note="Central paved entrance, clear of courtyard benches and trees."),
    route("courtyard_landscape", "courtyard",
          [[12.0, 1.9, -14.5], [12.6, 1.9, -17.0], [13.5, 1.95, -19.5], [14.3, 1.9, -22.0]],
          [[5, 1.6, -16], [4, 2.1, -17], [13, 3.0, -11], [21, 2.1, -17]],
          .57, 1.2, note="Views planted strips from central open paving; no travel across landscaping."),
    route("lobby_entry", "lobby",
          [[13, 1.85, -17], [13.1, 1.85, -14.5], [13.15, 1.85, -11.5], [13, 1.85, -8.5], [12.9, 1.85, -5.5]],
          [[13, 2.6, -11], [13, 2.2, -9], [13, 2, -6], [13, 2, -3], [13, 2, 2]],
          .65, 1.4, note="Continuous six-metre entrance and lobby opening."),
]


def hall_route(floor, name, z_values, room_ids):
    y = floor * 5 + 1.85
    points = [[13 + (.28 if i % 3 == 1 else -.18 if i % 3 == 2 else 0), y, z]
              for i, z in enumerate(z_values)]
    targets = []
    for i, z in enumerate(z_values):
        room = ROOMS[room_ids[min(i, len(room_ids) - 1)]]
        door = room["door"]
        targets.append([door[0] + (-2.0 if door[0] == 10 else 2.0),
                        floor * 5 + 1.8, door[2]])
    routes.append(route(name, f"hall_f{floor}", points, targets, .72, 1.7,
                        note="Camera stays near corridor centre and looks through actual room door openings."))


hall_route(0, "ground_hall_south", [-2, 1, 3, 6, 9, 12, 16, 19, 22],
           ["ac_lab", "ac_lab", "ac_lab", "shop", "shop", "dc_lab", "dc_lab", "cafeteria", "cafeteria"])
hall_route(0, "ground_hall_north", [25, 29, 33, 37, 41, 45, 47, 49],
           ["cafeteria", "gym", "gym", "tim_hortons", "tim_hortons", "subway", "subway", "subway"])
hall_route(1, "upper_hall_south", [-2, 1, 3, 6, 10, 14, 19, 23],
           ["elm253_lecture", "elm253_lecture", "ety155_lecture", "ety155_lecture",
            "computer", "computer", "library", "library"])
hall_route(1, "upper_hall_north", [25, 28, 31, 33, 36, 39, 43, 47],
           ["library", "study", "study", "study", "study", "circuit_studio",
            "circuit_studio", "circuit_studio"])


def doorway_view(room_id, route_id=None, weight=.9):
    room = ROOMS[room_id]
    x = room["door"][0]
    z = room["door"][2]
    floor_y = room["center"][1]
    inward = -1 if x == 10 else 1
    # Stay outside the doorway. A full interior sweep needs a Godot collision audit.
    points = [[13.0, floor_y + 1.83, z - 2.5],
              [13.0 + inward * .18, floor_y + 1.86, z - .8],
              [13.0 + inward * .18, floor_y + 1.88, z + .8],
              [13.0, floor_y + 1.83, z + 2.5]]
    targets = [[x + inward * 3.5, floor_y + 1.65, z - .45],
               [x + inward * 4.5, floor_y + 1.7, z],
               [x + inward * 5.0, floor_y + 1.7, z],
               [x + inward * 3.5, floor_y + 1.65, z + .45]]
    routes.append(route(route_id or f"{room_id}_door_view", room_id, points,
                        targets, .43, weight,
                        note=f"M{room['number'][1:]} view through the actual {room['door_width']}m door; camera stays in hall."))


for room_id in ["ac_lab", "dc_lab", "shop", "gym", "cafeteria", "tim_hortons",
                "subway", "elm253_lecture", "ety155_lecture", "computer", "library",
                "study", "circuit_studio"]:
    doorway_view(room_id)


# Room-entry tracks use the actual unobstructed door-centre aisles. They extend
# beyond the shell wall, unlike the doorway-only views above. Their interior
# reaches are deliberately short until Godot collision/raster review is possible.
INTERIOR_LIMITS = {
    "elm253_lecture": (6.4, 10.0),
    "ety155_lecture": (16.0, 19.6),
    "computer": (8.75, 10.0),
    "library": (16.0, 19.0),
    "study": (7.0, 10.0),
    "cafeteria": (16.0, 18.3),
    "circuit_studio": (16.0, 20.0),
}
# Representative occupied volumes from classroom_layout.gd, m203_room.gd,
# computer_station.gd, studio_room.gd, facility_room.gd and the social decor
# profile's seat/bookcase centres. Each footprint is deliberately enlarged
# beyond the mesh or collision footprint; dynamic chairs remain runtime work.
INTERIOR_OBSTACLES = {
    "elm253_lecture": [(x - 1.0, x + 1.0, z - .8, z + .8) for x in [-3.6, -1.2, 1.2, 3.6] for z in [-.5, 2.0]],
    "ety155_lecture": [(x - 1.0, x + 1.0, z - .8, z + .8) for x in [22.4, 24.8, 27.2, 29.6] for z in [-.5, 2.0]],
    "computer": [(x - 1.1, x + 1.1, z - .6, z + 1.5) for x in [-7.2, -3.6, 0, 3.6, 7.2] for z in [16.2, 18.4, 20.6, 22.8]],
    "library": [(19.0, 20.2, 15.0, 16.8), (19.0, 20.2, 21.2, 22.8)],
    "study": [(6.0, 7.8, 29.0, 30.7), (6.0, 7.8, 35.3, 37.0), (6.7, 8.0, 35.1, 36.2)],
    "cafeteria": [(20.0, 22.0, 14.6, 17.4), (20.0, 22.0, 20.6, 23.4)],
    "circuit_studio": [(21.0, 24.6, 42.1, 43.9), (23.2, 28.4, 46.2, 47.8),
                       (28.0, 31.6, 45.8, 48.2)],
}


def interior_route(room_id, reach, target_x, speed=.5):
    room = ROOMS[room_id]
    door_x, base_y, z = room["door"]
    west = door_x == 10
    half_way = (door_x + reach) / 2
    points = [[13, base_y + 1.82, z],
              [door_x + (1 if west else -1), base_y + 1.84, z],
              [half_way, base_y + 1.85, z + .12],
              [reach, base_y + 1.86, z + .35],
              [reach, base_y + 1.86, z + .65]]
    targets = [[target_x, base_y + 1.7, z - 1.0],
               [target_x, base_y + 1.7, z - 1.0],
               [target_x, base_y + 1.6, z - 1.4],
               [target_x, base_y + 1.5, z - 1.6],
               [target_x, base_y + 1.5, z - 1.6]]
    routes.append(route(f"{room_id}_interior", room_id, points, targets, speed, 1.15,
                        note="Actual doorway crossing into source-checked central room aisle; runtime collision and framing review still required."))


interior_route("elm253_lecture", 6.5, 0)
interior_route("ety155_lecture", 19.5, 26)
interior_route("computer", 8.8, 0, .4)
interior_route("library", 18.8, 26)
interior_route("study", 7.2, 0)
interior_route("cafeteria", 18.2, 26)
interior_route("circuit_studio", 19.8, 26)

routes.append(route("dorm_hall_preview", "dorm_hall",
                    [[13, 1.82, 69.8], [13.2, 1.84, 71.4], [13.0, 1.86, 73.5], [12.8, 1.84, 75.5]],
                    [[13, 1.7, 73.75], [10, 1.8, 73.75], [16, 1.8, 73.75], [13, 1.8, 78]],
                    .5, .85, note="Dorm hallway only; entry at z68 and capacity-dependent dorm shell must be present."))


def validate():
    failures = []
    seen = set()
    for item in routes:
        if item["id"] in seen:
            failures.append(f"duplicate ID {item['id']}")
        seen.add(item["id"])
        if len(item["points"]) != len(item["look_targets"]):
            failures.append(f"target count {item['id']}")
        points_to_check = list(item["points"])
        # Same cubic Bezier handles as routes.gd. Audit the swept camera centre,
        # not just authored control points; .25 m camera radius is budgeted by
        # the conservative envelopes below.
        authored = item["points"]
        for i in range(len(authored) - 1):
            p0, p3 = authored[i], authored[i + 1]
            prev = authored[max(0, i - 1)]
            nxt = authored[min(len(authored) - 1, i + 2)]
            out_handle = [(p3[k] - prev[k]) * .12 for k in range(3)]
            in_handle = [(nxt[k] - p0[k]) * .12 for k in range(3)]
            p1 = [p0[k] + out_handle[k] for k in range(3)]
            p2 = [p3[k] - in_handle[k] for k in range(3)]
            for sample in range(1, 21):
                t = sample / 20
                u = 1 - t
                points_to_check.append([u**3*p0[k] + 3*u*u*t*p1[k] +
                                        3*u*t*t*p2[k] + t**3*p3[k] for k in range(3)])
        for point in points_to_check:
            x, y, z = point
            if item["location_id"] in ("entrance", "courtyard"):
                safe = 11.4 <= x <= 14.6 and -23 <= z <= -11.8 and 1.5 <= y <= 2.2
            elif item["location_id"] == "lobby":
                safe = 12.4 <= x <= 13.6 and -18 <= z <= -4 and 1.5 <= y <= 2.2
            elif item["location_id"] == "dorm_hall":
                safe = 12.4 <= x <= 13.6 and 69.5 <= z <= 76 and 1.5 <= y <= 2.2
            elif item["id"].endswith("_interior"):
                room = ROOMS[item["location_id"]]
                minimum, maximum = INTERIOR_LIMITS[item["location_id"]]
                # Hall approach is admitted separately, with the crossing
                # constrained to the 2.4m shell doorway around room.center.z.
                in_hall = 12.4 <= x <= 13.6
                in_entry = minimum <= x <= maximum and abs(z - room["center"][2]) <= .9
                between = min(maximum, 13) <= x <= max(minimum, 13) and abs(z - room["center"][2]) <= .9
                safe = (in_hall or in_entry or between) and room["center"][1] + 1.5 <= y <= room["center"][1] + 2.2
            else:
                floor = 1 if y > 5 else 0
                safe = 12.4 <= x <= 13.6 and -3 <= z <= 49.6 and floor * 5 + 1.5 <= y <= floor * 5 + 2.2
            if not safe:
                failures.append(f"outside conservative corridor/entry envelope: {item['id']} {point}")
            if item["id"].endswith("_interior"):
                for xmin, xmax, zmin, zmax in INTERIOR_OBSTACLES[item["location_id"]]:
                    if xmin - .25 <= x <= xmax + .25 and zmin - .25 <= z <= zmax + .25:
                        failures.append(f"source obstacle proximity: {item['id']} {point}")
    return failures


def gd_string(value):
    return json.dumps(value, ensure_ascii=False)


def gd_vec(point):
    return "Vector3(%s, %s, %s)" % tuple(format(float(v), ".4f").rstrip("0").rstrip(".") or "0" for v in point)


def write_gd():
    lines = [
        "extends RefCounted",
        "## Authored from the existing campus registry and shell geometry.",
        "## Positions are world-space metres; this module changes no campus content.",
        "",
        "static func _curve(points: PackedVector3Array) -> Curve3D:",
        "\tvar curve := Curve3D.new()",
        "\tcurve.bake_interval = 0.12",
        "\tfor i in points.size():",
        "\t\tvar previous: Vector3 = points[maxi(0, i - 1)]",
        "\t\tvar following: Vector3 = points[mini(points.size() - 1, i + 1)]",
        "\t\tvar tangent: Vector3 = (following - previous) * 0.12",
        "\t\tcurve.add_point(points[i], -tangent if i > 0 else Vector3.ZERO, tangent if i < points.size() - 1 else Vector3.ZERO)",
        "\treturn curve",
        "",
        "static func catalog() -> Array[Dictionary]:",
        "\tvar result: Array[Dictionary] = []",
    ]
    for item in routes:
        location = item["location_id"]
        if location in ("entrance", "courtyard"):
            location = "exterior"
        elif location in ("lobby", "hall_f0", "hall_f1", "dorm_hall"):
            location = "circulation"
        pins = []
        if item["location_id"] in ROOMS:
            pins = [item["location_id"]]
        elif item["id"] == "ground_hall_south":
            pins = ["ac_lab", "shop", "dc_lab", "cafeteria"]
        elif item["id"] == "ground_hall_north":
            pins = ["gym", "tim_hortons", "subway"]
        elif item["id"] == "upper_hall_south":
            pins = ["elm253_lecture", "ety155_lecture", "computer", "library"]
        elif item["id"] == "upper_hall_north":
            pins = ["study", "circuit_studio"]
        points = ", ".join(gd_vec(p) for p in item["points"])
        looks = ", ".join(gd_vec(p) for p in item["look_targets"])
        rooms_gd = ", ".join(gd_string(p) for p in pins)
        lines.extend([
            "\tresult.append({",
            f"\t\t\"id\": {gd_string(item['id'])},",
            f"\t\t\"location\": {gd_string(location)},",
            f"\t\t\"path\": _curve(PackedVector3Array([{points}])),",
            f"\t\t\"look\": PackedVector3Array([{looks}]),",
            f"\t\t\"speed\": {item['speed_mps']},",
            f"\t\t\"transition\": {gd_string(item['transition'])},",
            f"\t\t\"weight\": {item['weight']},",
            f"\t\t\"rooms\": PackedStringArray([{rooms_gd}]),",
            "\t})",
        ])
    lines.append("\treturn result")
    (OUT / "routes.gd").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    failures = validate()
    if failures:
        raise SystemExit("\n".join(failures))
    payload = {"schema": 1, "coordinate_space": "Campus global Godot metres, Y up",
               "camera_radius_m": .25, "source": "actual room_registry.json and campus_world.gd geometry",
               "routes": routes}
    (OUT / "routes.json").write_text(json.dumps(payload, indent=2) + "\n")
    write_gd()
    print(f"Validated {len(routes)} routes and {sum(map(lambda r: len(r['points']), routes))} control points")
