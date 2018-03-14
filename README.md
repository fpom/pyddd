A Python binding for libDDD
===========================

(C) 2018 Franck Pommereau <franck.pommereau@univ-evry.fr>

This library provides a Python binding for the Data Decision Diagrams
library (libDDD) https://github.com/lip6/libDDD

## Requirements

 - libDDD (tested with 1.9.0) installed with the dynamic libraries
   enabled Current version at https://github.com/lip6/libDDD does not
   build them yet, instead use the fork at
   https://github.com/fpom/libDDD
 - Python 3 (tested with 3.5.2), this binding is not expected to work
   with Python 2
 - Cython (tested with 0.27.3)

## Installation

Run `build.py -I DDDINC -L DDDLIB` with Python 3 to build the library.
`DDDINC` is the path where file `ddd/DDD.h` can be found, it defaults
to `$HOME/.local/include`. `DDDLIB` is the path where the dynamic
library is installed (`libDDD.so` under Linux), it defaults to
`$HOME/.local/lib`.

Script `build.py` will create a dynamic library that implements Python
module `ddd` and whose path is printed at the end of script execution.
This file should be copied somewhere on your `PYTHONPATH`.

## Usage

Module `ddd` exports one main class called `ddd`, it is documented
through its docstrings.

This binding intends to provide a high-level user interface to libDDD,
so don't expect to be able to access all the internal features as one
could do using libDDD from C++.

### Status

Currently, only the features from `DDD.h` are included, `SDD.h` will
follows.

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
