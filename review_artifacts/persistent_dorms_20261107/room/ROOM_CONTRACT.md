# Personal room contract

The current physical bay is 7.0 × 11.5 × 4.0 m. Door and entry remain at the corridor wall and center Z. Preserve a 1.5 m clear path from `entry_anchor` toward `room_anchor`, and keep all furniture at least 0.25 m from the door swing. Placement authority owns collision validation; these are its reserved bounds.

Stable furniture IDs: `bed`, `bedside`, `wardrobe`, `study_desk`, `study_chair`, `desk_laptop`, `workshop`, `loadout`, `notes`, `storage_cabinet`, `shelf`, `rug`, `plant`, `ceiling_light`, `bedside_lamp`, `desk_lamp`. Preserve kit, backpack and paper anchors from the existing hall. Only three chosen display project IDs appear at once; decorative project meshes never run electrical simulation.

Use the existing `DormPersonalStationRouter` for workshop, loadout and notes. Wardrobe opens the existing avatar editor with its owned collection. Storage requests go exclusively through the dorm authority contract and ledger receipt API; the room renderer receives public display definitions only. The desk computer uses the M203 session adapter and shared desktop UI, with unsupported browser or execution features shown unavailable. Never materialize private files for visitors.

Palette options: upper wall `f2eee5`, lower wall `82919a`, wood `76604c`, floor `c6c1b5`, bedding `5b827d` by default. Alternate saved wall/floor/bedding choices may change materials, not geometry. Matte shared materials, simple collision, one ceiling panel and two local lamps; stream the interior when entered and release it when empty. Keep exterior windows only on the outward wall.

The current hall builds primitive furniture directly in `dorm_hall.gd`; the integration owner must replace that call with a furnished interior scene factory after persistent authority and room streaming are adopted. Current `peer:<id>` coordinator ownership and release-on-leave behavior do not satisfy this contract. Source inspection cannot establish that the user's missing assignment is fixed.

Candidate `room_interior.gd` builds the streamed mesh set and interactive targets. `room_adapter.gd` gates entry, routes owner interactions, and releases the room when its final occupant leaves. Personal actions are explicit callables bound by the authority coordinator's `_sync_interiors`: wardrobe to `_open_wardrobe`, bed to `game.dorm_rest.request(room)`, chair to `_request_desk_chair`, and storage to `_open_storage`. Computer calls the coordinator's `request_personal_computer(room)`; it registers the M203 station as `personal_` plus the physical bay, so a direct `dorm_` station name was incorrect. Its host checks chair occupancy and session roster. Storage writes use the coordinator's authenticated `storage_transfer`, never this renderer's state.

Reference image pixels were previously inspected by the root thread: teal bedding, light walls, desk/laptop, wardrobe, lamps and rug. This contract uses those observed features only.
