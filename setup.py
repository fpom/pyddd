from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from distutils.command.install import install as _install
from pathlib import Path

import urllib.request, tarfile

long_description = Path("README.md").read_text(encoding="utf-8")
description = (long_description.splitlines())[0]

BUILD = Path("build")
DDDURL = "https://lip6.github.io/libDDD/linux.tgz"
DDDTGZ = BUILD / "libDDD.tar.gz"
DDDINC = DDDLIB = None

BUILD.mkdir(exist_ok=True)
if not Path(DDDTGZ).exists() :
    print(f"downloading {DDDURL!r}")
    with urllib.request.urlopen(DDDURL) as remote, \
         open(DDDTGZ, "wb") as local :
        local.write(remote.read())
with tarfile.open(DDDTGZ) as tar :
    tar.extractall(BUILD)

class install (_install) :
    def run (self) :
        global DDDINC, DDDLIB
        base = Path(self.install_base)
        DDDINC = base / "include"
        DDDLIB = base / "lib"
        self.copy_tree(str(BUILD / "usr/local/include"),
                       str(base / "include"))
        self.copy_tree(str(BUILD / "usr/local/lib"),
                       str(base / "lib"))
        self.mkpath(self.install_lib)
        self.copy_file("ddd.pxd", self.install_lib)
        self.copy_file("dddwrap.h", DDDINC)
        super().run()

setup(name="pyddd",
      cmdclass={"install" : install})

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
                                       include_dirs = [str(DDDINC)],
                                       libraries = ["DDD"],
                                       library_dirs = [str(DDDLIB)],
                                       language="c++",
                                       extra_compile_args=["-std=c++11"])],
                            language_level=3),
)
