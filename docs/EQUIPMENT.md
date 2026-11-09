# Equipment evidence and electrical assumptions

The two supplied reference photographs determine relative panel arrangement, analog faces, switch groups, colored posts, fasteners and rack appearance. They do not establish exact variant identities, meter internal circuits, dimensions or nameplate machine parameters. The scene is photo-inspired and rescaled for first-person use, not dimensionally surveyed.

## Manufacturer evidence

- Festo's [Electric Power Technology Training Systems catalog](https://labvolt.festo.com/Website/downloads/datasheet_593336%2898-8010%29_en_120V_60Hz.pdf) identifies the common 120 V load variants: model 8311 has 300/600/1200 Ω elements; model 8321 has 0.8/1.6/3.2 H elements. Each has three independent groups with three switchable parallel elements. The project preserves these values and group topology. It models nominal values, not manufacturing tolerance or inductor iron loss/saturation.
- Festo's [Power Transmission Smart Grid Technologies data](https://labvolt.festo.com/downloads/datasheet_579331%2859-8010-E0%29_en_120V_60Hz.pdf) documents the common 8331-00 capacitive module: three groups of switchable 2.2/4.4/8.8 µF elements, nominal 120 V/60 Hz. Its discharge resistors and post-disconnection decay are outside this steady-state model. The game's conservative voltage trip is not that module's maximum voltage rating.
- The [8821-20 supply datasheet](https://labvolt.festo.com/downloads/datasheet_579603%2850-8821-2%29_en_120V_60Hz.pdf) documents fixed 120/208 V AC at 15 A and variable 0–120/208 V AC at 5 A, 60 Hz. The model implements only these AC sections, not its DC or 24 V outputs. Current limits are simplified instantaneous trips. The actual supply's shared upstream protection and trip timing are not reproduced.

These documents establish common-variant behavior, not that every photographed module is exactly that variant. Published manufacturer variants differ; never infer a physical trainer's ratings from this game's settings.

## Explicit modeling choices

| Quantity | Model |
|---|---|
| Source phases | RMS 120∠0°, 120∠−120°, 120∠+120°; variable output scales all three |
| Frequency | 60 Hz default, experimental 45–65 Hz adjustment; real 8821 is not a variable-frequency drive |
| Leads | Ideal wire unions; no resistance, inductance or contact failure; 5 m reach, four stacked plugs per simulated post |
| Ammeter/current coil | 0.02 Ω, 1 A visible scale; 5 A simulated protection. Internal impedance and actual photographed ranges unverified |
| Voltmeter | 150 kΩ for 150 V tap, 300 kΩ for 300 V tap; finite loading, simplified independent tap circuits |
| Wattmeter | 0.02 Ω current coil and 150 kΩ voltage coil; signed Re(V·conj(I)); actual photographed terminal mapping unverified |
| Load protection | Conservative 135 V RMS game trip; not a verified real protective-device curve |
| Ground/neutral | Source neutral is reference. No protective-earth conductor, touch-voltage or RCD simulation |
| Floating islands | Explicit arbitrary local references, no artificial leakage conductance; only differential potentials are physically meaningful |
| P/Q/S/PF display | Sum of load complex powers; S=abs(P+jQ), PF=P/S. This is aggregate complex load power, not a full unbalanced-system effective-apparent-power definition or an upstream energy audit of instrument losses |

All meter readings come from the constructed netlist. Instrument current is taken from the double-precision solution before phasors are converted to Vector2, avoiding cancellation of tiny shunt drops. The two-wattmeter total is valid for three-wire three-phase loads, including unbalanced three-wire loads; arbitrary four-wire unbalanced circuits need a different total-power measurement arrangement.

## Motor/dynamometer approximation

The machine is not calibrated to the photographed nameplate. The illustrative per-phase model uses Rs=12 Ω, Rr'=9 Ω, Xs=Xr'=15 Ω, Xm=180 Ω at 60 Hz and four poles. Reactances scale with frequency. Rotor resistance is Rr'/slip. Magnetizing and rotor branches are parallel behind stator impedance. Torque derives from rotor air-gap power divided by synchronous angular speed. A low-slip stable operating point is found against 0.02 Nm friction plus 0–1.2 Nm constant dynamometer load, or a stall is reported. The network is restamped to converge slip and winding voltage.

Reported quantities include synchronous speed, slip, torque, estimated locked-rotor starting current, shaft power, input power and efficiency. Balanced phase sequence determines visible direction. Unbalanced/missing/single-phase connections do not produce a validated running-speed model. No core-loss branch, magnetic saturation, thermal damage, start transient, inertia or real shaft-coupling simulation is claimed. Visual rotor acceleration is smoothing only.

The transformer, DAQ and additional control panel are explicitly display-only. Their decorative terminals cannot create fictitious electrical connections.
