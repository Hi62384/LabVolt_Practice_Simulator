# AC/DC breadboard and custom-IC practice

This guide describes the current source controls. The examples below were checked against source; this documentation pass did not run the game. See [the evidence ledger](FEATURE_LEDGER.md) for the separate runtime evidence and limits.

## Start and find the controls

1. Start the existing project using **Run.cmd**. Choose **Host Game**, **Freeplay**, and leave **Play alone** checked for solo practice. Select your usual character so its saved electronics designs are available.
2. Open **Electronics · Shop & Kits**. Its tabs include **My kits**, **Breadboard**, **IC / PCB builder**, and **Code**. Walk to a DC station before deploying. Clicking its control panel opens **DC LAB / STATION**; clicking a deployed board opens its editor.
3. Work with outputs off while arranging this example. In the DC panel, **Disconnect all / outputs off** clears station leads. It is a reset for this exercise, so use an unused station.

## Understand the holes first

- At each number, A–E are one connected strip; F–J are another. A1 and E1 connect internally. A1 and F1 do not. A1 and A2 do not.
- P and N are separate rails, each split halfway. On a 30-row board, P1–P15 connect, P16–P30 connect, and there is no connection across P15/P16 without a jumper. N behaves the same way. On 10/20/40-row boards the break follows row 5/10/20.
- A resistor with both legs in A1 and E1 is shorted by the strip. Use distinct nodes. A jumper between P15 and P16 deliberately bridges that rail break.
- **B1–B4** are external bench posts mapped to holes by the four fields below the editor. Type a hole and press Enter to commit it. These are mappings, not four automatically connected power rails. Defaults are P1, N1, A1, F1 respectively.
- Choose a component or **Jumper wire**, then click two holes. Right-click cancels the first hole. Middle drag pans; wheel zooms. **Undo**, **Redo**, **Remove**, selection and rotation tools are available. Package pin geometry can constrain placement.

## DC: measure one resistor

1. In **My kits**, equip the Starter kit (or a kit containing a **1000 Ω resistor**). A new profile starts with these resistors. Open **Breadboard** and use an empty board for this example; remove earlier parts and jumpers only if you intend to replace that design.
2. Select **1000 Ω resistor** and click **A1**, then **F1**. Set **B1 → A1** and **B2 → F1**, pressing Enter in each field. Leave B3/B4 unused. Wait for **Design saved** after the component edit; any validation or save error needs resolving before continuing.
3. Near the station, choose **Deploy to DC bench**. Deployment requires the parts in your equipped kit and available owned stock. The isolated circuit designer makes all parts available for preview; it does not grant deployment stock.
4. Open the station panel. In **Power supply**, keep master output off, set channel 1 to **5 V**, current limit **0.01 A**, and **Channel enabled** on. Keep other channels, current sources and generator disabled.
5. In **Leads & components**, select each pair and choose **Attach lead**: CH1+ → B1; CH1- → B2; VΩ → B1; COM → B2.
6. In **Multimeter**, choose **DC V**, Auto range. Switch **Master output ON / OFF** on. Expect approximately 5 V across the resistor. The supply readout should show about 5 mA; finite source resistance and models can shift the last digits. These are calculated expectations, not a new test receipt.
7. To measure series current, turn master off. Remove CH1+ → B1. Add CH1+ → A and COM → B1; retain CH1- → B2. The existing COM → B2 voltage lead must be removed, or it bypasses the load. Choose **DC A**, then turn master on. Expect about 5 mA. Turn off before restoring voltage wiring. Never place A/COM directly across a supply.

## Low-frequency AC on the same breadboard

1. Turn master off. Remove the DC supply leads and any series-current arrangement. Keep only the resistor on the board. Use **Leads & components** to connect GEN → B1, REF → B2, VΩ → B1, COM → B2, S1 → B1, GND → B2.
2. In **Function generator**, choose **Sine**, frequency **10 Hz**, peak amplitude **2 V**, offset **0 V**, output impedance **50 Ω**, and **Output enabled**. Keep DC channels and current sources disabled. The generator uses its own enable; the DC master does not switch it off.
3. Choose **AC V** in **Multimeter** and view channel 1 in **Oscilloscope**. The generator amplitude is open-circuit peak, not RMS. A nominal 1 kΩ load with 50 Ω source impedance gives roughly 1.90 V peak, or 1.35 V RMS; instrument loading and model details affect the reading. The scope measures S1 relative to GND; its channels share that ground.
4. Clear the generator's **Output enabled** when finished, and leave DC master off. The generator's implemented teaching range is 0.1–100 Hz. Use its scope settings to make several cycles visible; do not infer high-frequency hardware fidelity from this example.

## AC rack: read the printed ports

For a physical course experiment, right-click the instructor for the assigned lab and follow its generated **YOUR PHYSICAL BENCH** cable list and bank-switch values. Those instructions correspond to that experiment; the separate calculation questions may describe different circuits.

