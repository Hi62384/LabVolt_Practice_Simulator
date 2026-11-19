"""Loopback-only pages for the embedded browser integration check."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from random import Random
from struct import pack
from zlib import compress, crc32


def report_pdf():
    pixels = bytes(range(256)) * 4096
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 512 512] "
        b"/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /XObject /Subtype /Image /Width 1024 /Height 1024 "
        b"/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1048576 >>\nstream\n"
        + pixels + b"\nendstream",
    ]
    commands = b"q 512 0 0 512 0 0 cm /Im0 Do Q"
    objects.append(f"<< /Length {len(commands)} >>\nstream\n".encode() + commands + b"\nendstream")
    body = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, item in enumerate(objects, 1):
        offsets.append(len(body))
        body += f"{index} 0 obj\n".encode() + item + b"\nendobj\n"
    xref = len(body)
    body += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    for offset in offsets[1:]:
        body += f"{offset:010d} 00000 n \n".encode()
    body += f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(body)


def photo_png():
    width, height = 800, 600
    noise = Random(42)
    scanlines = b"".join(b"\0" + noise.randbytes(width * 3) for _ in range(height))

    def chunk(kind, data):
        return pack(">I", len(data)) + kind + data + pack(">I", crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", compress(scanlines, level=0)) + chunk(b"IEND", b""))


REPORT = report_pdf()
PHOTO = photo_png()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/website-download":
            body = b"""<html><title>WEBSITE_DOWNLOAD</title>
            <form method="post" action="/download-post">
            <button style="position:absolute;left:20px;top:20px;width:175px;height:40px">Download report</button>
            </form><form method="post" action="/download-photo">
            <button style="position:absolute;left:20px;top:75px;width:175px;height:40px">Download photo</button>
            </form><form method="post" action="/download-too-large">
            <button style="position:absolute;left:20px;top:130px;width:175px;height:40px">Download large file</button>
            </form></html>"""
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/signed-download.pdf":
            if "labvolt_session=fixture" not in self.headers.get("Cookie", ""):
                self.send_error(403)
                return
            body = b"%PDF-1.7\n" + b"Campus fixture\n" * 1100
            self.send_response(200)
            self.send_header("Content-Type", "application/pdf")
            self.send_header("Content-Disposition", 'attachment; filename="lecture.pdf"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path in ("/notes.txt", "/manual.pdf", "/invalid.png", "/direct-photo.png"):
            mime, body = {
                "/notes.txt": ("text/plain; charset=utf-8", b"Campus lab notes"),
                "/manual.pdf": ("application/pdf", b"%PDF-1.7\nfixture"),
                "/invalid.png": ("image/png", b"<html>Not an image</html>"),
                "/direct-photo.png": ("image/png", PHOTO),
            }[self.path]
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/private":
            title = "SIGNED_IN" if "labvolt_session=fixture" in self.headers.get("Cookie", "") else "SIGNED_OUT"
            body = f"<html><title>{title}</title><a download='lecture.pdf' href='/signed-download.pdf' style='position:absolute;left:20px;top:20px;width:160px;height:40px'>Download lecture</a></html>".encode()
        else:
            body = b"<html><title>LOGIN</title><form method='post' action='/login'><button style='position:absolute;left:20px;top:20px;width:120px;height:40px'>Sign in</button></form></html>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(size)
        if self.path in ("/download-post", "/download-photo", "/download-too-large"):
            mime, name, body = ("image/png", "website-photo.png", PHOTO) if self.path == "/download-photo" else (
                "application/pdf", "website-report.pdf", REPORT)
            if self.path == "/download-too-large":
                body += b"x" * (8 * 1024 * 1024)
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Disposition", f'attachment; filename="{name}"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self.send_response(302)
        self.send_header("Location", "/private")
        self.send_header("Set-Cookie", "labvolt_session=fixture; HttpOnly; SameSite=Lax")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 28767), Handler).serve_forever()
