# Campus decor asset pack

Thirteen generated, baked OBJ meshes support the room dressing system and
focused component-shop fit-out. They use
tapered chairs, polygonal vessels, splayed legs, sloped acoustic fins, round
tables, arched lockers, open racks, foliage silhouettes, a faceted service
counter, sloped component board/trays and an oval trading table; the dressing
is therefore not a repeated collection of cube primitives.

Regenerate deterministically from the repository root with
`python tools/campus/decor/generate_meshes.py`. The runtime never runs the
generator. Props have no physics bodies or dynamic lights. Repeated placements
are batched by room and material through `MultiMeshInstance3D`.
