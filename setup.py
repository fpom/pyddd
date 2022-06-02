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
DDDINC = BUILD / "usr/local/include"
DDDLIB = BUILD / "usr/local/lib"

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
        base = Path(self.install_base)
        self.copy_tree(str(BUILD / "usr/local/include"),
                       str(base / "include"))
        self.copy_tree(str(BUILD / "usr/local/lib"),
                       str(base / "lib"))
        self.mkpath(self.install_lib)
        self.copy_file("ddd.pxd", self.install_lib)
        self.copy_file("dddwrap.h", DDDINC)
        super().run()

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
                                       include_dirs = [str(DDDINC)],
                                       #libraries = ["DDD"],
                                       #library_dirs = [str(DDDLIB)],
                                       extra_objects= [str(DDDLIB / "libDDD.a")],
                                       extra_compile_args=["-std=c++11"],
                                       #extra_link_args=["-Wl,--no-as-needed"]
      )],
                            language_level=3),
)
