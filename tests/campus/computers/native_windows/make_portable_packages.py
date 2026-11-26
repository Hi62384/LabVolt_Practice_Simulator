"""Build original, unsigned Windows portable package fixtures without installing them."""
import argparse
import ctypes as c
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zlib


def png(size):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    row = b"\0" + b"\x25\x74\x88" * size
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * size)) + chunk(b"IEND", b""))


def make_msi(path, executable, scratch):
    msi = c.WinDLL("msi")

    def check(code):
        if code:
            raise OSError(f"Windows Installer database error {code}")

    raw = scratch / "ClickExe"
    raw.write_bytes(executable.read_bytes())
    cab = scratch / "payload.cab"
    subprocess.run(["makecab.exe", str(raw), str(cab)], check=True, stdout=subprocess.DEVNULL)
    msi.MsiOpenDatabaseW.argtypes = [c.c_wchar_p, c.c_void_p, c.POINTER(c.c_uint)]
    database = c.c_uint()
    check(msi.MsiOpenDatabaseW(str(path), 3, c.byref(database)))

    def sql(query, record=0):
        view = c.c_uint()
        check(msi.MsiDatabaseOpenViewW(database, c.c_wchar_p(query), c.byref(view)))
        try:
            check(msi.MsiViewExecute(view, record))
        finally:
            msi.MsiCloseHandle(view)

    try:
        field_tables = [
            ("Property", "`Property` CHAR(72) NOT NULL, `Value` CHAR(0) NOT NULL LOCALIZABLE PRIMARY KEY `Property`"),
            ("Directory", "`Directory` CHAR(72) NOT NULL, `Directory_Parent` CHAR(72), `DefaultDir` CHAR(255) NOT NULL PRIMARY KEY `Directory`"),
            ("Component", "`Component` CHAR(72) NOT NULL, `ComponentId` CHAR(38), `Directory_` CHAR(72) NOT NULL, `Attributes` SHORT NOT NULL, `Condition` CHAR(255), `KeyPath` CHAR(72) PRIMARY KEY `Component`"),
            ("File", "`File` CHAR(72) NOT NULL, `Component_` CHAR(72) NOT NULL, `FileName` CHAR(255) NOT NULL, `FileSize` LONG NOT NULL, `Version` CHAR(72), `Language` CHAR(20), `Attributes` SHORT, `Sequence` SHORT NOT NULL PRIMARY KEY `File`"),
            ("Media", "`DiskId` SHORT NOT NULL, `LastSequence` SHORT NOT NULL, `DiskPrompt` CHAR(64), `Cabinet` CHAR(255), `VolumeLabel` CHAR(32), `Source` CHAR(72) PRIMARY KEY `DiskId`"),
        ]
        for table, fields in field_tables:
            sql(f"CREATE TABLE `{table}` ({fields})")
        sql("INSERT INTO `Property` (`Property`,`Value`) VALUES ('ProductName','Campus Click Test MSI')")
        sql("INSERT INTO `Directory` (`Directory`,`DefaultDir`) VALUES ('TARGETDIR','SourceDir')")
        sql("INSERT INTO `Component` (`Component`,`Directory_`,`Attributes`,`KeyPath`) VALUES ('App','TARGETDIR',0,'ClickExe')")
        sql(f"INSERT INTO `File` (`File`,`Component_`,`FileName`,`FileSize`,`Attributes`,`Sequence`) VALUES ('ClickExe','App','CLICK.EXE|Campus Click Test.exe',{raw.stat().st_size},16384,1)")
        sql("INSERT INTO `Media` (`DiskId`,`LastSequence`,`Cabinet`) VALUES (1,1,'#payload.cab')")
        record = msi.MsiCreateRecord(2)
        try:
            check(msi.MsiRecordSetStringW(record, 1, c.c_wchar_p("payload.cab")))
            check(msi.MsiRecordSetStreamW(record, 2, c.c_wchar_p(str(cab))))
            sql("INSERT INTO `_Streams` (`Name`, `Data`) VALUES (?, ?)", record)
        finally:
            msi.MsiCloseHandle(record)
        check(msi.MsiDatabaseCommit(database))
    finally:
        msi.MsiCloseHandle(database)


def make_msix(path, executable, scratch, makeappx):
    package = scratch / "appx"
    package.mkdir()
    shutil.copyfile(executable, package / "Click.exe")
    for size in (44, 50, 150):
        (package / f"Logo{size}.png").write_bytes(png(size))
    (package / "AppxManifest.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities" IgnorableNamespaces="uap rescap">
  <Identity Name="LabVolt.CampusClick" Publisher="CN=Campus Fixture" Version="1.0.0.0" ProcessorArchitecture="x64"/>
  <Properties><DisplayName>Campus Click Test MSIX</DisplayName><PublisherDisplayName>Campus Fixture</PublisherDisplayName><Logo>Logo50.png</Logo></Properties>
  <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0"/></Dependencies>
  <Resources><Resource Language="en-us"/></Resources>
  <Applications><Application Id="Click" Executable="Click.exe" EntryPoint="Windows.FullTrustApplication">
    <uap:VisualElements DisplayName="Campus Click Test" Description="Original LabVolt fixture" BackgroundColor="transparent"
      Square150x150Logo="Logo150.png" Square44x44Logo="Logo44.png"/>
  </Application></Applications>
  <Capabilities><rescap:Capability Name="runFullTrust"/></Capabilities>
</Package>
""", encoding="utf-8")
    subprocess.run([str(makeappx), "pack", "/o", "/d", str(package), "/p", str(path)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("destination", type=Path)
    options = parser.parse_args()
    if os.name != "nt":
        parser.error("This fixture builder runs on Windows.")
    sdk = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Windows Kits/10/bin"
    makeappx = next(iter(sorted(sdk.glob("*/x64/makeappx.exe"), reverse=True)), None)
    if makeappx is None:
        parser.error("Install the Windows SDK to build MSIX fixtures.")
    output = options.destination.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="campus-packages-") as tmp:
        scratch = Path(tmp)
        make_msi(output / "Campus Click Package.msi", options.executable.resolve(), scratch)
        make_msix(output / "Campus Click Package.msix", options.executable.resolve(), scratch, makeappx)
