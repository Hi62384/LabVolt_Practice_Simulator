# Default held-object diagnosis

## Finding

The reported “AirPods” are not a starter item, saved equipment selection, probe, cable, or duplicated cosmetic. They are the default toon rig's three separate finger-detail cylinders copied into the first-person interaction arm.

The avatar generator creates a real palm (`Hand`), a real thumb (`Thumb`), and then three very thin, darkened-skin cylinders on the front of each palm:

```gdscript
for f in 3:link(arm,Vector3(-.032+f*.026,-.50,.052),Vector3(-.032+f*.026,-.535,.045),.003,material(Color(c.skin).darkened(.18).to_html()))
```

The shipped `assets/default_avatar.glb` proves those are baked geometry. `ArmR` has the expected `Sleeve2`, `Cuff2`, `Hand2`, and `Thumb2`, plus exactly three anonymous mesh children (`_MeshInstance3D_11`, `_MeshInstance3D_12`, `_MeshInstance3D_13`) at the finger-detail coordinates. There are no `Tool`, `Probe`, `Cable`, `Pod`, `HeldItem`, or equipment nodes in the arm.

The first-person presentation bridge duplicates only `ArmR`. It does not create or equip a prop. `actor.gd::_refresh()` sets that duplicate visible only while an accepted interaction or an actually-owned open-ended cable hold is active. Thus the apparent objects are hand surface geometry seen close to the camera, not a default held-item state.

The three cylinders sit at the palm's forward surface and use a contrasting dark material. At first-person scale they read as three independent stems instead of finger definition. The palm and thumb remain valid hand geometry and must not be deleted.

## Minimal safe correction

Apply `minimal_fix.patch`, then regenerate `assets/default_avatar.glb` from the corrected generator through the project's normal avatar generation flow when the user's live game is no longer running.

The patch removes only the three cosmetic palm-line cylinders. It preserves:

- palm and thumb meshes;
- arm, sleeve, cuff, rest pose, animations, and hand-size scaling;
- tool/cable equip and unequip state;
- accepted interaction gestures and carried cable anchoring;
- remote multiplayer appearance and authority;
- saved profile/equipment state.

No migration or save rewrite is required. Existing custom avatar GLBs retain their baked palm lines until they are intentionally re-saved; this is preferable to modifying active or historical saves. If desired, the integrator can later regenerate user-selected avatars through the existing explicit character-save UI.

## Screenshot limitation

The referenced Library attachment `libfile_c49dc549d0808191aea1ca4f20f63c1c` was not materialized into this delegated thread/workspace, and no supported Library materialization tool was exposed here. I did not invent a URL or claim pixel inspection. The source and shipped GLB evidence above independently identify the only object-like meshes attached to the default first-person hand.

## Preimage hashes (SHA-256)

```text
15BB3434CDCC166F57808832A6B457A0373F3CD01DD0DA4D2A3C7062A27AF466  assets/default_avatar.glb
D3C29FF6941E29BA85122DCFAC39D126919083A65837AF9A08E4CCE3689A538D  scripts/toon_character.gd
99C6DA455EB5E24211E920135AA01A62F7DB38147AAF1FBB4121BA80F58AEB5B  scripts/interaction_presentation/actor.gd
F32ECADD2FFF48FC80669DAB3BA0060995BE35BAB9C5F43249B62D6B5286C7D4  scripts/interaction_presentation/bridge.gd
5807038E0A5F3962D9B93EE84F40E3E28B5E30E59A036D83CE6C942A8383E37D  scripts/interaction_presentation/timeline.gd
F451FBA3D1132A5E7616DF4B4FF34FFA5F81D42F95A68A12A633354981BEB251  scripts/game.gd
CB6B505711D55EDB0AC47BD7CC6D876B0D8AFB28B6B3A4164E78EE6004230A4A  scripts/avatar_model.gd
```

## Offline checks performed

- Parsed the GLB JSON chunk directly without starting Godot.
- Confirmed 84 nodes and 77 meshes in the shipped avatar.
- Enumerated both arm child sets and their transforms.
- Traced local avatar creation, arm duplication, visibility gating, hold reconciliation, cable ownership reset, and remote avatar binding.
- Searched source/data for held-item, starter-item, tool, probe, and equipment defaults.

No runtime/render/GUI acceptance is claimed.
