extends RefCounted
# Immutable checksum-named blobs. No delete/garbage-collection API.
const Format=preload("res://scripts/inventory_authority/receipt_archive/format.gd")
var root := ""
var checkpoint := Callable() # Test observation/abort only; no successful I/O bypass.
func failure(message: String) -> Dictionary:return {"ok":false,"error":message}
func safe_name(filename: String) -> bool:
 if not filename.ends_with(".bin"):return false
 var hash := filename.trim_suffix(".bin").trim_prefix("v1-")
 return Format.hex_id(hash,64) and hash==hash.to_lower() and filename in [hash+".bin","v1-"+hash+".bin"]
func read_raw(filename: String,limit: int) -> Dictionary:
 if not safe_name(filename):return failure("Archive path must be a checksum-scoped filename")
 var file := FileAccess.open(root+"/"+filename,FileAccess.READ)
 if file==null:return failure("Receipt archive file is missing or unreadable")
 var length := file.get_length()
 if length<1 or length>limit:file.close();return failure("Receipt archive file exceeds hard bound")
 var bytes := file.get_buffer(length);file.close()
 if bytes.size()!=length:return failure("Receipt archive file is torn")
 return {"ok":true,"bytes":bytes}
func read_segment(hash: String) -> Dictionary:
 if not Format.hex_id(hash,64):return failure("Invalid archive reference")
 var result := read_raw(hash+".bin",Format.MAX_SEGMENT)
 if not result.ok:return result
 if Format.digest(result.bytes)!=hash:return failure("Receipt archive checksum mismatch")
 var value=bytes_to_var(result.bytes)
 if not Format.segment(value):return failure("Invalid receipt archive segment")
 return {"ok":true,"segment":value}
func immutable_write(filename: String,bytes: PackedByteArray,limit: int) -> Dictionary:
 if not safe_name(filename):return failure("Archive path must be a checksum-scoped filename")
 if bytes.is_empty() or bytes.size()>limit:return failure("Receipt archive hard size limit")
 var expected := Format.digest(bytes)
 if DirAccess.make_dir_recursive_absolute(root)!=OK:return failure("Could not create receipt archive directory")
 if FileAccess.file_exists(root+"/"+filename):
  var previous := read_raw(filename,limit)
  if not previous.ok:return previous
  if Format.digest(previous.bytes)!=expected:return failure("Existing immutable archive blob is corrupt")
  return {"ok":true,"hash":expected}
 var temporary := root+"/"+filename+".tmp"
 var file := FileAccess.open(temporary,FileAccess.WRITE)
 if file==null:return failure("Could not write receipt archive")
 file.store_buffer(bytes);file.flush()
 var error := file.get_error();file.close()
 if error!=OK:return failure("Receipt archive write failed")
 if checkpoint.is_valid() and checkpoint.call("blob_flushed_before_rename",filename)==false:return failure("Archive rename aborted by observer")
 # Single host writer; never publish a ledger reference until the renamed blob rereads.
 if DirAccess.rename_absolute(temporary,root+"/"+filename)!=OK:return failure("Receipt archive rename failed")
 var verified := read_raw(filename,limit)
 if not verified.ok:return verified
 if Format.digest(verified.bytes)!=expected:return failure("Receipt archive reread checksum mismatch")
 return {"ok":true,"hash":expected}
func put_segment(value: Dictionary) -> Dictionary:
 if not Format.segment(value):return failure("Invalid archive segment to write")
 var bytes := var_to_bytes(value)
 var hash := Format.digest(bytes)
 var result := immutable_write(hash+".bin",bytes,Format.MAX_SEGMENT)
 if not result.ok:return result
 var verified := read_segment(hash)
 return {"ok":true,"hash":hash} if verified.ok else verified
func backup_generation(path: String,slot: String) -> Dictionary:
 if slot not in [".0",".1"]:return failure("Invalid original generation slot")
 var file := FileAccess.open(path+slot,FileAccess.READ)
 if file==null:return failure("Could not read original v1 generation")
 var length := file.get_length()
 if length<1 or length>Format.MAX_FILE:file.close();return failure("Original v1 generation exceeds backup hard limit")
 var bytes := file.get_buffer(length);file.close()
 if bytes.size()!=length:return failure("Original v1 generation is torn during backup")
 var hash := Format.digest(bytes)
 var written := immutable_write("v1-"+hash+".bin",bytes,Format.MAX_FILE)
 if not written.ok:return written
 return {"ok":true,"slot":slot,"sha256":hash}
