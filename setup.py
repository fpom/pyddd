from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from distutils.command.install import install as _install
from pathlib import Path

import tarfile, os, ctypes, ctypes.util

##
## install precompiled libDDD
##

BUILD  = "build"
DDDTGZ = "libDDD.tar.gz"
DDDINC = f"{BUILD}/include"

Path(BUILD).mkdir(exist_ok=True)
with tarfile.open(DDDTGZ) as tar :
    
    import os
    
    def is_within_directory(directory, target):
        
        abs_directory = os.path.abspath(directory)
        abs_target = os.path.abspath(target)
    
        prefix = os.path.commonprefix([abs_directory, abs_target])
        
        return prefix == abs_directory
    
    def safe_extract(tar, path=".", members=None, *, numeric_owner=False):
    
        for member in tar.getmembers():
            member_path = os.path.join(path, member.name)
            if not is_within_directory(path, member_path):
                raise Exception("Attempted Path Traversal in Tar File")
    
        tar.extractall(path, members, numeric_owner=numeric_owner) 
        
    
    safe_extract(tar, BUILD)

##
## detect libDDD.so
##

def which_ddd () :
    so_name = ctypes.util.find_library("DDD")
    if not so_name :
        return None
    found = []
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
    _ = ctypes.CDLL(so_name)
    dl_iterate_phdr(callback_t(callback), os.fsencode(so_name))
    if found :
        return found[0].decode()
    else :
        return None

DDDPATH = which_ddd()
if not DDDPATH :
    class install (_install) :
        def run (self) :
            self.copy_tree(f"{BUILD}/include", f"{self.install_base}/include")
            self.copy_tree(f"{BUILD}/lib", f"{self.install_base}/lib")
            self.mkpath(self.install_lib)
            super().run()
    setup(cmdclass={"install" : install})

DDDPATH = which_ddd()
if not DDDPATH :
    DDDPATH = f"{BUILD}/lib/libDDD.so"
    print(f"### libDDD not found, using precompiled {DDDPATH}\n"
          f"### this will not work until libDDD is properly installed")

DDDLIB = str(Path(DDDPATH).parent)
print(f"### using '{DDDPATH}' ###")

##
## setup
##

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
      ext_modules=cythonize([Extension("ddd",
                                       ["ddd.pyx"],
                                       language="c++",
                                       include_dirs = [DDDINC],
                                       libraries = ["DDD"],
                                       library_dirs = [DDDLIB],
                                       extra_compile_args=["-std=c++11"],
                                       extra_link_args=["-Wl,--no-as-needed"],
      )],
                            language_level=3),
)
