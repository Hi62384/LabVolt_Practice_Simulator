# Bounded M108 static validation

- Registry M108: center `(26,0,47)`, footprint `20 x 12 m`, west entrance `(16,0,47)`, width `2.4 m`.
- Candidate uses 50 authored box calls plus bounded loops, shared box meshes and materials, three nonshadow ceiling lights, no collision, network RPC, per-frame animation, or save mutation.
- Counter shell matches the existing 6 m service body, with 6.22 m countertop, eight trays at `y=1.23`, foods at `y=1.274`, support posts and glass at `y=1.47–1.68`. The original collision stays authoritative. The back aisle from counter to wall shelving is about 2.3 m.
- Four table and chair centers match `FacilityRoom._restaurant`; the existing seat station ids and `2.5 m` reachability remain unchanged. The west entry lane is left clear. The east `WindowInset` groups are retained by the mounting patch.
- Menu text iterates the host's live venue entries. At this preimage, its three Subway items are Vegetable sub `$7`, Chicken sub `$9`, and Water `$2`. No unsupported purchasable categories or prices were added.
- `campus_integration.gd` SHA256 preimage: `90de50b3d38b1d90e81e8b24defcb9b55877bbf1ba0d6754614bfb028162695e`. `facility_room.gd`: `1ded4bbe3aa6db7ede49b88b7f5415a39bf10584b69ea6d88f90410a2f60dd76`. `facility_host.gd`: `b127b6cb72accc276d6125edfc8d15385237c2b4c8a4279e9f46b72d3876086f`.

Actual Godot import, mesh visibility, navigation, menu readability, purchase and multiplayer assertions, performance, and screenshots are pending the designated runtime owner's safe boundary. This candidate did not launch an engine, use a player session, or alter saves.
