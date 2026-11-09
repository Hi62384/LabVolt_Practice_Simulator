extends RefCounted
static func parse(output: String,files: Dictionary) -> Array:
	var result: Array=[]
	var regex := RegEx.new();regex.compile("^(.*?):([0-9]+)(?::([0-9]+))?: (fatal error|error|warning|note): (.*)$")
	var ansi := RegEx.new();ansi.compile("\\x1B\\[[0-9;]*[A-Za-z]")
	for raw in ansi.sub(output.left(262144),"",true).split("\n"):
		var match_value := regex.search(raw.strip_edges())
		if match_value==null:continue
		var name := match_value.get_string(1).replace("\\","/").get_file()
		if name.ends_with(".ino.cpp"):name=name.trim_suffix(".cpp")
		if not files.has(name):name="<toolchain>"
		result.append({"file":name,"line":maxi(1,int(match_value.get_string(2))),"column":maxi(1,int(match_value.get_string(3))),"severity":"error" if match_value.get_string(4)=="fatal error" else match_value.get_string(4),"message":match_value.get_string(5).left(1024)})
		if result.size()>=200:break
	return result

static func addresses(source_map: Array,file: String,line: int) -> Array:
	var result: Array=[]
	for entry in source_map:
		if entry.get("file","")==file and int(entry.get("line",0))==line:
			var pc := int(entry.get("pc",-1))
			if pc>=0 and pc not in result:result.append(pc)
	return result
