"""Next-version trusted benchmark runner component. SOURCE/LIGHT ONLY so far.
Direct real engine, no console wrapper; process-handle and file identity pins.
Native/helper workloads are NOT admitted by this single-process component.
"""
from pathlib import Path
from dataclasses import dataclass
import contextlib,ctypes,hashlib,os,struct,subprocess,time

@dataclass(frozen=True)
class EngineSpec:
    path: Path
    sha256: str
    size: int

def digest(path):
    value=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):value.update(block)
    return value.hexdigest()

def verify_engine(spec):
    path=spec.path.resolve()
    if path.name.casefold()!='godot_v4.5.1-stable_win64.exe':raise RuntimeError('Only pinned actual engine is admitted; console wrapper refused')
    if path.stat().st_size!=spec.size or digest(path)!=spec.sha256:raise RuntimeError('Actual engine byte identity differs')
    with path.open('rb') as stream:
        if stream.read(2)!=b'MZ':raise RuntimeError('Not a PE engine image')
        stream.seek(0x3c);pe=struct.unpack('<I',stream.read(4))[0];stream.seek(pe)
        header=stream.read(24)
        if header[:4]!=b'PE\0\0' or struct.unpack_from('<H',header,4)[0]!=0x8664:raise RuntimeError('Expected x64 engine image')
        optional=stream.read(70)
        if len(optional)<70 or struct.unpack_from('<H',optional,0)[0]!=0x20b or struct.unpack_from('<H',optional,68)[0]!=2:raise RuntimeError('Expected GUI actual engine, not console subsystem')
    return {'path':str(path),'sha256':spec.sha256,'bytes':spec.size,'machine':'x64','subsystem':'Windows GUI actual engine'}

@contextlib.contextmanager
def pin_engine_file(path):
    # This read-only handle denies image replacement/write/delete during launch
    # and measurement. It does not inspect or alter any process.
    if os.name!='nt':raise RuntimeError('Windows identity pin unavailable; no launch')
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
    kernel.CreateFileW.restype=ctypes.c_void_p;kernel.CloseHandle.argtypes=[ctypes.c_void_p]
    handle=kernel.CreateFileW(str(Path(path).resolve()),0x80000000,1,None,3,0x80,None)
    if handle in (None,ctypes.c_void_p(-1).value):raise OSError(ctypes.get_last_error(),'Cannot pin actual engine file; no launch')
    try:yield
    finally:kernel.CloseHandle(handle)


