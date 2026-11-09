# Remove M102 Campus Return station

The source entity is the `ShopRoom.build()` row at `(26,0,7)` with label
`CAMPUS / RETURN` and page `exit`. The staged patch removes its visible blue
box, billboard, and interaction collision together by removing that one row.
`ShopRoom.leave()` remains available via the existing Escape handling in
`game.gd`; the campus shell door and corridor are unaffected. The `interact()`
`page == "exit"` branch can remain for compatibility with old targets, but no
new exit target is built. Do not replace this with floating text.

Current `scripts/shop_room.gd` SHA-256 before adoption:
`8eb4ed6f57d9e667945d324984bb1efa36931a35b176fe404cc56ec7311261b`.
Apply only if the current row still matches; main owns the shared source.
