extends RefCounted

const MAX_BYTES := 256 * 1024
const TEXT_BYTES := 32 * 1024
const EXTENSIONS := {
	"text/plain":"txt", "text/csv":"csv", "application/json":"json", "text/markdown":"md",
	"image/png":"png", "image/jpeg":"jpg", "image/webp":"webp", "application/pdf":"pdf", "application/zip":"zip"
}
const TEXT_EXTENSIONS := ["txt","csv","json","md"]
const PAGE_CHUNK := 2048

static func filename(original: String, extension: String) -> String:
	var stem := ""
	for character in original.replace("\\","/").get_file().get_basename().left(20):
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":stem+=character
	return "%s.%s"%[stem if not stem.is_empty() else "download",extension]

# CEF keeps downloads off. Transfer only bounded bytes from the page's own
# origin or blob URL, using its existing browser session.
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
    if (length > limit) { await reader.cancel(); throw new Error('The file exceeds 256 KB.'); }
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
""".replace("__TOKEN__",JSON.stringify(token)).replace("__LIMIT__",str(MAX_BYTES)).replace("__CHUNK__",str(PAGE_CHUNK))

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
