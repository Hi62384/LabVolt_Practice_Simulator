# Integrator handoff

1. Verify `scripts/toon_character.gd` still has SHA-256 `D3C29FF6941E29BA85122DCFAC39D126919083A65837AF9A08E4CCE3689A538D`. If not, rebase the one-line deletion manually rather than forcing the patch.
2. Apply `minimal_fix.patch` to the shared generator.
3. Do not change `interaction_presentation`, inventory, session, network, or save code; those paths are behaving correctly.
4. After the user's live game is stopped at a safe point, regenerate `assets/default_avatar.glb` through the existing supported character generation flow. Do not overwrite active user saves.
5. Run `verify_source_data.ps1` before and after regeneration. Before regeneration it reports the known three baked details; after regeneration it must report zero anonymous right-arm detail children while retaining `Hand2` and `Thumb2`.
6. Runtime acceptance, when safe: launch normally, enter the world with no cable/tool selected, confirm no first-person arm is visible; perform a switch/knob interaction and confirm a natural hand appears briefly; pick up and return a cable and confirm its endpoint follows the hand; observe a remote avatar's idle/walk/seated animation.

The patch intentionally does not rewrite custom avatar GLBs or saved choices.
