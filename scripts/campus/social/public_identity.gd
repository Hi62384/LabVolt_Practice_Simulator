extends RefCounted
# Private academic/reconnect identities must never become public profile IDs.
const PATH := "user://campus_public_identity.key"
var secret := PackedByteArray()
func _init() -> void:
	if FileAccess.file_exists(PATH): secret=FileAccess.get_file_as_bytes(PATH)
	if secret.size()!=32:
		secret=Crypto.new().generate_random_bytes(32)
		var file := FileAccess.open(PATH,FileAccess.WRITE)
		if file!=null: file.store_buffer(secret)
func public_id(private_identity: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256,secret,private_identity.to_utf8_buffer()).hex_encode().substr(0,32)
