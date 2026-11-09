# Cross-station top bar removal candidate

The shared constructor in `scripts/electronics_ui.gd:70-101` is the only source construction path for the Hotbar / Components / My kits / Breadboard / Notebook / IC / PCB builder / Code / Trade top button row. `game.gd:189` mounts this one electronics UI. Every `open(page)` call (component shop, trading, loadout, kits, breadboard, notes, IC/PCB, firmware) entered the same constructor, so the earlier `if page!="shop"` guard fixed only Components and left the row on all other pages. The new user request removes it on every page.

`REMOVE_CROSS_STATION_NAV.patch` is a one-hunk candidate deleting only the shared `tabs` creation, page guard, and cross-station button loop. It keeps the existing title, funds/status, Close action, page dispatch, scroll/body, purchase state, generation guards and business callbacks intact. It does not remove any page-local toolbar or tabs. The patch's full-file SHA preimage is in `REMOVE_CROSS_STATION_NAV.json` and must be checked again by the main owner before applying. No live source was changed during the snapshot.

Source routes preserved by candidate:
- Component shop and trade physical counters: `shop_room.gd:57-63` -> `game.electronics.open(page)`; counter metadata comes from `shop_room.gd:27-38` / component fitout.
- Dorm kit workshop, loadout and notes: `campus/dorms/interactions/personal_station_router.gd:47-61` verifies assigned owner before opening the corresponding page.
- Circuit Studio workstations: `campus/facilities/circuit_studio/interaction_adapter.gd:23-38` validates registered station and action page; dedicated IC/PCB opens `builder_window.gd`, while other pages call electronics UI.
- Intentional I/K shortcuts in `game.gd:380-382` open inventory/kits directly as keyboard access. They do not expose a universal screen switch. Existing local builder actions `electronics_ui.gd:404-413,490,498,531,573` still move within circuit/firmware workflows.

`check_cross_station_nav.py` was run against the SHA-matched candidate. It verified no cross-station row constructor in `open`, retained Close, all ten page dispatches, the three physical/context routes, and the intentional local/keyboard actions. It did not parse GDScript or exercise runtime interaction. The main owner must apply the patch and the runtime owner must test each actual route in its private copy after integration. Screenshot pixels were not inspected; the exact user text and source path identify the row unambiguously.

Owner boundary: `electronics_ui.gd` is main integrator owned. This candidate is staged under review artifacts only. No conflicting owner edits were observed at the instant the SHA check ran; a subsequent change invalidates the candidate and requires rebase. No approval denial or uncertain mutation occurred.
