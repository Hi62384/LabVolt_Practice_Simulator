from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[3]
PATH=ROOT/'scripts/ui/hud_settings/review/manifest.json'
entries=json.loads(PATH.read_text())
for e in entries:
    file=ROOT/e['path'];raw=file.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==e['after'],f"Concurrent modification: {file}"
    s=raw.decode().replace('\r\n','\n')
    if e['path']=='scripts/lab_ui.gd':
        for name,icon in [('hud','switch'),('objective','course'),('prompt','play'),('log_label','info')]:
            s=s.replace(f'{name}.icon_key = "{icon}"',f'{name}.set("icon_key", "{icon}")')
        s=s.replace('settings = Layout.page(tabs, "Settings", "settings")', '''settings = Layout.page(tabs, "Settings", "settings")
\tsettings.theme = Skin.create()
\t# front_menu reparents the existing settings body; discard its empty tab wrapper.
\tvar settings_page := settings.get_parent()
\tsettings.tree_exiting.connect(func(): settings_page.queue_free(), CONNECT_ONE_SHOT)''')
    if e['path']=='scripts/campus/facilities/facility_panel.gd':
        s=s.replace('button("Buy %s • $%d"','button("%s • $%d"')
    data=s.replace('\n','\r\n').encode()
    assert file.read_bytes()==raw
    file.write_bytes(data)
    e['after']=hashlib.sha256(data).hexdigest()
PATH.write_text(json.dumps(entries,indent=2)+'\n')
print('Final source refinements written with hash guards.')
