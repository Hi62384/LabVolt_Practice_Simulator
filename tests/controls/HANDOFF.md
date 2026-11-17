# Held item placement

Run `test_place_item_binding.gd`, `test_placement_input.gd`, and `test_placement_target.gd` with isolated Godot user data. They check the F placement and I inspection defaults, legacy binding migration, routing while inspecting, blocked/unfocused input, key release, echo suppression, remapping, aimed flat surfaces, and the feet fallback when a target is distant or invalid.

Also run `tests/electronics/test_ac_laptops.gd` and `tests/campus/facilities/test_carry_plate.gd` for placement owner, distance, non-finite coordinate, and aimed-floor checks. The target fixture covers host table acceptance and distant-target rejection. The AC laptop service separately checks the physical surface on the host; it requires an in-game placement check because that ray needs the scene's collision geometry.

Then run `tests/menu_startup/test_menu_routes.gd` as described in `tests/menu_startup/HANDOFF.md`. In game, verify F places a held paper, kit, board, food item, AC laptop, portable laptop, and gym item on the aimed flat surface; a distant or invalid target should place it near the player's feet. Left click should still pick up and interact, and right click should still use or inspect the item without placing it. Test both Singleplayer and Host Game.
