import sys
from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension

extensions = [Extension("ddd",
                        ["ddd.pyx"],
                        include_dirs = ["."],
                        libraries = ["DDD"],
                        library_dirs = ["/home/franck/.local/lib"],
                        language="c++")]

sys.argv[1:] = ["build_ext", "--inplace"]
setup(ext_modules = cythonize(extensions))
