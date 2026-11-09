# Main-menu Host Game merge preimage

- Source: `scripts/front_menu.gd`
- Pre-change SHA-256: `99B36CD85A7A5B269167605BC295B224CCD1E33BA74D9FDE7ECE473FF094851C`
- Post-change SHA-256: `F1952AC4FC006429C98D50E280EA1462DBCFD3902F6CB8F23045315AB553562E`

Apply this reverse patch to restore the pre-change source:

```diff
--- a/scripts/front_menu.gd
+++ b/scripts/front_menu.gd
@@
 	button("Join Game",func():network_page(true))
 	button("Character Customizer",characters_page)
 	button("Electronics · Shop & Kits",func():game.shop_room.enter())
+	button("Campus · Courses & Map",campus_page)
 	button("Settings",settings_page)
@@
-	if not join:
-		button("Courses & Map",campus_page)
 	button("Back",home)
```
