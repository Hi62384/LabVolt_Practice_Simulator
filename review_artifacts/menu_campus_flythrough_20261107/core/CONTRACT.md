# Route API

Install at res://scripts/campus/presentation/menu_flythrough/routes.gd.
Extend RefCounted and implement static func catalog() -> Array[Dictionary].

- id: String unique and nonempty.
- location: String real registry room ID, or "exterior" / "circulation".
- path: Curve3D in world coordinates with authored Bezier handles, at least two points.
- look: PackedVector3Array absolute world targets, at least two, spaced uniformly across normalized baked distance.
- speed: float positive meters per second. Duration is baked length divided by speed, with time easing at each end.
- transition: String optional, "crossfade" by default. "continuous" permits a matching endpoint and viewing direction. Incompatible endpoints crossfade.
- weight: float optional, positive, default 1.
- rooms: PackedStringArray optional rooms to pin in addition to a valid location room. Include rooms visible through open portals where needed.

Use actual gameplay geometry. Offline clearance and runtime screenshot validation are separate checks.
