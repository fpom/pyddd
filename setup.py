from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from distutils.command.install import install as _install
from pathlib import Path

import urllib.request, tarfile, shutil

long_description = Path("README.md").read_text(encoding="utf-8")
description = (long_description.splitlines())[0]

DDDURL = "https://lip6.github.io/libDDD/linux.tgz"

BUILD = Path("build")
BUILD.mkdir(exist_ok=True)
DDDTGZ = str(BUILD / "libDDD.tar.gz")
DDDINC = str(BUILD / "usr/local/include")
DDDLIB = str(BUILD / "usr/local/lib")

def copy (src, dst, *l, **k) :
    print(src, "->", dst)
    shutil.copy2(src, dst, *l, **k)

class install (_install) :
    def run (self) :
        base = Path(self.install_base)
        print(f"downloading {DDDURL!r}")
        with urllib.request.urlopen(DDDURL) as remote, \
             open(DDDTGZ, "wb") as local :
            local.write(remote.read())
        with tarfile.open(DDDTGZ) as tar :
            tar.extractall(BUILD)
        for tree in ("include", "lib") :
            shutil.copytree(str(BUILD / "usr/local" / tree), str(base / tree),
                            symlinks=True, ignore_dangling_symlinks=True,
                            copy_function=copy,)
        try :
            Path(base / "usr/local").rmdir()
            Path(base / "usr").rmdir()
        except :
            pass
        hdr = Path(self.install_headers)
        hdr.mkdir(exist_ok=True, parents=True)
        copy("ddd.pxd", hdr / "ddd.pxd")
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
      ext_modules=cythonize([Extension("ddd",
                                       ["ddd.pyx"],
                                       include_dirs = [DDDINC],
                                       libraries = ["DDD"],
                                       library_dirs = [DDDLIB],
                                       language="c++",
                                       extra_compile_args=["-std=c++11"])],
                            language_level=3),
      cmdclass={"install" : install},
)
