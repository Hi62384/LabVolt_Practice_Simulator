# Geometry lane handoff

Provider: `hallway_finish.gd` (copy to `res://scripts/campus/presentation/hallway_finish.gd`). Integration: `INTEGRATION.md`.

## Shared anchor contract

- Main corridor: x=10–16, ground y=0, upper y=5, z=-4–68; exterior portal plane is z=-11.32. Existing side walls and collisions stay authoritative.
- Stairs: x=10–13, z=50–62, rise 0–5. The existing convex ramp collision, 30 visual treads and two longitudinal railings stay authoritative. This provider adds thin tread caps and noncolliding balusters.
- Elevator opening: east side x=16, z=56–60; provider places no edge wall or decoration there.
- Doors: x=10 or x=16, actual z and width from `room_registry.json`; provider puts noncolliding 3.1 m tall dark-blue jambs on the hall face, preserving the entire opening under the existing lintel. It does not add doors or signs.
- Fixed signage owner should use registry numbers and independent plaques beside or over these door anchors. No billboard text from this provider.
- Lighting owner should align fixtures around the existing 6 m spacing (z=-2,4,...,46 on each floor), below ceiling y=4.0/9.0. Provider ceiling panels occupy y=4.0125–4.0375 / 9.0125–9.0375, so ceiling fixtures should remain below y=4.0/9.0.
- Exterior owner threshold: z=-11.32. Provider floor tile pattern starts there but no added wall or ceiling at exterior side.

## Source inspection

- Existing room walls are at x=10/16, thickness 0.16; room openings are `door_width` in registry. Existing header spans y=3–4.
- Ground floor slab top y=0. Upper slab top y=5. New tile tops y=0.017/5.017 with 0.982 m tiles and 0.018 m seams. Ground and upper tiles skip x<13, z=50–62 to preserve the ramp void. No collision is added.
- Existing ceiling slab bottom y=4.05/9.05. New panels top y=4.0375/9.0375, with a 0.0125 m gap.
- Wall finish is 0.01 m outside the structural wall face. Finish, frames, tile, panels and balusters have no collision. Existing collision is untouched.
- Instanced tile and ceiling panel meshes use the shared cube mesh/material cache and 72 m visibility limit; no dynamic lights or unique per-tile nodes.

## Verification status

Source geometry and registry anchors inspected. No Godot runtime, window, network or rendered validation was launched under this lane's restrictions. Integrator and runtime owner must validate parser/import, portal sight lines, walking clearances and screenshots after safe apply.

