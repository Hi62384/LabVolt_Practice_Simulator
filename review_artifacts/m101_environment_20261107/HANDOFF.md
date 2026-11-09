# M101 environment candidate

This packet is private and has not changed shared production. Copy `m101_environment.gd` to `scripts/campus/presentation/decor/m101_environment.gd`, then apply `campus_integration.patch` to `scripts/campus_integration.gd` only if `campus_integration.preimage.gd` still matches. The patch mounts the new room finish through the existing registry and streaming content registration, and omits M101 from the older generic teaching finish to avoid overlapping trim and signs. No AC builder, device, panel asset, station node or equipment transform is edited.

Run `python review_artifacts/m101_environment_20261107/check_candidate.py` before integration and the AC guard `python review_artifacts/physical_instruments_20261106/ac_baseline_guard.py` before and after. At packet creation both passed. The private check covers source boundaries, tile/seam elevation, room bounds and registration. It cannot prove rendered appearance or gameplay. The runtime owner must check M101 lighting, bench and chair clearances, instructor teaching, device readability, wiring, multiplayer access and screenshots in the running game.

The new module uses shared box meshes and matte materials, no new collision, no actual lights, and no node traversal into equipment. The lighting coordinator can align separate neutral lighting with the six fixture visuals at X = -6/0/6, Z = 0/6, Y ≈ 4.0. Existing equipment and instructor positions stay fixed. North wall teaching details are shallow and remain off the floor. The south wall's existing teaching panels remain in place.

Integration owner: inspect any concurrent changes to `campus_integration.gd` and rebase the three mount lines if needed. Do not apply the historical `m101_geometry.patch` or `lab_floor_coplanar.patch`.
