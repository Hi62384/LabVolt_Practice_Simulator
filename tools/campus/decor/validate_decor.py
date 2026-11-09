"""Static decor admission checks; does not launch or contact the running game."""
from __future__ import annotations
import hashlib, json, math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
REGISTRY=ROOT/"assets/campus/world/room_registry.json"
CATALOG=ROOT/"assets/campus/decor/room_dressing.json"
MESHES=ROOT/"assets/campus/decor/meshes"
REPORT=ROOT/"assets/campus/decor/PLACEMENT_AUDIT.md"

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def mesh_bounds(path):
    vertices=[]
    for line in path.read_text(encoding="ascii").splitlines():
        if line.startswith("v "): vertices.append(tuple(map(float,line.split()[1:4])))
    return tuple(min(p[i] for p in vertices) for i in range(3)),tuple(max(p[i] for p in vertices) for i in range(3))

def main():
    registry=json.loads(REGISTRY.read_text(encoding="utf8")); catalog=json.loads(CATALOG.read_text(encoding="utf8"))
    rooms={r["id"]:r for r in registry["rooms"]}; profiles=catalog["rooms"]; errors=[]; rows=[]; used=set(); bounds_cache={}
    if set(rooms)!=set(profiles): errors.append(f"coverage mismatch missing={set(rooms)-set(profiles)} extra={set(profiles)-set(rooms)}")
    for room_id, profile in profiles.items():
        room=rooms.get(room_id)
        if not room: continue
        low,high=room["bounds_min"],room["bounds_max"]; door=room["door"]; count=0; batches=0; seen=set()
        for group in profile.get("groups",[]):
            batches+=1; mesh=group["mesh"]; used.add(mesh); mesh_path=MESHES/f"{mesh}.obj"
            if not mesh_path.is_file() or mesh_path.stat().st_size<100: errors.append(f"{room_id}: missing/empty {mesh}.obj")
            for item in group.get("items",[]):
                count+=1
                if len(item)!=7: errors.append(f"{room_id}/{mesh}: transform does not have 7 fields"); continue
                x,y,z=[float(item[i]) for i in range(3)]; key=(mesh,round(x,3),round(y,3),round(z,3))
                if key in seen: errors.append(f"{room_id}: duplicate transform {key}")
                seen.add(key)
                if not (low[0]+.15<=x<=high[0]-.15 and low[1]-.01<=y<=high[1] and low[2]+.15<=z<=high[2]-.15): errors.append(f"{room_id}/{mesh}: origin {(x,y,z)} outside inset bounds")
                if math.hypot(x-door[0],z-door[2])<1.25: errors.append(f"{room_id}/{mesh}: origin {(x,y,z)} intrudes 1.25m door clearance")
                if mesh_path.is_file():
                    if mesh not in bounds_cache:bounds_cache[mesh]=mesh_bounds(mesh_path)
                    a,b=bounds_cache[mesh]; yaw=math.radians(float(item[3])); sx,sy,sz=map(float,item[4:7]); points=[]
                    for lx in (a[0],b[0]):
                        for ly in (a[1],b[1]):
                            for lz in (a[2],b[2]):
                                px,pz=lx*sx,lz*sz; points.append((x+px*math.cos(yaw)+pz*math.sin(yaw),y+ly*sy,z-px*math.sin(yaw)+pz*math.cos(yaw)))
                    if any(not (low[0]-.001<=p[0]<=high[0]+.001 and low[1]-.001<=p[1]<=high[1]+.001 and low[2]-.001<=p[2]<=high[2]+.001) for p in points): errors.append(f"{room_id}/{mesh}: transformed mesh AABB crosses room shell at {(x,y,z)}")
        if count<3: errors.append(f"{room_id}: fewer than three placed props")
        if not profile.get("coverage") or not profile.get("protected"): errors.append(f"{room_id}: missing coverage/protected-zone record")
        rows.append((room_id,room["number"],room["kind"]," × ".join(str(v) for v in room["size"]),count,batches,", ".join(profile["coverage"]),profile["protected"]))
    for mesh in used:
        path=MESHES/f"{mesh}.obj"
        if path.is_file():
            text=path.read_text(encoding="ascii"); verts=sum(1 for line in text.splitlines() if line.startswith("v ")); faces=sum(1 for line in text.splitlines() if line.startswith("f "))
            if verts<8 or faces<12:errors.append(f"{mesh}: insufficient baked geometry ({verts} vertices/{faces} faces)")
    lines=["# Campus decor placement audit","","> Static source/data admission only. No engine or visual acceptance is claimed.","",f"Registry SHA-256: `{sha(REGISTRY)}`  ",f"Catalog SHA-256: `{sha(CATALOG)}`  ","", "| Room | Number | Kind | Registry size | Props | Batches | Coverage | Protected functional zone |","|---|---:|---|---:|---:|---:|---|---|"]
    lines += ["| %s | %s | %s | %s | %d | %d | %s | %s |"%r for r in rows]
    lines += ["","## Baked mesh inventory",""]
    for mesh in sorted(used):
        path=MESHES/f"{mesh}.obj"; lines.append(f"- `{mesh}.obj` — {path.stat().st_size} bytes — `{sha(path)}`")
    lines += ["","## Admission result","",f"{'PASS' if not errors else 'FAIL'} — {sum(r[4] for r in rows)} placements in {sum(r[5] for r in rows)} room-local MultiMesh batches across {len(rows)} registry rooms."]
    if errors: lines += ["",*['- '+e for e in errors]]
    REPORT.write_text("\n".join(lines)+"\n",encoding="utf8")
    print(lines[-1] if not errors else "\n".join(errors)); return 1 if errors else 0

if __name__=="__main__":raise SystemExit(main())
