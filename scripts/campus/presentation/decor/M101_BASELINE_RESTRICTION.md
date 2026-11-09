# M101 equipment baseline restriction

The user has explicitly frozen all existing AC training-device geometry,
materials, hierarchy, scripts, controls, connections, labels and placement.
The earlier `lab_floor_coplanar.patch` touches `equipment_builder.gd`, which
also generates that equipment. **Do not apply that patch from this packet.**
Its source arithmetic remains diagnostic only. A dedicated M101 environment
owner should address floor rendering through a separate environment-only
mount or isolated shell change after baseline review.

Likewise `m101_geometry.patch` changes rack/support geometry in the device
builder and is now withdrawn from integration under the latest instruction.
Keep both patch files as historical evidence only; do not use them as main
integration inputs. This exterior packet does not touch M101 devices.
