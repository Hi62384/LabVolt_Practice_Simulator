# Repeatable manual acceptance checks

Automated evidence is in docs/VALIDATION.md and docs/validation_logs. These procedures complement it; they are not claims of human multi-computer testing.

## Navigation and interactions

1. Launch LabVolt.exe. Confirm an unwired, unpowered station behind the menu. Select Single Player. Walk, sprint, jump, crouch, zoom and inspect labels at close range. Attempt to walk into the bench, cabinet, walls and chairs. Open Settings and change sensitivity, optional bob and a movement binding; restart and verify persistence.
2. Approach the rack, point at a lead and E. Verify a carried cable and two connector shapes. Plug first into P_A, walk away, verify sag/reach limit, then attach second to R0_P. Q on P_A must remove only that end. Plug it elsewhere. G releases the held end; E on its hanging connector reclaims it. Z within reach undoes your last completed connection. Test all four colors and the four-plug stacking limit.
3. Point at R bank 1's 1200-ohm toggle and E. Verify lever and indicator change. Point at the supply voltage dial, drag, and verify source level changes when F8 telemetry is enabled. With power on, verify wiring/load edits are blocked with feedback; turning the supply off permits them again.

## Actual electrical networks

Use R to reset cables/loads while power is off. No demo shortcuts exist.

- Wye: P_A/B/C to R0/1/2_P, returns to P_N; enable only each 1200-ohm element. At 120 V phase voltage expect 0.100 A per branch and 36 W total load power. To measure, put current coils in series, voltmeter taps across the load. Meter loading and current coils introduce small deviations.
- Delta: PV_A→R0_P→R0_N→PV_B; PV_B→R1_P→R1_N→PV_C; PV_C→R2_P→R2_N→PV_A. Enable 1200-ohm elements. Set variable level to 57%. Expect 118.47 V per branch, 0.098727 A per branch, 0.171 A per line and approximately 35.089 W total.
- Parallel PF correction: P_A to R0_P, L0_P, C0_P; all three returns to P_N. Enable 1200 Ω, 3.2 H and 2.2 µF only. Expect P=12 W, Q approximately −0.007 var and PF near 1. Remove C and verify positive Q / lagging current. Change frequency and verify reactance changes.
- Two-wattmeter method: for a three-wire Wye, join R0/1/2_N together, with no source neutral. Phase A through W0 current coil to R0; B directly to R1; C through W1 current coil to R2. W0 voltage across A−B, W1 across C−B. With balanced 1200-ohm loads, expect about +18 W each; sum about 36 W. Reversing a voltage coil must reverse that instrument's signed reading.
- Faults: with power off, connect phase A directly to N, then energize. Verify trip, zero de-energized readings and visible explanation. Repeat with an ammeter directly across supply. An open branch must draw zero load current. Unequal star loads with the neutral removed must shift the star potential, not preserve 120 V on every branch.
- Motor: wire phases to M1/M2/M3 and join M4/M5/M6 to neutral, then energize. Verify the shaft and calculated speed. Operate dynamometer load and verify speed decreases while input power increases. Reverse two supply phases while de-energized; direction must reverse. The model is illustrative, not calibrated.

## Worksheet and examinations

Assign Practical Exam, Balanced Wye, seed 101 in the host's menu. Read the specified resistance value in B. Confirm F8, highlight and wiring hints cannot reveal answers. Build it manually, include a series ammeter, a parallel voltmeter and valid total-power instruments. C preflight must precede energization. Record, type readings and submit. Correct topology, safe editing and measurements should earn 100/100; an incorrect numeric answer should lose 30 measurement points. Editing the circuit invalidates previous records/preflight. Restart and verify Records retains the result and personal-best XP.

## Real multiplayer

1. Open two instances, host on UDP 24842 and join 127.0.0.1. On separate computers, use the host's LAN IP. Verify names, ready indicators, movement, crouch, avatar interpolation and chat.
2. Player A starts a cable. B must see it but cannot claim that carried cable. A finishes; B unplugs one end, carries it and replugs it. Compare topology and meter values on both clients.
3. Have both players try the same switch and cable end simultaneously. There must be one owner and one accepted expected-state switch change, not duplicate cables or a double flip.
4. Join a third instance after energization. Verify installed cables, switches and readings appear immediately. Disconnect a carrying player: installed ends must remain and the free connector must be reclaimable. Disconnect a player with only installed leads; those leads must remain.
5. Host shutdown must return clients to local laboratory with a clear message. Join an unavailable IP and verify connection-failure feedback. Try a busy port and verify the host error. For Internet tests, explicitly configure UDP forwarding/firewall; NAT traversal is not automatic.

Eight-player WAN reliability, adverse packet loss, multiple GPU vendors, laptop performance and long sessions still require broader testing.
