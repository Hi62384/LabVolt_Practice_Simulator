"""Package a split Windows Godot export into hash-addressed release assets."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import random
import re


BLOCK_LIMIT = 8 * 1024 * 1024
MINIMUM = 1024 * 1024
MASK = (1 << 22) - 1
random_source = random.Random(129584)
GEAR = [random_source.getrandbits(32) for _ in range(256)]


def blocks(path):
    # Content-defined boundaries re-align after insertions and deletions.
    with path.open("rb") as source:
        pending = b""
        while True:
            data = pending + source.read(BLOCK_LIMIT - len(pending))
            if not data:
                return
            if len(data) <= MINIMUM:
                yield data
                return
            value = 0
            end = len(data)
            for index in range(MINIMUM, len(data)):
                value = ((value << 1) + GEAR[data[index]]) & MASK
                if value == 0:
                    end = index + 1
                    break
            yield data[:end]
            pending = data[end:]


def package(game, output, version):
    if not re.fullmatch(r"[a-f0-9]{40}-[0-9]+-[0-9]+", version):
        raise ValueError("Invalid release version")
    output.mkdir(parents=True, exist_ok=True)
    files = []
    for name in ("LabVolt.exe", "LabVolt.pck"):
        whole = hashlib.sha256()
        chunks = []
        for data in blocks(game / name):
            whole.update(data)
            digest = hashlib.sha256(data).hexdigest()
            asset = output / (digest + ".gz")
            if not asset.exists():
                asset.write_bytes(gzip.compress(data, compresslevel=3, mtime=0))
            chunks.append({"sha256": digest, "size": len(data)})
        if not chunks:
            raise ValueError("Empty game file: " + name)
        files.append({"name": name, "size": sum(chunk["size"] for chunk in chunks),
                      "sha256": whole.hexdigest(), "blocks": chunks})
    if len({chunk["sha256"] for file in files for chunk in file["blocks"]}) > 998:
        raise ValueError("The build exceeds GitHub's release asset limit")
    (output / "manifest.json").write_text(json.dumps(
        {"schema": 1, "version": version, "files": files}, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    package(args.game, args.output, args.version)
