# Core flythrough handoff

The staged controller follows the real campus via the route owner's current 28-route catalog. It uses the existing campus World3D, selects one weighted pass through the valid shots before refilling, and uses the existing zone streamer to activate current and upcoming room content. No authored campus, M101 equipment model, device parent, material, save, or provider file is patched.

A distant transition renders the outgoing pose once to a temporary capped-resolution SubViewport sharing the same World3D. A CanvasLayer between the world and front menu fades out the frozen texture as the live camera starts the new route. Matching continuous endpoints can use the same camera directly. Host and Join hold the shot while they start. Successful capture makes the player camera current, detaches the camera controller and its viewport/overlay, restores the streamer to the player, and restores saved callback and visibility states. Immediate start errors, asynchronous Join failure, cancellation, and home after leaving restore movement. The existing shop return through front.home() also restarts the tour. The quiet Master-bus ambience smooths between indoor and outdoor settings.

## Apply

1. Verify the current working files against PREIMAGES.json, then run check_offline.py from the project root. The 21 exact substitutions are separated from the visual owner's hunks. The front menu preimage includes the MTH repair. If any live file changed, check the current exact anchors and regenerate staged preimages using stage_hooks.py rather than overwriting the newer source.
2. Back up the matched live files. Install the three scripts from core/new/ in their matching scripts/ paths. Install routes/routes.gd beside them as routes.gd before running the engine.
3. Apply the three core .patch files for game.gd, zone_streamer.gd, and front_menu.gd. The visual owner's FRONT_MENU_VISUAL.patch is an anchor manifest, with unnumbered @@ separators. Apply those exact old/new spans after the core front_menu patch. The offline check verified that order against the current visual artifact. Core removes only the obsolete lab preview camera writer and unused clock. The character gallery continues to use its own SubViewport.
4. Record fresh final hashes after composing both menu patches. The postimage hash for front_menu in PREIMAGES.json is the core-only result.

The core keeps the baseline eager construction of gameplay geometry and services so Host/Join, classroom and provider APIs, and the existing Shop entry can use the same instance. It limits active registered presentation zones during the tour, and suspends selected frame callbacks while leaving their signal and RPC entry points intact. Existing unregistered campus shells and furnishings continue to use normal world culling. Existing Session networking remains offline until Host or Join is explicitly chosen.

## Verification

Passed the offline patch applicability check, exact preimage and postimage hash checks, core/visual menu composition, preload path closure, and the route owner's source envelope audit. Also checked route IDs, room pins and travel easing with the 28-route catalog.

The runtime clearance check tests a 0.24 m sphere at 0.18 m intervals against campus solids and interaction bodies, at most 12 samples per physics tick. It checks the exact baked positions used by the controller before travel, waits for pinned rooms, and skips obstructed or timed-out shots. Check runtime warnings for rejected route ID and position. Mesh-only furnishings, transitions, overlay framing, audio character, and perceived performance require visual and live verification.

Runtime pending with the runtime owner under fresh resource limits. Verify initial camera and later interior shots, the outgoing texture under GL Compatibility, no black frames or clipping, 1920×1080 and lower settings, all seven menu actions, failed and canceled Join, successful Host/Join including formal courses, return and shop round trips, and that the camera/transition viewport are released on repeated entry. Capture screenshots of actual exterior, hallway, educational and facility views. No Godot, server, CUA, screenshots, or live save operations were run in this handoff.
