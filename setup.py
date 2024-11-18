import os
import site
import tarfile

from pathlib import Path

from distutils.core import setup
from setuptools.command.install import install
from distutils.extension import Extension
from Cython.Build import cythonize


##
## install libDDD
##


class InstallDDD(install):
    # install libDDD together with Python package
    def run(self):
        super().run()
        with tarfile.TarFile.open("libDDD.tar.gz") as tar:
            tar.extractall(self.install_base, filter="fully_trusted")


# install libDDD lcoally for build
DDDBASE = Path("libDDD").absolute()
with tarfile.TarFile.open("libDDD.tar.gz") as tar:
    tar.extractall(DDDBASE, filter="fully_trusted")
DDDLIB = DDDBASE / "lib"
DDDINC = DDDBASE / "include"
os.environ["LD_LIBRARY_PATH"] = str(DDDLIB)
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
    # ensure libDDD is installed
    cmdclass={"install": InstallDDD},
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
    data_files=[(site.getsitepackages(".")[0], ["ddd.pxd"])],
)
