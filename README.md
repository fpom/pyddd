# A Python binding for libDDD

(C) 2024 [Franck Pommereau](franck.pommereau@univ-evry.fr)

This library provides a Python binding for the Data Decision Diagrams
library [libDDD](https://github.com/lip6/libDDD)

## Requirements

- Python 3
- Cython
- libDDD (see below)
- G++ (does not work with clang)

## Installation

First, `libDDD` needs to be installed. Because it uses very tricky
compilation options, a suitable precompiled version is
[provided here](https://github.com/fpom/pyddd/raw/master/libDDD.tar.gz).
It contains two directories: `lib` and `include` that should be copied
so that `ld` will find `lib/libDDD.so`. Installation will assume that
both directories reside together into the same location.

### Installing `libDDD` system-wide

- copy to `/usr/local/lib` and `/usr/local/include`
- add `/usr/local/lib` to `/set/ld.so.conf.d/ldbbb.conf`
- run `ldconfig` as root

### Installing `libDDD` in a virtual environment

- activate the virtual environment
- copy to `$VIRTUAL_ENV/lib` and `$VIRTUAL_ENV/include`
- add environment variable `LD_LIBRRAY_PATH=$VIRTUAL_ENV/lib`

This last step can be achieved by adding a line with
`export LD_LIBRRAY_PATH=$VIRTUAL_ENV/lib` at the end of file
`$VIRTUAL_ENV/bin/activate`.

### Installing `libDDD` in home directory

- copy to `$HOME/.local/lib` and `$HOME/.local/include`
- add environment variable `LD_LIBRRAY_PATH=$HOME/.local/lib`

This last item can be achieved by addding a line with
`export LD_LIBRRAY_PATH=$HOME/.local/lib` to file `~/.bashrc`
(or something equivalent for another shell).

### Installing `pyddd` itself

Clone the repository with `git clone https://github.com/fpom/pyddd.git`.
Change to the created directory with `cd pyddd`. Run`pip install .` as usual.

If `libDDD` has been installed independently, you may run
`pip install git+https://github.com/fpom/pyddd.git` directly.

You may check the doctests in the module by running `python3 test/test.py`,
which should produce no output if everything goes well.

## Usage

Module `ddd` exports two main class called `ddd` and `sdd`, they are
documented through their docstrings.

This binding intends to provide a high-level user interface to libDDD,
so don't expect to be able to access all the internal features as one
could do using libDDD from C++.

## Licence

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
Lesser General Public License for more details.

You have received a copy of the GNU Lesser General Public License
along with this program, see file COPYING or
http://www.gnu.org/licenses
