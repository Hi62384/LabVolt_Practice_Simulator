# Integrated Invention Studio

M208 is registered in the campus directory and mounted by `game.gd`. It has
five physical workstations: assembly table, IC builder, PCB builder, prototype
bench, and firmware console. The room is streamed with the campus and the mount
checks its registry coordinates against `assets/campus/circuit_studio/room.json`.

The assembly table opens `assembly_window.gd`. Players can save designs of up
to 32 direct parts and 64 expanded parts on a 0.3 m grid. The palette includes
wood, aluminum and plastic structure; wheels and hinges; battery, switches,
motors, servos, and references to existing custom PCB blueprints. Designs can
nest other invention blueprints to four levels. The editor validates cycles,
collisions, control assignments, power and part bounds and shows a top-down
preview. Its material bill and per-copy price are derived by `assembly_model.gd`.

Blueprints are stored in the electronics profile. Offline fabrication saves a
copy and applies the current economy purchase policy (the present playtest
policy allows unlimited purchases). Online fabrication uses the host inventory ledger; a
client metadata update cannot mint copies. Once copies exist, editing saves a
new blueprint revision; the host rejects modifications to fabricated revisions.
Existing IC/PCB copy and crafting paths remain in the electronics profile.

`invention_world.gd` lets each owned copy be placed once at a time, retrieved,
and operated nearby. The host validates ownership, blueprint, placement and
control proximity, then shares the placed state. Hold controls have a short
renewable lease and an exclusive holder. Toggle controls latch. A battery,
matching switch, motor and wheel give visible rotation and floor movement;
servos show control-driven angular motion.

A design may map one custom PCB's supply, ground and output pins to controls A
and B. The host runs that PCB in the existing DC station circuit and firmware
simulator with a 5 V supply. Outputs above 2.5 V activate a drive configured as
PCB; `Both` requires the manual control and PCB output. The mounted PCB panel
reports live voltages and operates supported manual inputs, including switches,
knobs, encoders, keypads, sliders, selectors, joysticks and touch inputs. At
most eight mounted PCBs simulate in a session to bound frame work. Other PCB
copies remain available at the standalone bench for full trace inspection and
lead wiring. The moving world body is an educational rigid assembly model; it
does not model structural stress or motor torque against varying loads.

Checks: `tests/campus/circuit_studio/assembly_flow_test.gd` covers nested
validation, price, persistence, host fabrication and forged-copy rejection.
`tests/menu_startup/test_menu_routes.gd` covers both Play routes, the five
mounted stations, editor windows, world placement, PCB-driven movement and retrieval.
`tests/campus/circuit_studio/pcb_drive_test.gd` checks voltage-gated motion
signals and mounted encoder input through the host circuit runtime.
