# M103 physical model / electrical binding contract

The physical model owner writes only this private packet. The binding owner (01a1b269-8bf0-7841-8566-39ac26cbbc26) owns validated actions, live displays and trace drawing. Main integrates production.

`physical_models/ports.json` is the sole source for **fixed** instrument/patch-panel ports. A row gives stable `id`, `device`, local centre in metres (`xyz`), face normal (`normal`), color/legend, and `face_z` of the mounting panel. The visible socket centre, `StaticBody3D` pick centre and cable endpoint MUST be derived from that same row, under the same device parent transform. Never recalculate port positions using `Station.PORTS` index arithmetic. The `X1..X64` terminals belong to the movable breadboard and are intentionally excluded.

Instrument roots use bench-local coordinates (+Y up, +Z toward user): PSU, meter, generator, scope and a real mounted distribution deck. Bench origin remains `(index-1)*6, 0, 8.8 + campus_offset`, yaw π. The worktop occupies X ±2.4, Y .76–.88, Z ±.8. Three stations use the same fixture data with independent state and actions. No M101/AC resource may be imported or edited.

Electrical identities and actions remain those in `scripts/dc_station.gd`: PSU `CH1±`…`CH3±`, `master`, `channel` voltage/limit/enabled; meter `VΩ`, `COM`, `A`, `meter`, `meter_range`, `fuse`; generator `GEN`, `REF`, `generator`; scope `S1`,`S2`,`GND`, `scope`; current sources `IS±`, `IS2±`…`IS4±`; load/board patch ports `R1a/b`,`R2a/b`,`Ca/b`,`Da/b`,`B1..B4`. Any new physical control must bind to a supported host-validated action or remain visibly non-interactive. All host requests go through `dc_lab.request(index,action)`. No device graphic sets simulation values.

Physical model supplies `fixture.gd` with `build(index)`, `port_targets: Dictionary`, `port_positions(): Dictionary`, `control_mounts: Dictionary`, and `display_mounts: Dictionary`. Binding owner can attach interaction behavior/display content to those mounts. Port target metadata remains `role=dc_port`, `dc_station=index`, `dc_port=id`. The main integration patch will mount one fixture per existing DC bench and use `port_positions()` for both local and external cable endpoints. Do not create additional terminal IDs or mutate saves.

Acceptance at current boundary: source and offline geometry checks only. Godot import, screenshot, collision, electrical, multiplayer and performance acceptance follow after user play ends.
