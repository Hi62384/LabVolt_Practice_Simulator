"""Exercise the Windows updater against an isolated HTTP release fixture."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from threading import Thread
from urllib.parse import urlsplit

from package import package


HERE = Path(__file__).resolve().parent
VERSIONS = ["a" * 40 + "-1-1", "b" * 40 + "-2-1", "c" * 40 + "-3-1"]


class Handler(SimpleHTTPRequestHandler):
    requests = []
    failures = 1
    corrupt_once_path = None
    stall_once = True
    stall_once_block_path = None

    def do_GET(self):
        self.requests.append(self.path)
        path = urlsplit(self.path).path
        if self.failures and path == "/latest/download/manifest.json":
            type(self).failures -= 1
            self.send_error(503)
            return
        if self.stall_once and path == "/latest/download/manifest.json":
            type(self).stall_once = False
            payload = (Path(self.directory) / "latest/download/manifest.json").read_bytes()
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.flush()
            time.sleep(1.5)
            try:
                self.wfile.write(payload)
            except OSError:
                pass
            return
        if path == self.corrupt_once_path:
            type(self).corrupt_once_path = None
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"truncated gzip")
            return
        if path == self.stall_once_block_path:
            type(self).stall_once_block_path = None
            payload = (Path(self.directory) / path.lstrip("/")).read_bytes()
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.flush()
            time.sleep(1.5)
            try:
                self.wfile.write(payload)
            except OSError:
                pass
            return
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
        var update = new Updater(args[0], new Uri(args[1]), Console.WriteLine, args.Length > 2 ? int.Parse(args[2]) : 30000);
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
    (game / "piper").mkdir()
    (game / "teacher_voices").mkdir()
    (game / "piper/piper.exe").write_bytes(b"offline voice runtime")
    (game / "piper/Mr serious").write_bytes(b"voice runtime data")
    (game / "teacher_voices/voice.onnx").write_bytes(b"offline voice model")
    (game / "data_CollegeSimulator_windows_x86_64").mkdir()
    (game / "data_CollegeSimulator_windows_x86_64/CollegeSimulator.dll").write_bytes(b"managed circuit solver")
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=feed))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for index, version in enumerate(VERSIONS):
            (game / "LabVolt.pck").write_bytes(("game build " + str(index)).encode())
            assets = feed / "download" / ("game-" + version)
            package(game, assets, version)
            shutil.copyfile(assets / "manifest.json", latest / "manifest.json")
            manifest = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
            if index == 1:
                Handler.corrupt_once_path = "/download/game-" + version + "/" + manifest["files"][1]["blocks"][0]["sha256"] + ".gz"
                Handler.stall_once_block_path = Handler.corrupt_once_path
            if index == 2:
                (assets / (manifest["files"][1]["blocks"][0]["sha256"] + ".gz")).write_bytes(b"invalid gzip")
            Handler.requests.clear()
            command = [str(executable), str(root / "install"), f"http://127.0.0.1:{server.server_port}/"]
            if index in (0, 1):
                command.append("500")
            result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
            expected = version if index < 2 else "fallback:" + VERSIONS[1]
            assert result.stdout.splitlines()[-1] == expected, result.stdout
            downloads = [url for url in Handler.requests if urlsplit(url).path.endswith(".gz")]
            assert len(downloads) == (6 if index == 0 else 3), downloads
            if index == 0:
                manifests = [url for url in Handler.requests if urlsplit(url).path == "/latest/download/manifest.json"]
                assert len(manifests) == 3 and all(urlsplit(url).query.startswith("check=") for url in manifests), manifests
                assert len(set(manifests)) == 3, manifests
                Handler.requests.clear()
                unchanged = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
                assert unchanged.stdout.splitlines()[-1] == version, unchanged.stdout
                assert len(Handler.requests) == 1 and urlsplit(Handler.requests[0]).path == "/latest/download/manifest.json", Handler.requests
        assert (root / "install" / "current").read_text() == VERSIONS[1]
        assert (root / "install" / VERSIONS[1] / "piper/piper.exe").read_bytes() == b"offline voice runtime"
        assert (root / "install" / VERSIONS[1] / "piper/Mr serious").read_bytes() == b"voice runtime data"
        assert (root / "install" / VERSIONS[1] / "teacher_voices/voice.onnx").read_bytes() == b"offline voice model"
        assert (root / "install" / VERSIONS[1] / "data_CollegeSimulator_windows_x86_64/CollegeSimulator.dll").read_bytes() == b"managed circuit solver"
        # A broken local manifest must disable fallback cleanly rather than
        # crashing the launcher when the remote update is also unavailable.
        (root / "install" / VERSIONS[1] / "manifest.json").write_text("not json", encoding="utf-8")
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=30)
        assert result.stdout.splitlines()[-1] == "fallback:", result.stdout
        print("PASS fresh checks, HTTP and stalled manifest/block retries, clean install, incremental update, corrupt download and corrupt local fallback")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
