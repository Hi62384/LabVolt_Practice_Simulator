# Source audit — integrated packing/final-three refresh (v4)

New isolated project-practice-docs-j was copied from immutable snapshot J and all 1020 baseline files were hash-verified. H and frozen documentation v1 remain unchanged. Line numbers below refer to J; current Main hashes and lines are also recorded.

| Topic | J source anchor | Main matches J |
|---|---|---|
| Hole groups and rail breaks | [scripts/breadboard_model.gd:13](../../scripts/breadboard_model.gd) | yes |
| Default external port mappings | [scripts/breadboard_model.gd:7](../../scripts/breadboard_model.gd) | yes |
| Board capacity limits | [scripts/breadboard_model.gd:20](../../scripts/breadboard_model.gd) | yes |
| Electronics tab names | [scripts/electronics_ui.gd:59](../../scripts/electronics_ui.gd) | yes |
| Board gesture instructions | [scripts/electronics_ui.gd:140](../../scripts/electronics_ui.gd) | yes |
| Automatic board save | [scripts/electronics_ui.gd:216](../../scripts/electronics_ui.gd) | yes |
| Port fields commit on Enter | [scripts/electronics_ui.gd:128](../../scripts/electronics_ui.gd) | yes |
| Deployment stock and proximity | [scripts/electronics_ui.gd:227](../../scripts/electronics_ui.gd) | yes |
| New empty design and package actions | [scripts/electronics_ui.gd:281](../../scripts/electronics_ui.gd) | yes |
| Starter stock and character save path | [scripts/electronics_profile.gd:34](../../scripts/electronics_profile.gd) | yes |
| Resistor and basic model ratings | [scripts/electronics_catalog.gd:11](../../scripts/electronics_catalog.gd) | yes |
| Catalog composition | [scripts/electronics_catalog.gd:41](../../scripts/electronics_catalog.gd) | yes |
| DC source controls | [scripts/dc_ui.gd:56](../../scripts/dc_ui.gd) | yes |
| Meter connections and fuse | [scripts/dc_ui.gd:84](../../scripts/dc_ui.gd) | yes |
| Generator amplitude and frequency limits | [scripts/dc_ui.gd:95](../../scripts/dc_ui.gd) | yes |
| Lead attachment controls | [scripts/dc_ui.gd:113](../../scripts/dc_ui.gd) | yes |
| DC panel/board interaction | [scripts/dc_lab.gd:152](../../scripts/dc_lab.gd) | yes |
| DC terminal names | [scripts/dc_station.gd:3](../../scripts/dc_station.gd) | yes |
| Scope common ground | [scripts/dc_station.gd:51](../../scripts/dc_station.gd) | yes |
| Generator enable independent of DC master | [scripts/dc_station.gd:74](../../scripts/dc_station.gd) | yes |
| AC ammeter common and ranges | [scripts/equipment_builder.gd:319](../../scripts/equipment_builder.gd) | yes |
| Historical 150 printed 100 | [scripts/equipment_builder.gd:342](../../scripts/equipment_builder.gd) | yes |
| Historical 300 printed 250 | [scripts/equipment_builder.gd:343](../../scripts/equipment_builder.gd) | yes |
| Generated physical rack instructions | [scripts/beginner_bench_instructions.gd:31](../../scripts/beginner_bench_instructions.gd) | yes |
| Generated meter series insertion | [scripts/beginner_bench_instructions.gd:47](../../scripts/beginner_bench_instructions.gd) | yes |
| Equipment inspection and rack labels | [scripts/equipment_guide.gd:4](../../scripts/equipment_guide.gd) | yes |
| Package form and save action | [scripts/package_editor/package_form.gd:75](../../scripts/package_editor/package_form.gd) | yes |
| Package electrical hole mapping | [scripts/package_editor/package_store.gd:18](../../scripts/package_editor/package_store.gd) | yes |
| Saved package content identity | [scripts/package_editor/package_store.gd:20](../../scripts/package_editor/package_store.gd) | yes |
| Physical pin anchor geometry | [scripts/package_editor/package_geometry.gd:65](../../scripts/package_editor/package_geometry.gd) | yes |
| Explicit package placement gesture | [scripts/breadboard_canvas.gd:153](../../scripts/breadboard_canvas.gd) | yes |
| Custom circuit nesting limits | [scripts/custom_circuit.gd:17](../../scripts/custom_circuit.gd) | yes |
| Custom circuit direct budgets | [scripts/custom_circuit.gd:21](../../scripts/custom_circuit.gd) | yes |
| Commercial model limits | [scripts/commercial_devices/catalog.gd:20](../../scripts/commercial_devices/catalog.gd) | yes |
| Educational display protocol limits | [scripts/io_devices/catalog.gd:16](../../scripts/io_devices/catalog.gd) | yes |
| LVScript controls and distinction | [scripts/firmware_ide.gd:24](../../scripts/firmware_ide.gd) | yes |
| Native board target catalog | [scripts/firmware_backends/native_boards.gd:5](../../scripts/firmware_backends/native_boards.gd) | yes |
| Native live ownership and saved drafts | [scripts/firmware_backends/native_studio.gd:67](../../scripts/firmware_backends/native_studio.gd) | yes |
| Native IDE image import actions | [scripts/firmware_backends/native_ide.gd:28](../../scripts/firmware_backends/native_ide.gd) | yes |
| Compiler strict required checks | [scripts/firmware_toolchain/acceptance.gd:4](../../scripts/firmware_toolchain/acceptance.gd) | yes |
| Compiler gate before broker | [scripts/firmware_toolchain/compile_service.gd:14](../../scripts/firmware_toolchain/compile_service.gd) | yes |

