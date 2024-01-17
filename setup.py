import ctypes
import ctypes.util
import os
import sys

from pathlib import Path
from setuptools import setup, Extension
from Cython.Build import cythonize
from Cython.Compiler import Options

DDDINC = Path("usr/include")
DDDLIB = Path("usr/lib")

Options.docstrings = True
Options.annotate = False


def which_ddd():
    so_name = ctypes.util.find_library("DDD")
    if not so_name:
        return None
    found = []

    class dl_phdr_info(ctypes.Structure):
        _fields_ = [('padding0', ctypes.c_void_p),
                    ('dlpi_name', ctypes. c_char_p)]

    callback_t = ctypes.CFUNCTYPE(ctypes.c_int,
                                  ctypes.POINTER(dl_phdr_info),
                                  ctypes.POINTER(ctypes.c_size_t),
                                  ctypes.c_char_p)
    dl_iterate_phdr = ctypes.CDLL("libc.so.6").dl_iterate_phdr
    dl_iterate_phdr.argtypes = [callback_t, ctypes.c_char_p]
    dl_iterate_phdr.restype = ctypes.c_int

    def callback(info, _, data):
        if data in info.contents.dlpi_name:
            found.append(info.contents.dlpi_name)
        return 0

    _ = ctypes.CDLL(so_name)
    dl_iterate_phdr(callback_t(callback), os.fsencode(so_name))
    if found:
        return found[0].decode()
    else:
        return None


if lib := which_ddd():
    DDDLIB = Path(lib).parent
    DDDINC = DDDLIB.parent / "include"
if not (DDDLIB / "libDDD.so").exists():
    sys.stderr.write(f"{DDDLIB}/libDDD.so not found")
    sys.exit(1)
if not (DDDINC / "ddd/DDD.h").exists():
    sys.stderr.write(f"{DDDINC}/ddd/DDD.h not found")
    sys.exit(1)


extensions = [
    Extension(
        "ddd",
        ["ddd.pyx"],
        language="c++",
        include_dirs=[str(DDDINC)],
        libraries=["DDD"],
        library_dirs=[str(DDDLIB)],
        extra_compile_args=["-std=c++11"],
    ),
]


setup(
    name="ddd",
    ext_modules=cythonize(extensions,
                          language_level=3),
)
