"""Bounded source/geometry check; does not execute GDScript or launch Godot."""
from pathlib import Path

source = Path("scripts/ui/paper_workspace/calculator/drawer.gd").read_text(encoding="utf-8")
calculator = Path("scripts/scientific_calculator.gd").read_text(encoding="utf-8")
for token in (
    "_style_physical_calculator()", "_bezel_style()", "_key_style(key.text)",
    "calculator.rotation = 0.0", "_shell.rotation = 0.0",
    "CLOSE_DELAY := 0.16", "_returning_to_dock", "set_occlusion_rect",
    "MOUSE_FILTER_IGNORE", "clamp_position", "snapshot_state", "restore_state",
):
    assert token in source, token
for token in ('"DEG"', '"MC"', '"MR"', '"M+"', '"M−"', '"sin"', '"cos"', '"tan"', '"√"', '"xʸ"', '"Ans"', '"="'):
    assert token in calculator, token

for width, height, drawer_width, drawer_height, anchor_y in (
    (1920, 1080, 318, 509, 440),
    (1366, 768, 318, 509, 440),
):
    y = max(18, min(anchor_y, max(18, height - drawer_height - 18)))
    stowed_x = width - 36
    open_x = width - drawer_width - 20
    assert width - stowed_x == 36
    assert open_x >= 20 and open_x + drawer_width == width - 20
    assert y >= 18 and y + drawer_height <= height - 18
    for x, candidate_y in ((-100, -100), (width + 100, height + 100)):
        x = max(20, min(x, max(20, width - drawer_width - 20)))
        candidate_y = max(18, min(candidate_y, max(18, height - drawer_height - 18)))
        assert 20 <= x <= width - drawer_width - 20
        assert 18 <= candidate_y <= height - drawer_height - 18
    # A pin fixes the revealed target; drag clamps the whole body; unpin
    # targets the original peek dock regardless of the last drag location.
    pinned_target = (open_x, y)
    dragged_target = (max(20, min(-100, width - drawer_width - 20)),
                      max(18, min(height + 100, height - drawer_height - 18)))
    assert pinned_target[0] + drawer_width <= width - 20
    assert dragged_target == (20, height - drawer_height - 18)
    assert stowed_x == width - 36
    # Modeled leave timer: two 0.05 s frames keep it expanded; 0.17 s closes.
    assert 0.05 + 0.05 < 0.16 < 0.05 + 0.05 + 0.07
    print(f"{width}x{height}: peek x={stowed_x}, open=({open_x},{y}), body={drawer_width}x{drawer_height}")
print("Source and modeled dock/clamp checks passed; GDScript/runtime untested")
