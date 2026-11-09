extends RefCounted
# Two independently checksummed generations. A temporary file is never a commit.
var path := ""
var generation := 0
var value := {}
var healthy := true
func open(location: String) -> Error:
	path=location;generation=0;value={};healthy=true
	var exists := false
	for slot in [".0",".1"]:
		if not FileAccess.file_exists(path+slot):continue
		exists=true
		var file := FileAccess.open(path+slot,FileAccess.READ)
		if file==null:continue
		# Validate the length-prefixed record before get_var allocates/reads it.
		# A torn generation is ignored so the other checked generation can recover.
		if file.get_length()>67108864:file.close();healthy=false;return ERR_FILE_CORRUPT
		if file.get_length()<4:file.close();continue
		var encoded_length := file.get_32()
		if encoded_length<4 or encoded_length!=file.get_length()-4:file.close();continue
		file.seek(0)
		var envelope=file.get_var(false);file.close()
		if not envelope is Dictionary or not envelope.get("bytes") is PackedByteArray:continue
		var bytes: PackedByteArray=envelope.bytes
		if bytes.hex_encode().sha256_text()!=envelope.get("hash",""):continue
		var record=bytes_to_var(bytes)
		if not record is Dictionary or not record.get("value") is Dictionary or not record.get("generation") is int:continue
		if record.generation>generation:generation=record.generation;value=record.value
	healthy=not exists or generation>0
	return OK if healthy else ERR_FILE_CORRUPT
func commit(next: Dictionary) -> Error:
	if not healthy or path.is_empty():return ERR_FILE_CORRUPT
	var revision := generation+1
	var target := path+"."+str(revision%2)
	var bytes := var_to_bytes({"generation":revision,"value":next})
	var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_var({"bytes":bytes,"hash":bytes.hex_encode().sha256_text()});file.flush()
	var error := file.get_error();file.close()
	if error!=OK:return error
	error=DirAccess.rename_absolute(target+".tmp",target)
	if error==OK:generation=revision;value=next.duplicate(true)
	return error

