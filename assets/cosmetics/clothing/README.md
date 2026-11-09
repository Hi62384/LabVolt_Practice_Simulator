# LabVolt clothing starter slice

Seven original, baked glTF garments target the current `labvolt_toon_v1` segmented character: fitted tee, hoodie, field jacket, lab coat, jeans, shorts, and skirt. They use authored UV streams and local 128px albedo, normal, and metallic/roughness maps. The 384px card images are static catalog thumbnails, not claims of in-engine visual acceptance.

The garment nodes intentionally follow the actual animation hierarchy. `Torso`/`Waist` attach to `Body`, sleeves to `Body/ArmL` and `Body/ArmR`, and lower panels to `LegL`/`LegR`. The overlapping waist/hip geometry bridges the leg seam. This is a segmented deformation solution for the existing non-Skeleton3D toon, not rigid whole-garment parenting.

Fit accepts the shared core's complete 0.65–1.40 body range. Torso rows follow the toon's actual waist-to-shoulder envelope, while limb width and length controls affect their corresponding baked segments. Sleeve and leg meshes extend slightly past their joint origins so mixed length/width extremes do not create an intentional open seam.

Rebuild with `python tools/cosmetics/clothing/build_clothing_assets.py` and validate with `python tools/cosmetics/clothing/validate_clothing_assets.py`. Both are bounded offline operations.
