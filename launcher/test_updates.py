"""Exercise the Windows updater against an isolated HTTP release fixture."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from threading import Thread

from package import package


HERE = Path(__file__).resolve().parent
VERSIONS = ["a" * 40 + "-1-1", "b" * 40 + "-2-1", "c" * 40 + "-3-1"]


class Handler(SimpleHTTPRequestHandler):
    requests = []

    def do_GET(self):
        self.requests.append(self.path)
        super().do_GET()

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix="labvolt-updates-") as temporary:
    root = Path(temporary)
    game = root / "game"
    game.mkdir()
    compiler = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
    harness = root / "Harness.cs"
    harness.write_text("""
using System;
using System.IO;
class Harness {
    static int Main(string[] args) {
        var update = new Updater(args[0], new Uri(args[1]), Console.WriteLine);
        try { Console.WriteLine(Path.GetFileName(update.Update().GetAwaiter().GetResult())); }
        catch (Exception error) { Console.WriteLine(error); Console.WriteLine("fallback:" + Path.GetFileName(update.Installed())); }
        return 0;
    }
}
""", encoding="utf-8")
    executable = root / "Harness.exe"
    subprocess.run([str(compiler), "/nologo", "/main:Harness", "/out:" + str(executable),
                    "/reference:System.Windows.Forms.dll", "/reference:System.Drawing.dll",
                    "/reference:System.Web.Extensions.dll", str(HERE / "Launcher.cs"), str(harness)], check=True)
    feed = root / "feed"
    latest = feed / "latest/download"
    latest.mkdir(parents=True)
    (game / "LabVolt.exe").write_bytes(b"engine stays the same")
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=feed))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for index, version in enumerate(VERSIONS):
            (game / "LabVolt.pck").write_bytes(("game build " + str(index)).encode())
            assets = feed / "download" / ("game-" + version)
            package(game, assets, version)
            shutil.copyfile(assets / "manifest.json", latest / "manifest.json")
            if index == 2:
                manifest = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
                (assets / (manifest["files"][1]["blocks"][0]["sha256"] + ".gz")).write_bytes(b"invalid gzip")
            Handler.requests.clear()
            command = [str(executable), str(root / "install"), f"http://127.0.0.1:{server.server_port}/"]
            result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
            expected = version if index < 2 else "fallback:" + VERSIONS[1]
            assert result.stdout.splitlines()[-1] == expected, result.stdout
            downloads = [url for url in Handler.requests if url.endswith(".gz")]
            assert len(downloads) == (2 if index == 0 else 1), downloads
            if index == 0:
                Handler.requests.clear()
                unchanged = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
                assert unchanged.stdout.splitlines()[-1] == version, unchanged.stdout
                assert Handler.requests == ["/latest/download/manifest.json"], Handler.requests
        assert (root / "install" / "current").read_text() == VERSIONS[1]
        print("PASS clean install, no-op check, incremental download and verified rollback")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
