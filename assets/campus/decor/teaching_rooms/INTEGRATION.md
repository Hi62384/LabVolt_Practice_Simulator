# Teaching room finish

`TeachingRoomFinish.mount_approved(campus, campus.registry, ids)` mounts
architectural trim, wall pilasters, ceiling baffles, and a physical room-number
sign through `register_content`. It covers M101, M103, M201, M202, M203.

Use one approved ID at a time after its existing furniture and functional
equipment are present. Once `mounted` contains that ID, exclude the same ID
from the older generic `CampusDecor` allowlist so furnishings do not stack.
M101 retains its existing style and furnishings; this finish adds only subtle
architectural details. Apply `m101_geometry.patch` separately at a safe point.

No gameplay collisions, dynamic lighting, instructional text, or device bodies
are added. Furniture and lab controls remain in their existing owners.
