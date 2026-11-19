extends RefCounted

const MAX_BYTES := 256 * 1024
const TEXT_BYTES := 32 * 1024
const EXTENSIONS := {
	"text/plain":"txt", "text/csv":"csv", "application/json":"json", "text/markdown":"md",
	"image/png":"png", "image/jpeg":"jpg", "image/webp":"webp", "application/pdf":"pdf", "application/zip":"zip"
}
const TEXT_EXTENSIONS := ["txt","csv","json","md"]

static func valid(body: PackedByteArray, extension: String) -> bool:
	if body.size()>MAX_BYTES:return false
	if extension in TEXT_EXTENSIONS:
		var document:=body.get_string_from_utf8()
		return body.size()<=TEXT_BYTES and document.to_utf8_buffer()==body
	match extension:
		"png":return body.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10])
		"jpg":return body.slice(0,3)==PackedByteArray([255,216,255])
		"webp":return body.slice(0,4)=="RIFF".to_ascii_buffer() and body.slice(8,12)=="WEBP".to_ascii_buffer()
		"pdf":return body.slice(0,5)=="%PDF-".to_ascii_buffer()
		"zip":return body.slice(0,4) in [PackedByteArray([80,75,3,4]),PackedByteArray([80,75,5,6])]
	return false
