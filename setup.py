from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension
from distutils.command.install import install as _install
from pathlib import Path

import urllib.request, tarfile, shutil, os

long_description = Path("README.md").read_text(encoding="utf-8")
description = (long_description.splitlines())[0]

DDDURL = "https://lip6.github.io/libDDD/linux.tgz"

BUILD = Path("build")
DDDTGZ = str(BUILD / "libDDD.tar.gz")
DDDINC = str(BUILD / "usr/local/include")
DDDLIB = str(BUILD / "usr/local/lib")

def copy (src, tgt, verbose=True) :
    if verbose :
        print(src, "->", tgt)
    shutil.copy2(src, tgt)

def copytree (src, tgt, verbose=True) :
    if not tgt.exists() :
        if verbose :
            print(src, "->", tgt)
        tgt.mkdir(exist_ok=True, parents=True)
    for child in src.iterdir() :
        if child.is_dir() :
            copytree(child, tgt / child.name, verbose)
        elif child.is_symlink() :
            _tgt = tgt / child.name
            if not _tgt.exists() :
                if verbose :
                    print(child, "->", _tgt)
                link = os.readlink(str(child))
                _tgt.symlink_to(link)
        elif child.is_file() :
            _tgt = tgt / child.name
            if not _tgt.exists() :
                copy(str(child), str(_tgt), verbose)

class install (_install) :
    def run (self) :
        base = Path(self.install_base)
        print(f"downloading {DDDURL!r}")
        BUILD.mkdir(exist_ok=True)
        with urllib.request.urlopen(DDDURL) as remote, \
             open(DDDTGZ, "wb") as local :
            local.write(remote.read())
        with tarfile.open(DDDTGZ) as tar :
            tar.extractall(BUILD)
        super().run()
        for tree in ("include", "lib") :
            copytree(BUILD / "usr/local" / tree, base / tree)
        for path, names in [(Path(self.install_lib), ["ddd.pxd", "dddwrap.h"])] :
            path.mkdir(exist_ok=True, parents=True)
            for name in names :
                copy(name, path / name)

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
