# Equation refinement handoff

Apply `equations.patch` only if the three live source files match `manifest.txt` preimage SHA-256 values. The staged `.gd` files are the intended postimages. This folder does not change the live game.

The existing `Layout.build(source, font, size)` and `Layout.draw(...)` API remains unchanged. `build` retains the exact source, reports errors, measures the full drawing extent, and supplies draw commands. The selected-object owner should persist the exact item `text` and formatting fields and use the existing rendered extent for hit testing and Bake; the renderer does not alter annotation state.

New notation: `sqrt(x)` has a radical with an overbar; `sin(x)`, `cos(x)`, `tan(x)`, `asin(x)`, `acos(x)`, `atan(x)`, `ln(x)`, `log(x)`, `exp(x)`, and `abs(x)` are recognized function calls with visible parentheses. Named Greek letters such as `alpha`, `theta`, `pi`, and `omega` render as glyphs. A rectangular matrix uses `[a,b;c,d]` syntax: comma separates columns and semicolon separates rows. Unequal row lengths, empty functions and matrices, and missing brackets produce parser errors. Existing fractions, powers, subscripts, grouping, implicit multiplication, and source roundtrip stay intact. `i` remains a literal symbol for complex notation; no evaluation occurs.

The updated `test_equations.gd` adds draw-command and bounds fixtures for radical, Greek, matrix, invalid structure, and exact source. These staged tests have not been executed. The runtime owner should run the pinned equation scope after integration and capture actual game screenshots at a safe time. No engine or UI interaction was performed here.
