extends RefCounted

const MAX_BYTES := 8 * 1024 * 1024
const LEGACY_PAGE_BYTES := 256 * 1024
const TEXT_BYTES := 32 * 1024
const EXTENSIONS := {
	"text/plain":"txt", "text/csv":"csv", "application/json":"json", "text/markdown":"md",
	"image/png":"png", "image/jpeg":"jpg", "image/webp":"webp", "image/gif":"gif", "image/bmp":"bmp",
	"application/pdf":"pdf", "application/zip":"zip", "application/x-zip-compressed":"zip",
	"audio/mpeg":"mp3", "audio/wav":"wav", "audio/x-wav":"wav", "audio/ogg":"ogg", "audio/flac":"flac",
	"audio/mp4":"m4a", "audio/aac":"aac", "audio/webm":"webm",
	"video/mp4":"mp4", "video/webm":"webm", "video/ogg":"ogv", "video/quicktime":"mov",
	"model/gltf-binary":"glb", "model/gltf+json":"gltf", "model/obj":"obj", "model/stl":"stl",
	"application/xml":"xml", "text/html":"html", "text/css":"css", "text/javascript":"js",
	"application/gzip":"gz", "application/x-tar":"tar", "application/x-7z-compressed":"7z",
	"application/vnd.openxmlformats-officedocument.wordprocessingml.document":"docx",
	"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":"xlsx",
	"application/vnd.openxmlformats-officedocument.presentationml.presentation":"pptx"
}
const TEXT_EXTENSIONS := ["txt","csv","tsv","json","jsonl","md","rst","log","xml","yaml","yml","toml","ini","cfg","conf","env","html","htm","css","scss","sass","svg","diff","patch","tex","srt","vtt"]
const CODE_EXTENSIONS := ["campus","gd","cs","py","pyw","js","mjs","cjs","jsx","ts","tsx","c","h","cpp","cc","cxx","hpp","java","kt","kts","go","rs","rb","php","lua","swift","sh","bash","zsh","ps1","bat","cmd","sql","r","dart","vue","svelte","asm","s","zig","ex","exs","erl","hs","scala","clj","lisp","pl","v","sv","vhd","fs","fsx","vb"]
const AUDIO_EXTENSIONS := ["mp3","wav","ogg","oga","flac","m4a","aac"]
const VIDEO_EXTENSIONS := ["mp4","m4v","webm","ogv","mov","mkv","avi"]
const MODEL_EXTENSIONS := ["glb","gltf","obj","stl","ply","fbx","dae","3mf","blend"]
const IMAGE_EXTENSIONS := ["png","jpg","jpeg","webp","gif","bmp","ico","avif","tif","tiff"]
const STORED_EXTENSIONS := ["pdf","zip","7z","rar","tar","gz","tgz","bz2","xz","doc","docx","xls","xlsx","ppt","pptx","odt","ods","odp","epub","rtf","wasm","woff","woff2","ttf","otf"]
const PAGE_CHUNK := 2048

static func filename(original: String, extension: String) -> String:
	var stem := ""
	for character in original.replace("\\","/").get_file().get_basename().left(20):
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_- .":stem+=character
	stem=stem.strip_edges().trim_prefix(".").strip_edges()
	return "%s.%s"%[stem if not stem.is_empty() else "download",extension]

static func is_text(extension: String) -> bool:
	extension=extension.to_lower()
	return extension in TEXT_EXTENSIONS or extension in CODE_EXTENSIONS

static func extension_for(original: String, mime: String) -> String:
	var extension:=original.get_extension().to_lower()
	if is_text(extension) or extension in AUDIO_EXTENSIONS or extension in VIDEO_EXTENSIONS or extension in MODEL_EXTENSIONS or extension in IMAGE_EXTENSIONS or extension in STORED_EXTENSIONS:
		return extension
	return EXTENSIONS.get(mime.get_slice(";",0).strip_edges().to_lower(),"")

# Compatibility bridge for builds without the Chromium download callback.
static func page_script(token: String) -> String:
	return """
(() => {
 const token = __TOKEN__, limit = __LIMIT__, chunk = __CHUNK__;
 if (window.__labvoltDownload) return;
 let report = '', originTitle = '', busy = false;
 const publish = (index) => {
  const part = report.slice(index * chunk, (index + 1) * chunk);
  document.title = '__LVD__' + token + '|' + index + '|' + (part.length < chunk ? '1' : '0') + '|' + part;
 };
 window.__labvoltDownload = (key, index) => {
  if (key !== token || !busy) return;
  if (index < 0) { document.title = originTitle; report = ''; busy = false; return; }
  publish(index);
 };
 document.addEventListener('click', async (event) => {
  const anchor = event.target instanceof Element && event.target.closest('a[download][href]');
  if (!anchor || (!event.isTrusted && !navigator.userActivation.isActive)) return;
  event.preventDefault();
  if (busy) return;
  originTitle = document.title;
  busy = true;
  try {
   const url = new URL(anchor.href, location.href);
   if (url.origin !== location.origin || !['http:', 'https:', 'blob:'].includes(url.protocol))
    throw new Error('Use Download address for an external file.');
   const response = await fetch(url, {redirect: 'error', credentials: 'same-origin', signal: AbortSignal.timeout(15000)});
   if (!response.ok || !response.body) throw new Error('The page could not provide the file.');
   const reader = response.body.getReader();
   let length = 0, bytes = '';
   for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > limit) { await reader.cancel(); throw new Error('Use Download address for files above 256 KiB on this browser build.'); }
    for (let i = 0; i < value.length; i += 4096)
     bytes += String.fromCharCode(...value.subarray(i, i + 4096));
   }
   const mime = (response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
   const name = (anchor.download || url.pathname.split('/').pop() || 'download').slice(0, 128);
   const payload = new TextEncoder().encode(JSON.stringify({name,mime,data:btoa(bytes)}));
   let wire = '';
   for (let i = 0; i < payload.length; i += 4096) wire += String.fromCharCode(...payload.subarray(i,i+4096));
   report = btoa(wire);
  } catch (error) {
   report = btoa(JSON.stringify({error: String(error.message || 'Download failed').replace(/[^ -~]/g, '').slice(0,120)}));
  }
  publish(0);
 }, true);
})();
""".replace("__TOKEN__",JSON.stringify(token)).replace("__LIMIT__",str(LEGACY_PAGE_BYTES)).replace("__CHUNK__",str(PAGE_CHUNK))

static func valid(body: PackedByteArray, extension: String) -> bool:
	if body.size()>MAX_BYTES:return false
	extension=extension.to_lower()
	if is_text(extension):
		var document:=body.get_string_from_utf8()
		return document.to_utf8_buffer()==body
	match extension:
		"png":return body.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10])
		"jpg","jpeg":return body.slice(0,3)==PackedByteArray([255,216,255])
		"webp":return body.slice(0,4)=="RIFF".to_ascii_buffer() and body.slice(8,12)=="WEBP".to_ascii_buffer()
		"pdf":return body.slice(0,5)=="%PDF-".to_ascii_buffer()
		"zip":return body.slice(0,4) in [PackedByteArray([80,75,3,4]),PackedByteArray([80,75,5,6])]
	return not extension.is_empty() and not body.is_empty() and extension_for("file."+extension,"")==extension
