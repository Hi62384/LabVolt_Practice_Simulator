"""Generate review-only exact-preimage edits. Never writes shared source files."""
from pathlib import Path
import hashlib
import json
import difflib

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "review_artifacts/component_values_20261106"
EDITS = []
WORK = {}

def edit(path, before, after):
    text = WORK.setdefault(path, (ROOT / path).read_text(encoding="utf-8"))
    if text.count(before) != 1:
        raise AssertionError(f"Expected one exact preimage in {path}: {before[:100]!r}")
    EDITS.append({"path": path, "before": before, "after": after})
    WORK[path] = text.replace(before, after, 1)

V = 'preload("res://scripts/electronics/component_values/values.gd")'
edit("scripts/electronics_catalog.gd",
     '\treturn _simulation_entries.get(id,{}).duplicate(true)',
     f'\tif id.begins_with("cv1:") and not _simulation_entries.has(id):\n\t\tvar configured: Dictionary={V}.resolve(id,_simulation_entries)\n\t\tif not configured.ok:return {{}}\n\t\tif _simulation_entries.size()<512:_simulation_entries[id]=configured.entry.duplicate(true)\n\t\treturn configured.entry\n\treturn _simulation_entries.get(id,{{}}).duplicate(true)')
edit("scripts/electronics_profile.gd",
     'var known: Dictionary=preload("res://scripts/custom_circuit.gd").catalog(value.get("blueprints",{}))',
     f'var known: Dictionary={V}.augment(preload("res://scripts/custom_circuit.gd").catalog(value.get("blueprints",{{}})),value.inventory.keys())')
edit("scripts/electronics_profile.gd",
     'func catalog() -> Dictionary:return preload("res://scripts/custom_circuit.gd").catalog(data.get("blueprints",{}))',
     f'func catalog() -> Dictionary:return {V}.augment(preload("res://scripts/custom_circuit.gd").catalog(data.get("blueprints",{{}})),data.get("inventory",{{}}).keys())')
METHOD = '''func buy_configured(base_id: String, settings: Variant, amount: Variant, authority_confirmed: bool=false) -> String:
	operation_succeeded=false
	if authority_submit.is_valid():return queued("buy_configured",[base_id,settings,amount])
	if not authority_confirmed:return "Authenticated host required"
	if not data.get("pending_trade",{}).is_empty():return "Finish the pending trade first"
	var values=preload("res://scripts/electronics/component_values/values.gd")
	var builtins: Dictionary=Catalog.all()
	var configured: Dictionary=values.configure(base_id,settings,builtins)
	if not configured.ok:return configured.error
	var existing: Variant=data.get("inventory",{}).get(configured.id,0)
	if not ProfileQuantity(existing):return "Invalid existing stock"
	var plan: Dictionary=values.intent(base_id,settings,amount,builtins,int(existing))
	if not plan.ok:return plan.error
	var debit: Dictionary=preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(int(data.dollars),plan.total_price,true)
	if not debit.ok:return debit.error
	var before := data.duplicate(true)
	data.dollars=debit.next_balance;data.inventory[plan.id]=int(existing)+plan.quantity
	if save()!=OK:data=before;return "Save failed; purchase rolled back"
	operation_succeeded=true
	return "Purchased %d × %s"%[plan.quantity,plan.entry.name]

'''.replace('ProfileQuantity(existing)', 'quantity(existing)')
edit("scripts/electronics_profile.gd", 'func kit_error(id: String) -> String:', METHOD+'func kit_error(id: String) -> String:')
edit("scripts/electronics_profile.gd", 'Catalog.all()[type].name]', 'Catalog.simulation_entry(str(type)).get("name",type)]')
edit("scripts/electronics_ui.gd", 'Catalog.all()[type].name]', 'Catalog.simulation_entry(str(type)).get("name",type)]')
edit("scripts/dc_lab.gd", 'preload("res://scripts/electronics_catalog.gd").all().get(found.type,{}).get("kind","")',
     'preload("res://scripts/electronics_catalog.gd").simulation_entry(str(found.type)).get("kind","")')
