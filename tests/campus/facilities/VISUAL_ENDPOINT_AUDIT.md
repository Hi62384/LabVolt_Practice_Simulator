# Gym endpoint visual audit

These are rendered inspections, not exhaustive coverage of every possible avatar.
Phase 0 and phase 1 are the exercise animation endpoints. The listed heights and
outfits are the exact combinations rendered. Re-render cases marked pending after
the relevant pose or cable-routing changes.

| Exercise | Phase | Height | Outfit | Result |
|---|---:|---:|---|---|
| Seated curl | 0 | 0.85 | Tee | Inspected after hand-tracking fix |
| Seated curl | 1 | 1.15 | Hoodie | Inspected after hand-tracking fix |
| Seated good morning | 0 | 0.85 | Tee | Inspected after seat-height fix |
| Seated good morning | 1 | 1.15 | Hoodie | Inspected after hand-tracking fix |
| Seated front raise | 1 | 1.15 | Hoodie | Inspected after seat-height fix |
| Seated wrist curl | 0 | 0.85 | Tee | Inspected after forearm-position fix |
| Seated overhead extension | 0 | 0.85 | Tee | Inspected; raised upper arms and bent elbows keep bar behind head |
| Seated overhead extension | 1 | 1.15 | Hoodie | Inspected; grip rises as elbows extend, remaining behind head |
| Cable chest press | 0 | 0.85 | Tee | Inspected after curved routing |
| Cable chest press | 1 | 1.15 | Hoodie | Inspected after curved routing |
| Cable row | 0 | 0.85 | Tee | Inspected; elbow is unbent at this endpoint |
| Cable row | 1 | 1.15 | Hoodie | Inspected after elbow-bend fix |
| Cable lateral raise | 0 | 0.85 | Tee | Inspected after lower-pulley fix |
| Cable lateral raise | 1 | 1.15 | Hoodie | Inspected after lower-pulley fix |
| Cable front raise | 0 | 0.85 | Tee | Inspected after lower-pulley fix |
| Cable front raise | 1 | 1.15 | Hoodie | Inspected after lower-pulley fix |
| Cable curl | 0 | 0.85 | Tee | Inspected after lower-pulley fix |
| Cable curl | 1 | 1.15 | Hoodie | Inspected after lower-pulley fix |
| Cable tricep pushdown | 0 | 0.85 | Tee | Inspected |
| Cable tricep pushdown | 1 | 1.15 | Hoodie | Inspected |
| Cable reverse fly | 0 | 0.85 | Tee | Inspected |
| Cable reverse fly | 1 | 1.15 | Hoodie | Inspected |
| Cable overhead extension | 0 | 0.85 | Tee | Inspected after raised-arm and elbow pose change |
| Cable overhead extension | 1 | 1.15 | Hoodie | Inspected after raised-arm and elbow pose change |
| Cable chest fly | 0.25 | 1.15 | Hoodie | Inspected after curved routing |
| Cable chest fly | 0.5 | 1.15 | Hoodie | Inspected after curved routing |
| Cable chest fly | 0.75 | 1.15 | Hoodie | Inspected after curved routing |

Separate pose tests cover both heights and both outfits for floor exercises,
bench angles, arm deformation, and cable stance. The chest-press midpoint at
height 0.85 in a Tee was inspected after changing to curved routing. The cable
continuity test checks both leads while the grips move. The curved path is a
visual approximation, not a taut cable simulation. The short stylized arms
place the overhead-extension grip behind the head rather than above its crown.
