Apply only after rechecking the preimage hashes in `INTEGRATION.md`.

1. Copy both candidate `.gd` files into `scripts/campus/facilities/clothing_store/`.
2. In `store_panel.gd`, add `signal legacy_purchase_requested(request: Dictionary)`
   and `signal legacy_wear_requested(item_id: String)`, plus a `legacy_section`
   member. In `_ready()`, immediately after `var root := VBoxContainer.new(); ... add_child(root)`, add:

   ```gdscript
   legacy_section = preload("res://scripts/campus/facilities/clothing_store/legacy_wear_section.gd").new()
   root.add_child(legacy_section)
   legacy_section.purchase_requested.connect(func(request): legacy_purchase_requested.emit(request))
   legacy_section.wear_requested.connect(func(id): legacy_wear_requested.emit(id))
   ```

   In `open_profile`, after `session.open(snapshot)`, call
   `legacy_section.open_profile(snapshot)`. Add
   `accept_legacy_receipt(result, snapshot)` forwarding to
   `legacy_section.accept_receipt(result, snapshot)`. Set
   `legacy_section.request_id_factory = request_id_factory` when opening.
   This puts visible cards in the already reachable M207 panel. Keep the
   existing avatar categories, search and preview unchanged.

3. In `campus_integration.gd::_install_clothing_store`, connect
   `clothing_panel.legacy_purchase_requested` separately from its avatar
   signal. For online, set a separate `legacy_pending` request ID and call
   `profile.authority_submit.call("cosmetic", request.args)`. For offline,
   call `profile.buy_cosmetic(request.args[0])`; the method already saves
   atomically and returns a status string. Build result `{"ok":
   profile.operation_succeeded, "message": message}` and call
   `accept_legacy_receipt(result, profile.data)`. In the existing
   `operation_result` callback, handle `op == "cosmetic"` only when
   `legacy_pending` is set, call `accept_legacy_receipt(result,
   game.electronics.profile.data)` and clear the pending ID. Do not route
   this through `session.accept_authoritative_result`.

4. Connect `legacy_wear_requested` to the exact existing Wear sequence from
   `electronics_ui.gd:123-128`: require selected character, parse its
   `character.json` into a Dictionary, use
   `LegacyCosmeticAdapter.wear_settings(id, profile.data)` (reject empty),
   `config.merge(settings, true)`, call
   `game.characters.save_character(selected, config)`, emit
   `game.characters.changed` on success, and report status with
   `legacy_section.show_wear_result`. This retains character rendering and
   multiplayer appearance broadcast. Never alter the profile's ownership on
   Wear.

5. Only then remove `electronics_ui.gd`'s block starting at
   `label(body,"Laboratory accessories · saved to this character")` through
   its `for id in profile.COSMETICS` closure. Keep the capacity button after
   it, plus analyzer, components and boxes. The `cosmetic` ledger branch and
   `ElectronicsProfile.COSMETICS` stay intact.
