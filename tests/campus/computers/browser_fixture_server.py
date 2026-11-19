"""Loopback-only pages for the embedded browser integration check."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/website-download":
            body = b"""<html><title>WEBSITE_DOWNLOAD</title>
            <form method="post" action="/download-post">
            <button style="position:absolute;left:20px;top:20px;width:175px;height:40px">Download report</button>
            </form><form method="post" action="/download-too-large">
            <button style="position:absolute;left:20px;top:75px;width:175px;height:40px">Download large file</button>
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
        if self.path in ("/notes.txt", "/manual.pdf", "/invalid.png"):
            mime, body = {
                "/notes.txt": ("text/plain; charset=utf-8", b"Campus lab notes"),
                "/manual.pdf": ("application/pdf", b"%PDF-1.7\nfixture"),
                "/invalid.png": ("image/png", b"<html>Not an image</html>"),
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
        if self.path in ("/download-post", "/download-too-large"):
            body = b"%PDF-1.7\n" + b"Actual Chromium POST download"
            if self.path == "/download-too-large":
                body += b"x" * (256 * 1024)
            self.send_response(200)
            self.send_header("Content-Type", "application/pdf")
            self.send_header("Content-Disposition", 'attachment; filename="website-report.pdf"')
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
