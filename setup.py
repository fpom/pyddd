from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from distutils.command.install import install as _install
from pathlib import Path

import tarfile, os, ctypes, ctypes.util

##
## untar headers & precompiled lib
##

BUILD  = "build"
DDDTGZ = "libDDD.tar.gz"
DDDINC = f"{BUILD}/include"

Path(BUILD).mkdir(exist_ok=True)
with tarfile.open(DDDTGZ) as tar :
    tar.extractall(BUILD)

##
## detect libDDD.so
##

found = [f"{BUILD}/lib".encode()]
so_name = ctypes.util.find_library("DDD")

if so_name :
    class dl_phdr_info (ctypes.Structure) :
      _fields_ = [('padding0', ctypes.c_void_p),
                  ('dlpi_name', ctypes. c_char_p)]

    callback_t = ctypes.CFUNCTYPE(ctypes.c_int,
                                  ctypes.POINTER(dl_phdr_info),
                                  ctypes.POINTER(ctypes.c_size_t),
                                  ctypes.c_char_p)

    dl_iterate_phdr = ctypes.CDLL("libc.so.6").dl_iterate_phdr
    dl_iterate_phdr.argtypes = [callback_t, ctypes.c_char_p]
    dl_iterate_phdr.restype = ctypes.c_int
    def callback(info, size, data):
        if data in info.contents.dlpi_name:
            found.append(info.contents.dlpi_name)
        return 0
    libddd = ctypes.CDLL(so_name)
    dl_iterate_phdr(callback_t(callback), os.fsencode(so_name))

DDDLIB = str(Path(found[-1].decode()).parent)

print(f"using '{DDDLIB}/{so_name}'")

##
## setup
##

class install (_install) :
    def run (self) :
        self.copy_tree(f"{BUILD}/include", f"{self.install_base}/include")
        self.copy_tree(f"{BUILD}/lib", f"{self.install_base}/lib")
        self.mkpath(self.install_lib)
        self.copy_file("dddwrap.h", self.install_lib)
        self.copy_file("ddd.pxd", self.install_lib)
        super().run()

long_description = Path("README.md").read_text(encoding="utf-8")
description = (long_description.splitlines())[0]

setup(name="pyddd",
      description=description,
      long_description=long_description,
      url="https://github.com/fpom/pyddd",
      author="Franck Pommereau",
      author_email="franck.pommereau@univ-evry.fr",
      classifiers=["Development Status :: 4 - Beta",
                   "Intended Audience :: Developers",
                   "Topic :: Scientific/Engineering",
                   "License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)",
                   "Programming Language :: Python :: 3",
                   "Operating System :: OS Independent"],
      cmdclass={"install" : install},
      ext_modules=cythonize([Extension("ddd",
                                       ["ddd.pyx"],
                                       language="c++",
                                       include_dirs = [DDDINC],
                                       libraries = ["DDD"],
                                       library_dirs = [DDDLIB],
                                       extra_compile_args=["-std=c++11"],
                                       extra_link_args=[],
      )],
                            language_level=3),
)
