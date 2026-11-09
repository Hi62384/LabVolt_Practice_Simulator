from pathlib import Path
p=Path(__file__).resolve().parent
u=(p/'paper_ui.patch').read_text(encoding='utf-8')
s=(p/'school_session.patch').read_text(encoding='utf-8')
assert 'practice_lesson' in u and 'open_lab_equipment_tutorial' in u
assert 'formal_guide_policy.gd' in u and 'formal_guide_policy.gd' in s
assert 'registry.call("locate",pose)' in s and 'room_bridge.contains(room_id,pose)' in s
assert 'practice_scope' in s and 'mode in ["Open Lab","Freeplay","Creative Freeplay"]' in u
print('OPEN_LAB_SOURCE_CHECK OK')
