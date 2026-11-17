"""Convert the pinned Arduino core tarball to an offline Windows ZIP."""
import sys
import tarfile
import zipfile
from pathlib import PurePosixPath

source, destination = sys.argv[1:3]
with tarfile.open(source, "r|bz2") as archive, zipfile.ZipFile(destination, "w") as output:
    for member in archive:
        name = member.name.replace("\\", "/")
        parts = PurePosixPath(name).parts
        if not parts or name.startswith("/") or ".." in parts or ":" in parts[0]:
            raise ValueError("Unsafe Arduino core archive entry")
        if member.isdir():
            continue
        if not member.isfile():
            raise ValueError("Arduino core archive contains a link or special file")
        info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        info.create_system = 0
        data = archive.extractfile(member)
        if data is None:
            raise ValueError("Missing Arduino core data")
        output.writestr(info, data.read())
