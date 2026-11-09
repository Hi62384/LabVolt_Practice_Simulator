# Expansion fixture

Entry point: `res://tests/campus/world/expansion/expansion_fixture.gd` as a
headless Godot SceneTree script. It needs two physics frames and one run method;
no Main scene, network peer, saves, or UI are created. It instantiates the
actual Campus scene and presentation providers with synthetic eight-player dorm
capacity. It checks 16 generated shells, routes, teaching/social/service mounts,
shop/trade page metadata, dorm door count, and generated corridor floor rays.

Run only after the user's live game session is finished. This fixture is
prepared, not executed. The static checks cannot prove visual quality, player
camera occlusion, furniture clearance outside authored providers, or complete
shop/economy and IC/PCB transaction behavior. Those need the Main integration
tests and playtest. It does not mount the same provider twice in the same scene.
