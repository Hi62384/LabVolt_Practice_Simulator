# Campus decor integration

This package is intentionally additive. It does not own the campus generator,
room collisions, navigation, environment, lighting, interactions, authority or
saves.

Preferred streaming hook after the existing `Campus.tscn` instance is ready:

```gdscript
var decor := CampusDecor.new()
decor.name = "CampusDecor"
add_child(decor)
decor.register_streamed(campus, approved_room_ids)
```

Each completed root is passed back through the campus's existing
`register_content` API, so zone visibility remains owned by the established
streamer rather than by this package.

If the existing loader budget is already fully allocated, use the eager hook
instead (14 room-local roots, 56 MultiMesh draw instances total):

```gdscript
var decor := CampusDecor.new()
decor.name = "CampusDecor"
add_child(decor)
var result := decor.build_all(campus.registry, campus, approved_room_ids)
```

The integrator should use only one hook. Pass a reviewed `approved_room_ids`
allowlist during visual integration. An empty array retains the complete-pack
behavior, but must not be used while the identity of a room whose existing
decoration should be preserved is unresolved. Excluding a room leaves all of
its current furnishings and style untouched.

Props have no collision or scripts that
process each frame, so movement and interaction envelopes remain controlled by
the existing world. Do not add collisions to chairs/tables in this package
unless navigation is regenerated and all functional seats/benches are retested.

## Screenshot/clipping evidence status

Materialization of the four supplied Library attachments was attempted through
the supported attachment reader. All four exact reads were denied with
`Stopped. Resume locally in the dashboard; MCP cannot grant itself permission`.
No alternate path was used and no screenshot pixel-inspection claim is made.

Static prevention still applied: authoritative registry bounds, a 0.15 m wall
origin inset, 1.25 m door-origin clearance, duplicate-transform detection,
explicit functional-zone notes, and no prop collision. The static validator
cannot detect intersections with generator-owned furniture whose extents are
not published. The main integrator should run the existing visual checks once
the user's active playtest has ended, especially for lab benches and lecture
desks.
