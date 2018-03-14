import argparse, os.path
from distutils.core import setup
from Cython.Build import cythonize
from distutils.extension import Extension

parser = argparse.ArgumentParser("build.py")
parser.add_argument("-I", metavar="PATH", type=str,
                    default=os.path.expanduser("~/.local/include"),
                    help="libDDD source dir containing 'ddd/DDD.h' "
                    "(default '$HOME/.local/include')")
parser.add_argument("-L", metavar="PATH", type=str,
                    default=os.path.expanduser("~/.local/lib"),
                    help="libDDD binary dir (default '$HOME/.local/lib')")

args = parser.parse_args()

extensions = [Extension("ddd",
                        ["ddd.pyx"],
                        include_dirs = [args.I],
                        libraries = ["DDD"],
                        library_dirs = [args.L],
                        language="c++",
                        extra_compile_args=["-std=c++11"])]

setup(ext_modules=cythonize(extensions),
      script_args=["build_ext", "--inplace"])

import ddd
print("built ddd module in %r" % os.path.relpath(ddd.__file__))
