import os
import sys
import ctypes
import ctypes.util

from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from pathlib import Path


def which_ddd():
    so_name = ctypes.util.find_library("DDD")
    if not so_name:
        return None
    found = []

    class dl_phdr_info(ctypes.Structure):
        _fields_ = [("padding0", ctypes.c_void_p), ("dlpi_name", ctypes.c_char_p)]

    callback_t = ctypes.CFUNCTYPE(
        ctypes.c_int,
        ctypes.POINTER(dl_phdr_info),
        ctypes.POINTER(ctypes.c_size_t),
        ctypes.c_char_p,
    )
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
        return Path(found[0].decode())
    else:
        return None


DDDPATH = which_ddd()
if DDDPATH is None:
    sys.stderr.write("*** could not find libddd ***")
    sys.exit(1)

DDDLIB = DDDPATH.parent
DDDINC = DDDLIB.parent / "include"
os.environ["CXX"] = "g++"

##
## setup
##

long_description = Path("README.md").read_text(encoding="utf-8")
description = (long_description.splitlines())[0]

setup(
    name="pyddd",
    description=description,
    long_description=long_description,
    url="https://github.com/fpom/pyddd",
    author="Franck Pommereau",
    author_email="franck.pommereau@univ-evry.fr",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Scientific/Engineering",
        "License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)",
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
    ext_modules=cythonize(
        [
            Extension(
                "ddd",
                ["ddd.pyx"],
                language="c++",
                include_dirs=[str(DDDINC)],
                libraries=["DDD"],
                library_dirs=[str(DDDLIB)],
                extra_compile_args=["-std=c++11"],
                extra_link_args=["-Wl,--no-as-needed"],
            )
        ],
        language_level=3,
    ),
)
