# Custom Circuit Studio integration

This package is additive and owns no profile, inventory, authority or circuit state. IC and PCB targets now open separate local workstation windows through `builder_window.gd`. IC locks the existing package form to IC; PCB locks it to PCB and embeds the existing `pcb_design/editor.gd` for outline/copper. The form retains `package_store.save_package`; the board editor retains `document.save_copy`; purchase/craft retain `profile.obtain_ic`. Source editing, firmware and kits remain explicit handoffs to existing electronics pages. Source inspection found no standalone custom-package file import/export action to relocate; firmware image import remains on the delegated Code page.

The five station actions are `ic_builder`, `pcb_builder`, `prototype_bench`, `firmware_console`, `kit_library`. IC and PCB route keys are `studio_ic` and `studio_pcb`, consumed by the adapter rather than passed to `electronics.open`. Shared main dispatch still needs only `controller.interact(target)`. The independent builder windows contain no universal electronics tab bar. A shared design-system owner may apply a reusable Theme to each window after it is created; no dependency on an unpublished theme API is introduced.

## Shared hooks (main integrator)

Preimages observed 2026-11-06 (SHA-256): `game.gd` `F451FBA3D1132A5E7616DF4B4FF34FFA5F81D42F95A68A12A633354981BEB251`; `shop_room.gd` `3A5FDA0FFD807BE261FDEDD5B195447BFF959EDDD8FFAB73042FCEC5887D1031`; registry JSON `77CAC595787C0AFEE16BE22E1DF18FF8952AAA1534F11CCC1DD37AD86999BB25`. Rebase these hooks if those preimages changed; do not overwrite concurrent work.

1. Merge `assets/campus/circuit_studio/room.json.room` into `assets/campus/world/room_registry.json.rooms`. M208 uses the currently unallocated upper-floor east slot at centre `(26,5,47)`, opposite the upper-floor west gap and connected to the existing floor-2 corridor. Rebase/relocate it if concurrent registry work has claimed that slot, keeping the manifest and content coordinates aligned. Do not mount until registry validation succeeds.
2. After `electronics`, `shop_room` and `campus` exist in `game.gd`, instantiate `CircuitStudioMountController`, add it to the game, and call `install(self,campus)`. Store it (for example `circuit_studio`) for interaction dispatch.
3. In `activate()`, route `circuit_studio.interact(current_target)` before `shop_room.interact(...)`.
4. In the shop builder, find the legacy station whose `page == "ics"`. Set its visibility and collision layer from `mount_controller.legacy_custom_circuits_enabled()` only after `install()` returns. A failed or partial mount must leave that station visible and interactive. Do not delete the legacy station.
5. Register/map/directory/signage code should use the merged registry record. The content itself calls `campus.register_content("circuit_studio",room)` and contains only presentation collision plus local interaction metadata; it adds no RPC or personal save state.

The coordinates are a contract proposal. Main owns final shared-world placement and must verify the slot remains unallocated before integration.