[source_anchors.json](source_anchors.json) holds exact hashes/anchor text. [evidence.json](evidence.json) distinguishes current J/PCB receipts from historical supporting receipts. Receipt archive v3.3 and hands v1.3 are now integrated source. Eight focused Main archive suites pass; broader Main/user-flow acceptance remains open, including the unaccepted J2 profile-reload fixture. File-only review: no engine, imports, renderer, compiler, probes or process queries.

## Integrated source anchors (v3)

These hashes refer to the actual integrated Main modules, separately from the immutable J baseline. No module was edited or executed by this documentation pass. The original 41 anchors retain J identity and have refreshed current-Main hashes/lines in source_anchors.json.

- Accepted-host-only gesture projection: `scripts/interaction_presentation/accepted_event.gd:2` — `35126b026d02c7fbb165b271857fb40ccea35efd72a0fb657d5616a7dd9aa2c6`.
- Cosmetic event dispatch: `scripts/interaction_presentation/bridge.gd:99` — `f32ecadd2fff48fc80669dab3ba0060995be35bab9c5f43249b62d6b5286c7d4`.
- First-person v1.3 pose: `scripts/interaction_presentation/actor.gd:105` — `99c6da455eb5e24211e920135aa01a62f7db38147aaf1fbb4121ba80f58aeb5b`.
- Saved hands setting: `scripts/campus/ui/graphics_settings.gd:4` — `99c9e109912c161845904e81bac6828ebe3155e82792bd0a622aa02fe01270ef`.
- Archive budgets and receipt structure: `scripts/inventory_authority/receipt_archive/format.gd:4` — `abb5e5bc0407570858b220196bd1c26d8e67a79ea2e11d241a6c5f5fc4a71608`.
- Archive cold replay check: `scripts/inventory_authority/receipt_archive/coordinator.gd:44` — `91ebfed8492ce934c879f6047a225ccf4cea1760d8ab67e9320763cfe2d4da17`.
- Backup before migration: `scripts/inventory_authority/receipt_archive/coordinator.gd:71` — `91ebfed8492ce934c879f6047a225ccf4cea1760d8ab67e9320763cfe2d4da17`.
- Immutable archive blob storage: `scripts/inventory_authority/receipt_archive/blob_store.gd:51` — `eb66f403c091ea8cd27f55225f984ae6d1dfda5573b0e9ec77ab25e047e2b4d4`.

Machine-readable locations: [integrated_source_anchors.json](integrated_source_anchors.json). Current accepted/private scope and open integrated checks are in [FEATURE_LEDGER.md](FEATURE_LEDGER.md).

## Final-three / immutable-head refresh

Actual `scripts/dc_lab.gd` SHA-256: `b3d2b932f3f31da13086a9095601f55b49cc4c53323c57f320cd962d538e4ac8`. Final aggregate simulation/snapshot-UI/presentation spans are the current source; the superseded nine-phase patch is historical. Current anchor lines/hashes are refreshed in both JSON anchor files. Immutable-head packing at coordinator `_flush` publishes a new bounded head and preserves old roots/blobs.

- Final simulation span: `scripts/dc_lab.gd:317`.
- Final snapshot/UI span: `scripts/dc_lab.gd:337`.
- Final presentation span: `scripts/dc_lab.gd:341`.

K phase-8 DATA_VALID is separate: DC 21.6994 / AC 25.1091 callbacks/s, target NOT MET; no FPS claim. All-eight current-Main archive PASS38.125 is correctness/history acceptance within its fixture, not an all-feature or performance pass.


## Historical status references

Coordinator status markers change while work proceeds. Their original digests and summaries are preserved in [historical_status_references.json](historical_status_references.json), separately from immutable test receipts. They do not establish acceptance. The receipt audit checks the original bounded-run reports instead.
