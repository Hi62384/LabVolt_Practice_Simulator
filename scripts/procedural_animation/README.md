# Procedural animation

Mount the renderer in a Control or in a SubViewport for a 3D display. Its 960 × 520 logical canvas fits the destination while preserving its aspect ratio.

## Author a scene

A version 1 scene contains a title, a duration in seconds, and objects with stable IDs. The frame header occupies the first 90 logical pixels. Set loop for repeating motion. The optional parameters dictionary maps names to [initial, minimum, maximum].

An object has an ID, a type, an origin (x and y), and relevant numeric properties such as radius, rotation, width, or alpha. A group can pass its transform and opacity to children. The layer controls draw order. Color and fill use RGB or RGBA hex notation.

Bindings let numeric properties refer to parameters, time in seconds (t), constants pi and tau, and approved math functions. A graph function uses u as the horizontal coordinate. Tracks use ordered [time, value] keyframes with linear or smooth interpolation. Each property accepts one binding or track. Objects can use progress to reveal text or trace curves. Labels can display parameter values by putting the name in braces.

The [animation fixture](../../tests/procedural_animation/test_animation.gd) combines a rotating arrow, a moving marker, a plot, and an equation using the same general-purpose renderer.

## Play, edit, and reuse

Load a dictionary with Playback.load_scene or validate JSON with Document.parse. Call advance(delta) from the consumer clock or seek to a specific time. The command API supports create, play, pause, seek, step, restart, speed, highlight, parameter, add, remove, update, duplicate, clear, and restore. An invalid edit preserves the live scene. Use snapshot and restore_checkpoint to transfer playback state. The storage module saves named checkpoints under the game's user-data directory.

Mount canvas.gd in the display container and call show_checkpoint(revision_key, snapshot). A new key reloads the specification. Later checkpoints with the same key can correct drift. The surface emits frame_changed so a 3D display can redraw when needed. The consumer owns proximity, input, and display policy.

## Classroom adapter

The room class host validates and moderates generated plans. The AI can supply typed data and commands. A playback belongs to its class. The host sends the scene when its revision changes or a player enters the room. Later updates carry playback state. Each client calculates movement locally. The regular teacher dialogue and the static portion of the board remain available. The renderer evaluates illustrative equations from the scene.
