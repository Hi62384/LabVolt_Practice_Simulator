extends VBoxContainer
signal changed(rows: Array)
var columns: Array=[]
var rows: Array=[]
var editable:=true
var grid: GridContainer
var highlight:Array=[]

func configure(data: Dictionary, can_edit: bool=true) -> void:
	if data.get("columns") is int:
		columns=[]
		for i in range(clampi(int(data.columns),1,6)):columns.append("Column %d"%(i+1))
	else:columns=data.get("columns",["Value","Frequency"]).slice(0,8).duplicate(true)
	if data.get("rows") is int:
		rows=[]
		for i in range(clampi(int(data.rows),1,6)):
			var row:=[];row.resize(columns.size());row.fill("");rows.append(row)
	else:rows=data.get("rows",[]).slice(0,128).duplicate(true)
	editable=can_edit
	highlight=data.get("highlight",[]).duplicate()
	_build()

func _build() -> void:
	for child in get_children(): remove_child(child);child.queue_free()
	grid=GridContainer.new()
	grid.columns=maxi(1,columns.size())
	var scroll:=ScrollContainer.new()
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.add_child(grid)
	for c in range(columns.size()):
		var button:=Button.new()
		button.theme=preload("res://scripts/ui/design_system/theme.gd").create()
		button.custom_minimum_size.y=40
		button.text=str(columns[c].get("label",columns[c].get("id",""))) if columns[c] is Dictionary else str(columns[c])
		button.tooltip_text="Sort by this column (view order is saved)"
		button.disabled=not editable
		button.pressed.connect(func():sort_column(c))
		grid.add_child(button)
	for r in range(rows.size()):
		while rows[r].size()<columns.size(): rows[r].append("")
		for c in range(columns.size()):
			var entry:=LineEdit.new()
			entry.text=str(rows[r][c])
			entry.max_length=128
			entry.editable=editable
			entry.custom_minimum_size.x=95
			if r in highlight: entry.add_theme_color_override("font_color",Color("ffd198"))
			entry.text_changed.connect(func(text): rows[r][c]=text;changed.emit(rows.duplicate(true)))
			grid.add_child(entry)
	if editable:
		var add:=preload("res://scripts/ui/design_system/widgets.gd").action("Add row","plus",Callable())
		add.theme=preload("res://scripts/ui/design_system/theme.gd").create()
		add.disabled=rows.size()>=128
		add.pressed.connect(func():var row:=[];row.resize(columns.size());row.fill("");rows.append(row);_build();changed.emit(rows.duplicate(true)))
		add_child(add)

func sort_column(column: int) -> void:
	if not editable: return
	rows.sort_custom(func(a,b):return float(a[column])<float(b[column]) if str(a[column]).is_valid_float() and str(b[column]).is_valid_float() else str(a[column])<str(b[column]))
	_build()
	changed.emit(rows.duplicate(true))