1. Find the assigned AC rack. Aim at its panel and press **F** to inspect; scroll zooms and F/Escape returns. Turn supply power off and unused bank switches off. Set the supply dial and frequency exactly as the sheet states.
2. Open the drawer under the table, click one cable bag, then click the two sockets named in the first cable instruction. Repeat one cable at a time. Leads can stack on a socket. Use the panel labels rather than guessing from internal IDs.
3. The variable supply uses **4 / 5 / 6 / N** for A/B/C/neutral. The first ammeter's **±** common is internally **AM0_OUT** (the AM_OUT suffix denotes common); its **0.5**, **2.5**, **8** sockets are AM0_IN, AM0_2_5, AM0_8. Use common and one range under the same meter, in series. Only the middle meter has the additional 25 A socket.
4. Each voltmeter uses its black **±** common and one yellow range socket, across two nodes. Printed **100** is historical ID **V0_150** on the first meter; printed **250** is **V0_300**. The other meters use the corresponding V1/V2 prefix. There is no hidden 150/300 socket to find. Use the assignment's range; when unsure start with printed 250.
5. Each R/L/C bank has top/bottom sockets and three switches. Enabled switch values combine in parallel. Follow the printed switch list rather than treating a bank as one series row. Check the cable list, power on, read the assigned instruments and use **Record equipment** on the worksheet. Power off when finished. **C** checks wiring; **P** switches power. The crosshair prompt identifies the available control.

## Turn the resistor into a reusable custom IC

1. In **IC / PCB builder**, select **New empty circuit design**. This creates and equips a new design; it does not erase the previous kit. Place one 1000 Ω resistor at A1/F1 in the designer. Do not include a battery for this passive package.
2. Return to **IC / PCB builder**. Choose **IC**, name it `Practice resistor`, set **Pins** to 2, **Width** to 2 and **Length** to 6. Keep **Explicit grid positions** enabled. For X1 use name `IN`, internal hole A1, x=0, y=0. For X2 use name `OUT`, internal hole F1, x=0, y=5. Hole fields select internal electrical nodes; x/y describe external physical placement. Role labels alone do not create electrical behavior.
3. Choose **Save circuit package** and check for **Blueprint saved:**. Inspect it with **Inspect package**. **Buy $…** obtains a package with money; **Craft from components** uses its required materials. A saved blueprint alone is not an owned physical part.
4. Equip a separate receiving kit in **My kits**, include one owned Practice resistor, and open its empty breadboard. Select the package, click A1 and then another hole to finish the placement gesture. Explicit geometry anchors its pins from the first hole, so this package occupies A1/F1; the second click does not override the saved pin positions. Use B1=A1/B2=F1 and the earlier DC wiring to practice measuring it.
5. **Edit a copy** restores the saved layout for editing. Saving creates a new revision identity; existing owned packages keep their definition. PCB selection adds footprint/layout rules; **Outline / copper** edits actual routed connectivity, and **Use standalone** is available for PCBs. IC packaging is circuit composition, not automatic synthesis of a new silicon/device model.

## Save, close and reopen

Board edits validate and save automatically; the editor reports **Design saved** or an error. Press Enter for port-field edits and kit renaming. Package definitions save only through **Save circuit package**. Close and reopen **Electronics · Shop & Kits**, reselect the same kit and check its holes and port mappings. To check persistence after a later session, select the same character and kit again. Designs live in the character's local application data; this guide does not claim that station power, loose leads or an active deployed session resume after restart. **Recall / disconnect** returns a deployment through the inventory authority. Disconnect B1–B4 leads before moving a board with **Carry board**; right-click a table to place it and R rotates it.

## Programming: choose the right path

- **LV Micro / LabVolt Script 1:** place LV Micro, power VIN/GND within its catalog rating, open **Code**, select it, choose a template, **Validate**, **Save / Upload**, then **Run**. **Stop**, **Reset**, breakpoints and serial inspection support practice. This is the educational LVScript interpreter, not Arduino C++ or MicroPython.
- **Precompiled native images:** native Uno R3, classic ATmega328P Nano and Pico have a separate native panel in **Code**. Import a validated image for the exact supported target and pin map; power the circuit and use the panel's controls. Existing image import/execution remains available. A successful Uno fixture does not certify every sketch, board peripheral or Pico firmware image.
- **C/C++ source compilation is deferred for this deadline.** Editing/saving source remains available. Compilation stays disabled behind the current fail-closed local acceptance gate; there is no unrestricted compiler fallback. Do not change the gate or install/configure a compiler to follow this guide. Broad additional native chips and unsupported-device features are also deferred.

For model-specific limits and verified scope, read [FEATURE_LEDGER.md](FEATURE_LEDGER.md). For traceable source locations, read [SOURCE_AUDIT.md](SOURCE_AUDIT.md).

## Interaction hands feedback

Integrated hands v1.3 adds cosmetic feedback after supported host-accepted cable/control actions, including a first-person hand kept low/right of the view. Use the existing cable and equipment controls above; the animation does not change reach, electrical connections or the solve. Its bounded fixture passed, but remote ENet gestures/reconnect, all mouse interactions and full integrated regression are not yet accepted.

Persistence acceptance note: the separate exact-J core-practice J2 run recorded 57 checks with one profile-reload failure involving pin IDs/order and crafted inventory. Treat the save/reopen steps above as source-supported instructions, not a completed restart-acceptance claim. See the ledger for the distinct passing focused Main archive tests.
