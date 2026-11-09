# M102 furniture candidate

Current source: `game.gd` calls `ShopRoom.build_campus()`, which mounts
`component_shop_fitout.gd`. Thus the lumpy yellow trading table, awkward chairs,
and large parts label are visible from this provider. Its current imported OBJ
trading top is composed of overlapping cylindrical discs and two raised tray
meshes; the chairs are imported OBJ parts with rotations and centers at ±1.25 m.
The candidate uses one Godot cylinder top with trays entirely above the surface,
four simple legged chairs placed at ±1.52 m, a component counter with distinct
parts bins, and no Label3D or billboard. It retains exact shop/trade action
metadata and current local station centers, so `ShopRoom.build()` can still move
trade to `(26,0,-1)` after contract success.

Main-owned adoption: change the single preload in `ShopRoom.build()` from
`res://scripts/campus/presentation/decor/component_shop_fitout.gd` to
`res://scripts/campus/presentation/decor/component_shop_fitout_candidate.gd`.
Then remove the legacy billboard titles and blue counter bodies for kits/ics/
inventory/exit only after their destination providers and return route mount.
The current `ShopRoom` has old box stations for those four pages and a fixed
`ELECTRONICS WORKSHOP` label; this candidate cannot retire them on its own.

Preimages SHA-256: `component_shop_fitout.gd`
`93d887626db0aa7eddbd500b84b8066da82a4b57cd169125742d50908896db52`;
`shop_room.gd` `8eb4ed6f57d9e667945d324984bb1efa36931a35b176fe404cc56ec7311261b`.
No runtime or screenshot acceptance is claimed for the candidate.
