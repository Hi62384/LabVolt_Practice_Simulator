# Entrance geometry packet

Entry: `res://review_artifacts/campus_entrance_20261107/geometry/exterior_finish.gd`.
Main can instantiate this node under `campus` and call `mount(campus)` once after
the persistent campus shell builds. This is private staging; no production file
has been edited by this packet. Current `campus_world.gd` preimage SHA-256 is
`5393697770ebcf3b523f6129e54ffac66fc1951c9258e218341c1ee9b468b424`.

Actual anchors: spawn `(13,0,-18)`, x10..16 entrance opening at z=-11,
ground corridor x10..16, building face in two existing x[-10,10] and [16,36]
segments. Frame uprights sit outside that opening, leaving at least 6m clear;
the center approach has no new collision. Benches and trees stay in lateral
courtyard bands. The window panels are opaque dark glass on existing wall
sections; visible interiors through windows would require shell cutouts and a
separate door/window collision review. No false transparency claim is made.

The packet adds facade color bands, framed windows, roofline trim, portal frame,
path edging, small benches and eight-segment trees. It uses seven shared matte
materials and no physics, scripts per frame, extra NPCs, lights, or text. The
signage owner should use portal frame at x13, y4.54, z-11.32; lighting owner
should use the entrance opening and avoid duplicate lamp poles here. Geometry
does not supply signs or illumination.

After safe runtime integration: capture front, angled and inside views; confirm
entrance traversal, room routes, shadows, no facade clipping, and performance.
Offline bounds checks do not establish visual acceptance.
