# LabVolt accessory collection

Nine original baked glTF accessories cover three distinct headwear silhouettes, two eyewear designs, paired earrings, a pendant, a watch, and a cosmetic backpack. Every mesh has UVs, normals, multiple PBR texture channels where its construction needs them, and a static original thumbnail.

Models are authored in the existing toon rig's local coordinate spaces: head/eyewear/ears under `Body/Head`, necklace and backpack under `Body`, and the watch under `Body/ArmL`. Head children inherit animation and all nonuniform head proportions directly. Body attachments fit the full `.65–1.4` torso range. The watch uses a positive inverse arm-length scale plus a derived root offset, so its center follows the wrist while its face and strap do not stretch along the arm.

Headwear declares `hair_covering` and conflicts with `hair_volume_high`/`headwear_locked`. Integration should hide only the equipped avatar's legacy `Body/Head/Hair` node while a `hair_covering` item is attached, and restore it on unequip. Do not delete or mutate hair geometry. Cosmetic backpacks conflict with `physical_backpack_visible`, allowing gameplay inventory code to reject the combination or hide its cosmetic skin while the physical pack is in use.
