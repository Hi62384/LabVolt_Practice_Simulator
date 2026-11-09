from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "scripts/session.gd": "4c5bd463b7bf6ec6627e8070698528ac183ca7eb328c14af5358feb001c64cde",
    "scripts/inventory_authority/network.gd": "84c67f67243786565ec64bce941c0d20d0761895bef54eb316805c5c7f103175",
}
for relative, expected in EXPECTED.items():
    actual = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
    assert actual == expected, f"shared preimage changed: {relative} {actual}"

core = (ROOT / "scripts/campus/dorms/authority/ownership.gd").read_text(encoding="utf-8")
adapter = (ROOT / "scripts/campus/dorms/authority/network_adapter.gd").read_text(encoding="utf-8")
for token in ("join_authenticated", "leave_authenticated", "reconcile_authenticated_peers", "request_door", "stale_session", "rate_limited", "open_doors"):
    assert token in core, token
for forbidden in ("profile", "inventory", "loadout", "notes", "authority_credentials", "@rpc"):
    assert forbidden not in core, forbidden
for token in ("authenticated_peers", "peer_is_connected", "authenticated_sender", "initial_snapshot", "broadcast_snapshot"):
    assert token in adapter, token
print("dorm ownership static audit: OK; shared preimages intact")