edit("scripts/inventory_authority/ledger.gd", '\t\t"buy":\n',
     '\t\t"buy_configured":\n\t\t\tif args.size()!=3 or not args[0] is String:return failure("Invalid configured purchase")\n\t\t\tmessage=p.buy_configured(args[0],args[1],args[2],true)\n\t\t"buy":\n')
edit("scripts/inventory_authority/ledger.gd", 'if op in ["buy",', 'if op in ["buy_configured","buy",')
edit("scripts/inventory_authority/ledger.gd", 'if not Custom.catalog(owned).has(type):return "Unknown component"',
     f'if not {V}.augment(Custom.catalog(owned),[type]).has(type):return "Unknown component"')
edit("scripts/breadboard_model.gd", 'static func catalog(board: Dictionary) -> Dictionary:return Custom.catalog(board.get("definitions",{}))',
     f'static func catalog(board: Dictionary) -> Dictionary:return {V}.augment(Custom.catalog(board.get("definitions",{{}})),board.get("parts",[]).map(func(part):return str(part.get("type",""))))')
edit("scripts/custom_circuit.gd", '\treturn result\nstatic func validate(',
     f'\tvar configured_ids: Array=[]\n\tfor bp in definitions.values():\n\t\tif not bp is Dictionary or not bp.get("parts",[]) is Array:continue\n\t\tfor part in bp.parts:\n\t\t\tif part is Dictionary:configured_ids.append(str(part.get("type","")))\n\treturn {V}.augment(result,configured_ids)\nstatic func validate(')
edit("scripts/custom_circuit.gd", '\tvar names := {};var ids := {};var chain := ancestors.duplicate();chain.append(id)',
     f'\tvar builtin_catalog: Dictionary={V}.augment(Catalog.all(),bp.parts.map(func(part):return str(part.get("type","")) if part is Dictionary else ""))\n\tvar names := {{}};var ids := {{}};var chain := ancestors.duplicate();chain.append(id)')
for before, after in [
    ('if not Catalog.all().has(type):return "Unsupported internal component"', 'if not builtin_catalog.has(type):return "Unsupported internal component"'),
    ('Catalog.all()[type].pins.size()', 'builtin_catalog[type].pins.size()'),
    ('Catalog.all().get(type,{"kind":"R"})', 'builtin_catalog.get(type,{"kind":"R"})'),
    ('if not Catalog.all().has(type) or str(part.get("a",""))', 'if not builtin_catalog.has(type) or str(part.get("a",""))'),
    ('int(Catalog.all()[type].price)*int(counts[type])', 'int(Catalog.simulation_entry(str(type)).get("price",0))*int(counts[type])'),
]:
    edit("scripts/custom_circuit.gd", before, after)
edit("scripts/physical_resistors.gd", 'var catalog: Dictionary=load("res://scripts/electronics_catalog.gd").all()',
     f'var catalog: Dictionary={V}.augment(load("res://scripts/electronics_catalog.gd").all(),profile.get("inventory",{{}}).keys())')

# Shop owner has independently wired shop_services and canonical quantity; no shop edit needed.
preimages = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in WORK}
payload = {"mode":"REVIEW ONLY; not applied", "hashes_are_informational":True,
           "application_rule":"Each exact before block must occur exactly once; fail closed on any mismatch. Recheck concurrent owner changes. Apply atomically with backups. Do not launch Godot or reload the running game during active playtest.",
           "source_sha256": preimages, "edits":EDITS}
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "shared_patch.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
diffs=[]
for p, after in WORK.items():
    before=(ROOT / p).read_text(encoding="utf-8")
    diffs.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile="a/"+p,tofile="b/"+p))
(OUT / "shared_integration.patch").write_text("".join(diffs),encoding="utf-8")
print(f"Staged {len(EDITS)} exact edits across {len(WORK)} shared files; no shared files modified.")
