# Billboard text removal candidate

Production sources were not edited. `billboard_removal.patch` targets these SHA-256 preimages: `game.gd` FBE9FA5AC3EDDDF08DCF2EC1A7AF8D00A9C8036959122D3B1B2E32015894A007; `lab_chat.gd` 3425EB2B665C2175E5D74B75C6A8F356D724064341DB121D0CEAB1B00D81320F; `school_world.gd` 45724F288351CB059E1C4059AA9F3345B999AD2C7683BF4D5D1929F301CB8615.

The patch removes avatar name labels, overhead chat bubbles, and the instructor badge. Chat remains in the existing bottom-left team log with sender names and 40-message history. Instructor identification remains in the teacher interaction target metadata (`role=teacher`, `label=Lab instructor`). Avatar identity remains in the session roster and public profile UI; the old overhead label update loop is removed.

`shop_room.gd:37` still explicitly billboards a product title. Decor owner must remove that callsite in its M102 fitout change. `campus_social.gd:97` only toggles the now removed overhead name label and should remove that loop at integration. Both are excluded from this patch under ownership.

Other active fixed `Label3D` paths: campus room number and corridor signage; equipment_builder/device and physical instrument readouts; school whiteboard and recycling bin; DC lab display; shop and facility menus; classroom/decor signs; lab challenge labels; board component labels. These are not billboarded by source. Audit their physical front and back placement individually, retaining instrument and course information on its actual surface. `look_at` matches elsewhere are cameras, not user-facing text nodes. The only explicit text billboard callsites in active scripts are the three patched sources plus `shop_room.gd`.

`tests/campus/signage/no_billboard_text.ps1` is intended as a post-integration static gate. It will fail until the decor-owned `shop_room.gd` billboard line is removed. No Godot process or user window was touched.
