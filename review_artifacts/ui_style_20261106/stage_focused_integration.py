from pathlib import Path
import hashlib,difflib,json
root=Path.cwd();out=root/'review_artifacts/ui_style_20261106';changes=[]
def stage(path,edits):
 raw=(root/path).read_bytes();old=raw.decode('utf-8-sig').replace('\r\n','\n');new=old
 for a,b in edits:
  if new.count(a)!=1: raise ValueError((path,new.count(a),a[:90]))
  new=new.replace(a,b,1)
 changes.append({'path':path,'sha256':hashlib.sha256(raw).hexdigest(),'edits':[{'old':a,'new':b} for a,b in edits]})
 return ''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+path,tofile='b/'+path,n=3))
p='scripts/electronics_ui.gd';s=(root/p).read_text(encoding='utf-8-sig');start=s.index('\tvar search := LineEdit.new();search.placeholder_text="Search component name or category"',s.index('func shop()'));end=s.index('\tbutton(body,"Capacity +20',start)
patches=[]
patches.append(stage(p,[
 ('var game: Node\n','var game: Node\nvar shop_adapter=preload("res://scripts/electronics/component_shop_ui/shop_adapter.gd").new()\n'),
 ('var title := label(bar,"ELECTRONICS STUDIO");','var title := label(bar,"COMPONENTS" if page=="shop" else "ELECTRONICS STUDIO");'),
 ('\tfor entry in [["inventory","Hotbar"],["shop","Components"],["kits","My kits"],["board","Breadboard"],["notes","Notebook"],["ics","IC / PCB builder"],["code","Code"],["trade","Trade"]]:button(tabs,entry[1],func():open(entry[0],bench))','\tif page!="shop":\n\t\tfor entry in [["inventory","Hotbar"],["shop","Components"],["kits","My kits"],["board","Breadboard"],["notes","Notebook"],["ics","IC / PCB builder"],["code","Code"],["trade","Trade"]]:button(tabs,entry[1],func():open(entry[0],bench))'),
 ('func shop() -> void:\n','func shop() -> void:\n\tshop_adapter.build(self,body,{"economy":profile.get_meta("economy_display",{})})\n'),
 (s[start:end],'')]))
p='scripts/inventory_authority/network.gd'
patches.append(stage(p,[
 ('\tif not metadata.is_empty() and game.electronics.has_method("kit_names_submitted"):game.electronics.kit_names_submitted(str(pending.back().id),args[0])\n\tflush()','\tif not metadata.is_empty() and game.electronics.has_method("kit_names_submitted"):game.electronics.kit_names_submitted(str(pending.back().id),args[0])\n\tif op in ["buy","buy_configured"] and is_instance_valid(game.electronics.shop_adapter):game.electronics.shop_adapter.submitted(str(pending.back().id),op)\n\tflush()'),
 ('\t\toperation_result.emit(str(pending[0].get("op","")),result)\n\t\tpending.pop_front()','\t\tif str(pending[0].get("op","")) in ["buy","buy_configured"] and is_instance_valid(game.electronics.shop_adapter):game.electronics.shop_adapter.received(id,result)\n\t\toperation_result.emit(str(pending[0].get("op","")),result)\n\t\tpending.pop_front()')]))
(out/'FOCUSED_INTEGRATION.patch').write_text('\n'.join(patches),encoding='utf-8')
(out/'FOCUSED_INTEGRATION.json').write_text(json.dumps({'state':'proposed_read_only_snapshot','warning':'Owner review required. Apply atomically only if exact whole-file SHA matches; no live project file was edited.','changes':changes},indent=2)+'\n',encoding='utf-8')
print('Staged 2-file patch, whole-file SHA bound, shared source untouched')
