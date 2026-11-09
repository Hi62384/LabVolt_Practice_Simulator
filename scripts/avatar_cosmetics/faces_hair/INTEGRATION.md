# Integration handoff

Merge every entry from `res://assets/cosmetics/faces_hair/catalog.json` through
the shared catalog collector. Do not duplicate or rename IDs.

For resolved slots `face`, `hair`, and `facial_hair`, call:

1. `FacesHairProvider.instantiate(definition, sanitized_parameters, body)`
2. `FacesHairProvider.attach_to_avatar(avatar, instance, definition)`

Keep the instance as the equip handle. It is parented to `Body/Head`; do not
free it after attachment. Before freeing or replacing it, call
`FacesHairProvider.detach_from_avatar(avatar, instance)`; legacy nodes are
reference-counted per category and restored to their exact prior visibility.
The existing renderer currently handles only footwear, so this hook is required
in the integration owner's shared file.

Do not add inverse head-fit scaling in the renderer. `Body/Head` already carries
the toon builder's `head * head_width/head_height` scale, and these assets are
authored in that node's local coordinates. This preserves the full core range
of 0.65–1.4 and mixed head-size/proportion extremes. Hair `length` selects baked
variant scenes; it never scales the whole hairstyle to simulate length.

The accessories catalog rejects bulky hair through the symmetric
`hair_volume_high` conflict. Only Cloud Curls and Braided Bun carry that tag;
ordinary crop, bob, waves, and ponytail styles remain hat-compatible under the
current accessories contract.

The face asset replaces eyes, brows, nose, mouth, and optional skin details as
one preset. The provider recognizes the current unnamed procedural brow/mouth
CylinderMesh links by their direct-parent and vertical bands; a future named
`Mouth`/`Brows` group in the shared toon builder would be a cleaner seam. This
lane did not modify that owner-controlled file. Facial animation beyond rigid
head motion requires a future named face-deformation contract.
