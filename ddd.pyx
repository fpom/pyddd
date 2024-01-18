import ast
import re

from pathlib import Path
from collections import defaultdict
from subprocess import check_call

from libcpp.vector cimport vector
from libcpp cimport bool
from libcpp.pair cimport pair

cdef extern from "dddwrap.h" namespace "std":
    cdef cppclass ofstream:
        ofstream()
        ofstream(const string &filename)
        void close()
        ofstream& write(const char* s, int n)
    cdef cppclass ifstream:
        ifstream()
        ifstream(const string &filename)
        void close()
        bool eof()
    void getline(ifstream& i, string& s)

_hom_expr = re.compile(r"^\s*(\S+)\s*(=|==|!=|<=|>=|<|>|\+=)\s*(\S+)\s*$", re.I)

##
## domain (aka, factory)
##

cdef extern from "dddwrap.h":
    cdef DDD ddd_new_ONE()
    cdef DDD ddd_new_EMPTY()
    cdef DDD ddd_new_range(int var, val_t val1, val_t val2, const DDD&d)
    cdef void saveDDD(ofstream &s, vector[DDD] l)
    cdef void loadDDD(ifstream &s, vector[DDD] &l)
    cdef DDD ddd_concat(DDD &a, DDD &b)
    cdef DDD ddd_union(DDD &a, DDD &b)
    cdef DDD ddd_intersect(DDD &a, DDD &b)
    cdef DDD ddd_minus(DDD &a, DDD &b)
    ctypedef pair[val_t,DDD] *ddd_iterator
    cdef ddd_iterator ddd_iterator_begin(DDD d)
    cdef void ddd_iterator_next(ddd_iterator i)
    cdef bint ddd_iterator_end(ddd_iterator i, DDD d)
    cdef DDD ddd_iterator_ddd(ddd_iterator i)
    cdef val_t ddd_iterator_value(ddd_iterator i)
    cdef bint ddd_is_STOP(DDD &d)

cdef extern from "ddd/Hom_Basic.hh":
    cdef Hom setVarConst(int var, int val)
    cdef Hom varEqState(int var, int val)
    cdef Hom varNeqState(int var, int val)
    cdef Hom varGtState(int var, int val)
    cdef Hom varLtState(int var, int val)
    cdef Hom varLeqState(int var, int val)
    cdef Hom varGeqState(int var, int val)
    cdef Hom incVar(int var, int val)
    cdef Hom varEqVar(int var, int var2)
    cdef Hom varNeqVar(int var, int var2)
    cdef Hom varGtVar(int var, int var2)
    cdef Hom varLtVar(int var, int var2)
    cdef Hom varLeqVar(int var, int var2)
    cdef Hom varGeqVar(int var, int var2)


cdef class domain(_domain):
    """`ddd` and `hom` factory

    Only the `ddd` and `hom` instances from the same `domain` are compatible
    with each other. This allows to create them for distinct models without
    interference between their variables names and domains.

    Attributes:
     - `tuple vars`: the variables names for this factory, in the
       order they are arranged in the `ddd`s
     - `int depth`: the number of variables, that is the depth of the `ddd`s
     - `dict doms`: map variables names and numbers to sets of values allow
       for the variable
     - `ddd full`: the set of all possible valuations wrt the variables domain
     - `ddd empty`: the empty set of valuations
     - `ddd one`: the accepting all node
     - `hom id`: the identity homomorphism
    """
    def __cinit__(self, **doms):
        self.vmap = {}
        self.vars = tuple(doms)
        self.depth = len(self.vars)
        self.sdoms = {}
        self.ddoms = {}
        self.full = ddd.__new__(ddd)
        self.one = ddd.__new__(ddd)
        self.empty = ddd.__new__(ddd)
        self.id = hom.__new__(hom)
        self.full.f = self.one.f = self.empty.f = self.id.f = self
        self.id.h = Hom()

    def __init__(self, **doms):
        """initialise a `domain` by defining the variables and their domains

        >>> dom = domain(x=(0, 1), y=2, z=(0, 1, 2))
        >>> dom.vars
        ('x', 'y', 'z')
        >>> dom.depth
        3
        >>> dom.doms
        {'x': {0, 1}, 'y': {0, 1}, 'z': {0, 1, 2}}
        >>> len(dom.full)
        12

        Arguments:
         - `name=values, ...`: for each `str name` defines the values this
           variable is allowed to hold as a collection, the order these names are
           given is the order of the variables in the `ddd`s from to to bottom.
           If `values` is an `int`, it is replaced by `range(values)`
        """
        cdef str name
        cdef int rank
        cdef ddd tmp = ddd.__new__(ddd)
        cdef object dom
        cdef set sdom
        for rank, (name, dom) in enumerate(doms.items()):
            self.vmap[rank] = name
            self.vmap[name] = rank
            if isinstance(dom, int):
                dom = range(dom)
            sdom = self.sdoms[name] = self.sdoms[rank] = set(dom)
            tmp.d = self._from_set(rank, sdom, ddd_new_ONE())
            self.ddoms[name] = self.ddoms[rank] = self.makeddd(tmp.d)
        tmp = self()
        self.full.d = tmp.d
        self.one.d = ddd_new_ONE()
        self.empty.d = ddd_new_EMPTY()

    def __eq__(self, object other):
        """domains equality

        Two domains are equal if they have the same variables, in the same
        order, and with the same domains.

        >>> domain(x=2, y=2) == domain(x=(0, 1), y=(0, 1))
        True
        >>> domain(x=2, y=2) == domain(y=2, x=2)
        False
        """
        cdef domain oth
        if not isinstance(other, domain):
            return False
        oth = <domain>other
        # don't call ddd.__eq__ as it calls domain.checkd that calls domain.__eq__
        return self.full.d.set_equal(oth.full.d) and self.vars == oth.vars

    def __ne__(self, object other):
        "domain inequality"
        return not self.__eq__(other)

    @property
    def doms(self):
        """variable domains
        
        >>> domain(x=2, y=2).doms
        {'x': {0, 1}, 'y': {0, 1}}
        """
        return {v: self.sdoms[v] for v in self.vars}

    cdef DDD _from_set(self, int var, set dom, DDD tail):
        """build a `DDD` from a set

        The `DDD` valuates `var` in set `dom` and is followed by `tail`.
        For instance, `_from_set(2, {1, 4}, d)` is `2 ---1|4--> d`
        """
        cdef DDD d
        cdef val_t m, M, v
        cdef int i
        m, M = min(dom), max(dom)
        if M - m + 1 == len(dom):
            return DDD(var, m, M, tail)
        else:
            for i, v in enumerate(dom):
                if i == 0:
                    d = DDD(var, v, tail)
                else:
                    d = ddd_union(d, DDD(var, v, tail))
            return d

    cdef inline void checkd(self, ddd d):
        "helper method to check that a `ddd` is from this domain"
        if d.f != self:
            raise ValueError("not same domains")

    cdef inline void checkh(self, hom h):
        "helper method to check that a `hom` is from this domain"
        if h.f != self:
            raise ValueError("not same domains")

    cdef inline ddd makeddd(self, DDD d):
        "auxiliary method to make a `ddd` from a `DDD`"
        cdef ddd obj = ddd.__new__(ddd)
        obj.f = self
        obj.d = d
        return obj

    cdef inline hom makehom(self, Hom h):
        "auxiliary method to make a `hom` from a `Hom`"
        cdef hom obj = hom.__new__(hom)
        obj.f = self
        obj.h = h
        return obj

    def __call__(self, **values):
        """create a `ddd` instance

        It expects a valuation given as the keywords arguments to build a `ddd`:

         1. No arguments: return a `ddd` with all possible valuations
         2. `var=values, ...`: return a `ddd` with the variables ranging over the
            provided values (iterables)

        When creating `ddd`, the variables that are not valuated are considered
        to range over all their full domains. The returned `ddd` is the
        Cartesian product of all the variables valuations. For instance:

        >>> dom = domain(x=(0, 1), y=range(5), z=(0, 1))
        >>> d = dom(x=0, y=(1,2))
        >>> d == dom(x=0, y=1, z={0, 1}) | dom(x=0, y=2, z={0, 1})
        True
        """
        cdef str n
        cdef int r, i
        cdef val_t v
        cdef set  vals, dom
        cdef DDD d = ddd_new_ONE()
        cdef ddd t
        for r in reversed(range(self.depth)):
            n = self.vmap[r]
            dom = self.sdoms[n]
            if n in values:
                if isinstance(values[n], int):
                    vals = {values[n]}
                else:
                    vals = set(values[n])
                vals.intersection_update(dom)
                if not vals:
                    raise ValueError(f"no values within domain for '{n}'")
                elif vals == dom:
                    t = self.ddoms[r]
                    d = ddd_concat(t.d, d)
                else:
                    d = self._from_set(r, vals, d)
            else:
                t = self.ddoms[n]
                d = ddd_concat(t.d, d)
        return self.makeddd(d)

    def const(self, ddd vals=None, **values):
        """return a constant `hom` that returns `d`
        
        Expects either a single positional argument that must be a `ddd`, or
        keywords arguments that are passed to `__call__` to produce a `ddd`.

        >>> dom = domain(x=2, y=2)
        >>> h = dom.const(x=0, y=0)
        >>> h(dom.full) == dom(x=0, y=0)
        True
        >>> dom.const(dom(x=0, y=0)) == h
        True
        """
        cdef ddd d
        if vals is None:
            d = self(**values)
        elif values:
            raise TypeError("expected no keywords arguments when a positional"
                            " argument has been supplied")
        else:
            d = vals
        return self.makehom(Hom(d.d))

    def op(self, *args):
        """create a `hom` instance

        Possible calls are:
         - `domain.op("x OP y")`
         - `domain.op("x", "OP", "y")` where `y` is a variable name
         - `domain.op("x", "OP", y)` where `y` is an `int`

        Return a `hom` that computes the given operation, where `OP` is the
        operation to implement:

         1. If `OP` is one of `==`, `!=`, `<=`, `>=`, `<`, `>`, the resulting
            `hom` selects the subset of valuations where `x OP y`. The returned
            `hom` is a selector.
         2. If `OP` is `=`, the resulting `hom` assigns `y` to `x`
         3. If `OP` is `+=`, the resulting `hom` increments `x` by `y`

        As noted above, only the identity `hom` and those constructed with
        comparison operators (case 1) are selectors and are suitable to
        serve as conditions.

        >>> dom = domain(x=2, y=2)
        >>> dom.id.is_selector()
        True
        >>> dom.const(x=0, y=0).is_selector()
        False
        >>> dom.op("x < y").is_selector()
        True
        >>> dom.op("x += 1").is_selector()
        False

        Note also that in cases 2 and 3, when `y` is a variable, we use an 
        inefficient construct that may even fail if the domain of `y` is large.

        Selector homomorphisms always return a subset of their arguments as
        they only filter the paths in it.

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x == 0")
        >>> h(dom.full) == dom(x=0, y={0, 1}) 
        True
        >>> h = dom.op("x != 1")
        >>> h(dom.full) == dom(x=0, y={0, 1})
        True
        >>> h = dom.op("x < 1")
        >>> h(dom.full) == dom(x=0, y={0, 1})  #3
        True
        >>> h = dom.op("x <= 0")
        >>> h(dom.full) == dom(x=0, y={0, 1})
        True
        >>> h = dom.op("x > 0")
        >>> h(dom.full) == dom(x=1, y={0, 1})
        True
        >>> h = dom.op("x >= 1")
        >>> h(dom.full) == dom(x=1, y={0, 1})
        True
        >>> h = dom.op("x == y")
        >>> h(dom.full) == dom(x=0, y=0) | dom(x=1, y=1)
        True
        >>> h = dom.op("x != y")
        >>> h(dom.full) == dom(x=0, y=1) | dom(x=1, y=0)
        True
        >>> h = dom.op("x < y")
        >>> h(dom.full) == dom(x=0, y=1)
        True
        >>> h = dom.op("x <= y")
        >>> h(dom.full) == dom(x=0, y={0, 1}) | dom(x=1, y=1)
        True
        >>> h = dom.op("x > y")
        >>> h(dom.full) == dom(x=1, y=0)
        True
        >>> h = dom.op("x >= y")
        >>> h(dom.full) == dom(x=1, y={0, 1}) | dom(x=0, y=0)
        True

        Other homomorphisms assign variables and thus may return valuations
        that do not exist in their argument. They may even return valuations
        that are not in the domain (see `hom.clip()` to solve this).

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x = 1")
        >>> h(dom(x=0, y={0, 1})) == dom(x=1, y={0, 1})
        True
        >>> h = dom.op("x += 1")
        >>> d = h(dom.full)
        >>> values = list(d.values())
        >>> len(values)
        4
        >>> for i in [1, 2]:
        ...     for j in [0, 1]:
        ...         assert dict(x=i, y=j) in values
        >>> h = dom.op("x = y")
        >>> h(dom.full) == dom(x=0, y=0) | dom(x=1, y=1)
        True
        >>> h = dom.op("x += y")
        >>> d = h(dom.full)
        >>> values = list(d.values())
        >>> len(values)
        4
        >>> assert {'x': 0, 'y': 0} in values
        >>> assert {'x': 1, 'y': 0} in values
        >>> assert {'x': 1, 'y': 1} in values
        >>> assert {'x': 2, 'y': 1} in values
        """
        cdef Hom r
        cdef int var
        cdef str left, op
        cdef object right
        cdef int rint = 0   # suppress warnings about non-initialized variable
        cdef str rstr = ""  # idem
        cdef bint isint = False
        # read args
        if len(args) == 1:
            match = _hom_expr.match(args[0])
            if not match:
                raise ValueError(f"invalid 'hom' expression '{args[0]}'")
            left, op, right = match.groups()
        elif len(args) == 3:
            left, op, right = args
        else:
            raise TypeError(f"expected one or three arguments, got {len(args)}")
        if isinstance(right, int):
            rint = right
            isint = True
        else:
            try:
                rint = int(right)
                isint = True
            except ValueError:
                rstr = right
        # process
        try:
            var = self.vmap[left]
        except KeyError:
            raise ValueError(f"unknown variable {left}")
        if isint:
            # var op int
            if op == "==":
                r = varEqState(var, rint)
            elif op == "!=":
                r = varNeqState(var, rint)
            elif op == ">":
                r = varGtState(var, rint)
            elif op == "<":
                r = varLtState(var, rint)
            elif op == "<=":
                r = varLeqState(var, rint)
            elif op == ">=":
                r = varGeqState(var, rint)
            elif op == "=":
                r = setVarConst(var, rint)
            elif op == "+=":
                r = incVar(var, rint)
            else:
                raise ValueError(f"unsupported operator '{op}'")
        else:
            # var op var
            try:
                rint = self.vmap[rstr]
            except KeyError:
                raise ValueError(f"unknown variable {right}")
            if op == "==":
                r = varEqVar(var, rint)
            elif op == "!=":
                r = varNeqVar(var, rint)
            elif op == ">":
                r = varGtVar(var, rint)
            elif op == "<":
                r = varLtVar(var, rint)
            elif op == "<=":
                r = varLeqVar(var, rint)
            elif op == ">=":
                r = varGeqVar(var, rint)
            elif op == "=":
                r = self._hom_ass(var, rint)
            elif op == "+=":
                r = self._hom_inc(var, rint)
            else:
                raise ValueError(f"unsupported operator '{op}'")
        return self.makehom(r)

    cdef Hom _hom_ass(self, int tgt, int src):
        "auxiliary method to build a `Hom` that assigns `src` to `tgt`"
        cdef val_t v
        cdef int i
        cdef Hom h, t
        cdef set dom = self.sdoms[tgt] & self.sdoms[src]
        if not dom:
            raise ValueError(f"cannot assign '{self.vmap[tgt]}"
                             f" = {self.vmap[src]}': disjoint domains")
        for i, v in enumerate(dom):
            t = hom_circ(setVarConst(tgt, v), varEqState(src, v))
            if i == 0:
                h = t
            else:
                h = hom_union(h, t)
        return h

    cdef Hom _hom_inc(self, int tgt, int src):
        "auxiliary method to build a `Hom` that adds `src` to `tgt`"
        cdef val_t v, s
        cdef int i
        cdef Hom h, t
        cdef set sdom = self.sdoms[src]
        cdef set tdom = self.sdoms[tgt]
        cdef set dom = set()
        for s in sdom:
            for v in tdom:
                if s + v in tdom:
                    dom.add(s)
                    break
        if not dom:
            raise ValueError(f"cannot assign '{self.vmap[tgt]}"
                             f" += {self.vmap[src]}': incompatible domains")
        for i, v in enumerate(dom):
            t = hom_circ(incVar(tgt, v), varEqState(src, v))
            if i == 0:
                h = t
            else:
                h = hom_union(h, t)
        return h

    def save(self, str path, *ddds, **headers):
        """save a series of `ddd`s to a file

        Additional headers can be saved, given as `**headers`. Every header
        is serialized to text using `repr` and will be read back using
        `ast.literal_eval`. Headers `Count` and `Domains` are reserved.

        Arguments:
         - `str path`: where to save to
         - `ddd, ...`: a series of `ddd`s to be saved, at least one is expected
         - `key=value, ...`: an optional series of headers to save together
           with the `ddd`s
        """
        cdef ofstream f = ofstream(path.encode())
        cdef vector[DDD] vec
        cdef ddd d
        cdef int i
        cdef bytes line
        cdef str v, key
        cdef object val
        if not ddds:
            raise ValueError("no ddds provided")
        # save headers
        if "Count" in headers:
            raise ValueError("reserved header 'Count'")
        elif "Domains" in headers:
            raise ValueError("reserved header 'Domains'")
        headers["Count"] = len(ddds)
        headers["Domains"] = {v: self.sdoms[v] for v in self.vars}
        for key, val in sorted(headers.items()):
            line = (f"{key}: {val!r}\n").encode()
            f.write(line, len(line))
        f.write(b"\n", 1)
        # save DDDs
        vec.resize(len(ddds))
        for i, d in enumerate(ddds):
            if not d.f is self:
                raise ValueError("cannot save ddds from another domain")
            vec[i] = d.d
        saveDDD(f, vec)
        f.close()

    def load(self, str path):
        """load a previously saved series of `ddd`s

        Arguments:
         - `str path`: where to load the `ddd`s from

        Return: a pair `headers, [ddd, ...]` with the loaded headers and `ddd`s
        """
        cdef ifstream f = ifstream(path.encode())
        cdef dict headers = {}
        cdef vector[DDD] vec
        cdef int r
        cdef int count = -1
        cdef dict varmap
        cdef str v
        cdef bytes line, h, s
        cdef string rawline
        cdef object obj
        cdef DDD d
        cdef dict doms = {}
        # read headers
        while True:
            getline(f, rawline)
            line = rawline.strip()
            if not line:
                break
            try:
                h, line = (s.strip() for s in line.split(b":", 1))
                obj = ast.literal_eval(line.strip().decode())
            except:
                raise ValueError("invalid header line: %r" % line.decode())
            if h == b"Count":
                count = obj
            elif h == b"Domains":
                doms = obj
            else:
                headers[h.decode()] = obj
        if count < 0:
            raise ValueError("missing header 'Count'")
        elif count == 0:
            raise ValueError("no ddds saved")
        elif not doms:
            raise ValueError("missing header 'Domains'")
        elif doms != {v: self.sdoms[v] for v in self.vars}:
            raise ValueError("incompatible domains")
        elif tuple(doms) != self.vars:
            raise ValueError("incompatible variables ordering")
        # read DDDs
        vec.resize(count)
        loadDDD(f, vec)
        f.close()
        return headers, [self.makeddd(d) for d in vec]


##
## ddd
##


cdef class edge(_edge):
    """the edge of a `ddd`

    Attributes:
     - `str var`: variable name corresponding to the edge source node
     - `int val`: value on the edge
     - `ddd succ`: target node of the edge

    The source node is not given because it is always the `ddd` from which the
    edges are extracted.
    """
    def __cinit__(self, str var, val_t val, ddd succ):
        self.var = var
        self.val = val
        self.succ = succ

    cdef inline tuple tuple(self):
        "return a pair with var number, and val"
        return (self.succ.f.vmap[self.var], self.val)

    cdef inline void check(self, edge other):
        "check if same domain"
        if self.succ.f != other.succ.f:
            raise ValueError("not same domains")

    @property
    def domain(self):
        return self.succ.f

    def __eq__(self, object other):
        """equality

        Two edges are equal if they have the same domain and fields

        """
        cdef edge oth
        if not isinstance(other, edge):
            return False
        oth = <edge>other
        return (self.succ.f == oth.succ.f
                and self.var == oth.var
                and self.val == oth.val
                and self.succ == oth.succ)

    def __ne__(self, object other):
        "inequality"
        return not self.__eq__(other)

    def __lt__(self, edge other):
        """strictly lower than

        Comparison is based on the order of variables in the domain,
        and then the values.
        """
        self.check(other)
        return self.tuple() < other.tuple()

    def __le__(self, edge other):
        """lower than or equal

        Comparison is based on the order of variables in the domain,
        and then the values.
        """
        self.check(other)
        return self.tuple() <= other.tuple()

    def __gt__(self, edge other):
        """strictly greater than

        Comparison is based on the order of variables in the domain,
        and then the values.
        """
        self.check(other)
        return self.tuple() > other.tuple()

    def __ge__(self, edge other):
        """greater than or equal

        Comparison is based on the order of variables in the domain,
        and then the values.
        """
        self.check(other)
        return self.tuple() >= other.tuple()


cdef class ddd(_dd):
    """data-decision-diagram

    This class exposes a high-level representation of class `DDD` from
    `libDDD`. In particular, variable numbers are never exposed, only variable
    names are. Moreover, `ddd` instances are associated with domains
    and only the `ddd`s from the same domain are compatible with each other.
    """
    def __init__(self):
        """class `ddd` should never be instantiated directly

        To construct a `ddd` instance, use either:
         - `domain.__call__()` that is the usual method
         - `domain.one` or `domain.empty` that are less likely
            to be useful
        """
        raise TypeError("class 'ddd' should not be instantiated directly")

    @property
    def domain(self):
        """domain from which the `hom` is

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=1)
        >>> d.domain is dom
        True
        """
        return self.f

    @property
    def vars(self):
        """the variables in this `ddd`

        Usually these are the variables of its domain, by if the `ddd` is the
        internal node of a larger `ddd`, only the trailing part will be
        returned

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=1)  # d is  (x)---0-->(y)---1-->[ONE]
        >>> d.vars
        ('x', 'y')
        >>> e = next(iter(d))  # e is  (x)---0-->(y) 
        >>> e.succ.vars        # e.succ is  (y)---1---> [ONE]
        ('y',)

        Return: `tuple`
        """
        return self.f.vars[self.d.variable():]

    @property
    def head(self):
        """the variable name on the top-node of the `ddd`

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=1)  # d is  (x)---0-->(y)---1-->[ONE]
        >>> d.head
        'x'
        >>> e = next(iter(d))  # e is  (x)---0-->(y) 
        >>> e.succ.head        # e.succ is  (y)---1--->[ONE]
        'y'

        Return: `str`
        """
        return self.f.vmap[self.d.variable()]

    @property
    def stop(self):
        """whether this `ddd` is NULL of ONE

        This allows to test that a traversal of a `ddd` has reached a stop,
        that is either the `ddd` is empty, or it is an accepting leaf at the
        bottom of a larger `ddd`

        >>> dom = domain(x=2, y=2)
        >>> dom.one.stop
        True
        >>> dom.empty.stop
        True
        >>> d = dom(x=0, y=1)  # d is  (x)---0-->(y)---1-->[ONE]
        >>> d.stop
        False
        >>> e = next(iter(d))  # e is  (x)---0-->(y) 
        >>> e.succ.stop        # e.succ is  (y)---1--->[ONE]
        False
        >>> e = next(iter(e.succ))  # e is  (y)---0-->[ONE]
        >>> e.succ.stop             # e.succ is  [ONE]
        True

        Return: `bool`
        """
        return ddd_is_STOP(self.d)

    # FIXME: find a general way to build ddd manually while not breaking domains
    #  def __add__(self, ddd other):
    #      """concatenation
    #
    #      `a + b` replaces "one" terminals of `a` by `b`.
    #      This is used to build a `ddd` by hand, but avoid it unless you known
    #      what you're doing. In particular, this allows to build `ddd`s that are
    #      not valid with respect to the variable ordering or the organisation in
    #      layers of variables.
    #      """
    #      self.f.checkd(other)
    #      return self.f.makeddd(ddd_concat(self.d, other.d))

    def __or__(self, ddd other):
        """union

        `a | b` contains all the valuations contained in `a` or `b`

        >>> dom = domain(x=2, y=2)
        >>> d1 = dom(x=0, y=0) | dom(x=1, y=1)
        >>> d2 = dom(x=1, y=0) | dom(x=0, y=1)
        >>> d1 != d2
        True
        >>> d1 & d2 == dom.empty
        True
        >>> d1 != dom.full != d2
        True
        >>> d1 | d2 == dom.full
        True
        >>> d1 | dom.empty == d1
        True
        """
        self.f.checkd(other)
        return self.f.makeddd(ddd_union(self.d, other.d))

    def __xor__(self, ddd other):
        """disjoint union

        `a ^ b` is `(a | b) - (a & b)`
        """
        return (self | other) - (self & other)

    def __and__(self, object other):
        """intersection

        `a & b` contains all the valuations contained in `a` and `b`

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=0) | dom(x=1, y=1)
        >>> d != dom.full
        True
        >>> d & dom.empty == dom.empty
        True
        >>> d & dom.full == d
        True
        """
        cdef ddd d
        cdef hom h
        if isinstance(other, ddd):
            d = <ddd>other
            self.f.checkd(d)
            return self.f.makeddd(ddd_intersect(self.d, d.d))
        elif isinstance(other, hom):
            h = <hom>other
            self.f.checkh(h)
            return self.f.makehom(hom_intersect_Hom_DDD(h.h, self.d))
        else:
            raise TypeError(f"expected 'ddd' or 'hom' object but got"
                            f" '{other.__class__.__name__}'")

    def __invert__(self):
        """complement within the domain

        `~d == d.domain.full - d`

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=0)
        >>> ~d == dom.full - d
        True
        >>> ~d == dom(x=0, y=1) | dom(x=1, y=0) | dom(x=1, y=1)
        True
        """
        return self.f.full - self

    def __sub__(self, ddd other):
        """difference

        `a - b` contains all the valuations that are in `a` but not in `b`

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=0)
        >>> dom.full - d == dom(x=0, y=1) | dom(x=1, y=0) | dom(x=1, y=1)
        True
        """
        self.f.checkd(other)
        return self.f.makeddd(ddd_minus(self.d, other.d))

    def __eq__(self, object other):
        """equality
        
        `a == b` iff `a` contains exactly the same valuations as `b` and both
        are from the same domain

        >>> dom1 = domain(x=2, y=2)
        >>> dom2 = domain(x=2, y=2)
        >>> dom3 = domain(y=2, x=2)
        >>> dom1(x=0, y=0) == dom2(x=0, y=0)
        True
        >>> dom1(x=0, y=0) == dom3(x=0, y=0)
        False
        >>> dom1(x=0, y=0) == dom1(x=1, y=0)
        False
        """
        cdef ddd oth
        if not isinstance(other, ddd):
            return False
        oth = <ddd>other
        return self.f == oth.f and self.d.set_equal(oth.d)

    def __ne__(self, object other):
        """inequality

        `a != b` iff not `a == b`
        """
        return not self.__eq__(other)

    def __le__(self, ddd other):
        """inclusion

        `a <= b` iff all the valuations in `a` are also in `b` and both are
        from the same domain

        >>> dom = domain(x=2, y=2)
        >>> dom(x=0, y=0) <= dom.full
        True
        >>> dom(x={0, 1}, y={0, 1}) <= dom.full
        True
        """
        return (self | other) == other

    def __lt__(self, ddd other):
        """strict inclusion

        `a < b` iff `a <= b` and `a != b`

        >>> dom = domain(x=2, y=2)
        >>> dom(x=0, y=0) < dom.full
        True
        >>> dom(x={0, 1}, y={0, 1}) < dom.full
        False
        """
        return self != other and self <= other

    def __ge__(self, ddd other):
        """reversed inclusion

        `a >= b` iff `b <= a`

        >>> dom = domain(x=2, y=2)
        >>> dom.full >= dom(x=0, y=0)
        True
        >>> dom(x={0, 1}, y={0, 1}) >= dom.full
        True
        """
        return (self | other) == self

    def __gt__(self, ddd other):
        """reversed strict inclusion

        `a > b` iff `b < a`

        >>> dom = domain(x=2, y=2)
        >>> dom.full > dom(x=0, y=0)
        True
        >>> dom(x={0, 1}, y={0, 1}) > dom.full
        False
        """
        return self != other and self >= other

    def __len__(self):
        """number of valuations

        The length of a `ddd` is the number of valuations it contains.
        Note that the length of ONE is `1` by convention.

        >>> dom = domain(x=2, y=2, z=3)
        >>> len(dom.full)  # 2*2*3
        12
        >>> len(dom.empty)
        0
        >>> len(dom.one)
        1
        >>> len(dom(x=0, y=0, z=0) | dom(x=1, y=1, z=1) | dom(x=1, y=1, z=1))
        2
        """
        return int(self.d.set_size())

    def __bool__(self):
        """a `ddd` is `True` iff it is ONE or contains at least one valuation

        >>> dom = domain(x=2, y=2)
        >>> bool(dom.full)
        True
        >>> bool(dom.empty)
        False
        >>> bool(dom.one)
        True
        >>> bool(dom(x=0, y=0, z=0))
        True
        """
        return self.d.set_size() > 0

    def __hash__(self):
        """hash of a `ddd`

        The hash of a `ddd` is unique wrt its set of valuations. So, two `ddd`s
        `a` and `b` such that `a == b` also have the same hash.
        """
        return int(self.d.hash())

    cdef DDD _pick(self, DDD d):
        "auxiliary method to compute `ddd.pick()`"
        cdef ddd_iterator it
        if ddd_is_STOP(d):
            return d
        it = ddd_iterator_begin(d)
        if ddd_iterator_end(it, d):
            return ddd_new_EMPTY()
        return DDD(d.variable(),
                   ddd_iterator_value(it),
                   self._pick(ddd_iterator_ddd(it)))

    def pick(self, as_dict=False):
        """pick an arbitrary valuation from a `ddd`

        The returned valuation is arbitrary in the sense that we cannot expect
        it to have specific properties, but it is not randomly chosen

        >>> dom = domain(x=2, y=2)
        >>> p = dom.full.pick()
        >>> p <= dom.full
        True
        >>> len(p)
        1

        Arguments:
         - `bool as_dict`: if `True`, the picked valuation is returned as a
           `dict`, otherwise its is returned as a `ddd` (default)

        Return: `ddd` or `dict`
        """
        cdef ddd p = self.f.makeddd(self._pick(self.d))
        cdef dict d
        if as_dict:
            for d in p.values():
                return d
        else:
            return p

    def __iter__(self):
        """yield the edges starting from the top-node of a `ddd`

        Each edge is an instance of class `edge`, this allows to traverse a
        `ddd` considered as a graph.

        >>> dom = domain(x=2, y=2)  # (x)---0|1-->(y)---0|1-->[ONE]
        >>> for x, e in enumerate(sorted(dom.full)):
        ...     assert e.var == "x"
        ...     assert e.val == x
        ...     for y, f in enumerate(sorted(e.succ)):
        ...         assert f.var == "y"
        ...         assert f.val == y
        ...         assert f.succ == dom.one

        Note that sorting the edges as above is generally not a good idea as
        it leads to explicitly enumerate all of them at each level. This was
        only made to exhibit the structure of the (very small) `ddd`.

        Yield: `edge` instances
        """
        cdef ddd_iterator it
        if not self.stop:
            it = ddd_iterator_begin(self.d)
            while not ddd_iterator_end(it, self.d):
                yield edge(self.head,
                           ddd_iterator_value(it),
                           self.f.makeddd(ddd_iterator_ddd(it)))
                ddd_iterator_next(it)

    def values(self):
        """yield all the valuations as `dict`s

        This method explicitly enumerates the `ddd` and is inefficient
        on large `ddd`s.

        >>> dom = domain(x=2, y=2)
        >>> values = list(dom.full.values())
        >>> len(values)
        4
        >>> for i in [0, 1]:
        ...     for j in [0, 1]:
        ...         assert dict(x=i, y=j) in values

        Yield: `dict`
        """
        cdef edge e
        cdef dict s
        if self.stop:
            yield {}
        else:
            for e in self:
                for s in e.succ.values():
                    yield {e.var: e.val} | s

    def domains(self, dict doms=None):
        """compute the actual domains of variables

        For each variable `v`, this is the set values that `v` can have among
        all the valuations stored in the `ddd`.

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=0, y=1)
        >>> d.domains() == {'x': {0}, 'y': {1}}
        True

        Arguments:
         - `dict doms`: if not `None`, this `dict` is updated otherwise, a fresh
           `dict` is used

        Return: a `dict` mapping variable names to `set`s
        """
        cdef edge e
        if doms is None:
            doms = {}
        doms.setdefault(self.head, set())
        for e in self:
            doms[e.var].add(e.val)
            e.succ.domains(doms)
        return doms

    def _dot(self, out, nid, node, parent=None):
        nid[node] = len(nid)
        if node.stop:
            out.write(f'    "n{nid[node]}" [shape=square, label="1"];\n')
        elif parent is None:
            out.write(f'    "n{nid[node]}" [label="{node.head}"];\n')
        else:
            out.write(f'    "n{nid[node]}" [label="{node.head}@{parent}"];\n')
        edges = defaultdict(set)
        for e in node:
            if e.succ not in nid:
                self._dot(out, nid, e.succ)
            edges[e.succ].add(e.val)
        for succ, values in edges.items():
            m, M = min(values), max(values)
            if m == M:
                lbl = f"{m}"
            if (count := len(values)) == M - m + 1 and count > 2:
                lbl = f"{m}..{M}"
            else:
                lbl = "|".join(str(v) for v in sorted(values))
            out.write(f'    n{nid[node]} -> n{nid[succ]} [label="{lbl}"];\n')

    def dot(self, path):
        """dump `ddd` to GraphViz `dot` format

        If `path` as suffix `.dot`, a `dot` file is just saved, otherwise, it is
        converted to the corresponding format (eg, `pdf`, `png`, `svg`, or any
        format supported by the local GraphViz installation)

        Arguments:
         - `str|pathlib.Path path`: target file
        """
        path = Path(path)
        path_dot = path.with_suffix(".dot")
        with path_dot.open("w") as out:
            out.write("digraph ddd {\n")
            self._dot(out, defaultdict(), self)
            out.write("}\n")
        if (fmt := path.suffix.lower().lstrip(".")) != "dot":
            check_call(["dot", f"-T{fmt}", "-o", path, path_dot])

##
## Hom
##

cdef extern from "dddwrap.h":
    cdef bint hom_eq(Hom a, Hom b)
    cdef bint hom_ne(Hom a, Hom b)
    cdef Hom hom_neg(Hom a)
    cdef DDD hom_call(Hom h, DDD d)
    cdef Hom hom_union(Hom a, Hom b)
    cdef Hom hom_circ(Hom a, Hom b)
    cdef Hom hom_intersect_DDD_Hom(DDD a,Hom b)
    cdef Hom hom_intersect_Hom_DDD(Hom a, DDD b)
    cdef Hom hom_intersect_Hom_Hom(Hom a, Hom b)
    cdef Hom hom_minus_Hom_DDD(Hom a, DDD b)
    cdef Hom hom_ITE(Hom a, Hom b, Hom c)
    cdef Hom fixpoint(const Hom &h)


cdef class hom(_hom):
    """homomorphisms on a `ddd`

    This class exposes a high-level representation of class `Hom` from `libDDD`.
    As for class `ddd`, instances are associated with domains and only the
    `ddd`s and `hom`s from the same domain are compatible with each other.
    """
    def __init__(self):
        """class `hom` should never be instantiated directly

        To construct a `hom` instance, use either:
         - `domain.id`
         - `domain.const()`
         - `domain.op()`
        """
        raise TypeError("class 'hom' should not be instantiated directly")

    @property
    def domain(self):
        "domain from which the `hom` is"
        return self.f

    def __hash__(self):
        "hash of a `hom`"
        return int(self.h.hash())

    def __eq__(self, object other):
        """equality of two `hom`

        Two `hom` instances are equal if they are the same operation and are
        both from the same domain.
        """
        cdef hom oth
        if not isinstance(other, hom):
            return False
        oth = <hom>other
        return self.f == oth.f and hom_eq(self.h, oth.h)

    def __ne__(self, object other):
        """inequality

        `a != b` iff not `a == b`
        """
        return not self.__eq__(other)

    def __invert__(self):
        """negation of a selector `hom`

        `(~h)(d) == d - h(d)`

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x == 0")
        >>> (~h)(dom.full) == dom(x=1, y={0, 1})
        True
        """
        if not self.is_selector():
            raise ValueError("not a selector")
        return self.f.makehom(hom_neg(self.h))

    def __call__(self, ddd d):
        """application onto a `ddd`

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x == 0")
        >>> h(dom.full) == dom(x=0, y={0, 1})
        True

        Return: the resulting `ddd`
        """
        self.f.checkd(d)
        return self.f.makeddd(hom_call(self.h, d.d))

    def __or__(self, hom other):
        """union of two `hom`

        `(h1 | h2)(d) == h1(d) | h2(d)`

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x == 0") | dom.op("y == 0")
        >>> h(dom.full) == dom.full - dom(x=1, y=1)
        True
        """
        self.f.checkh(other)
        return self.f.makehom(hom_union(self.h, other.h))

    def __mul__(self, hom other):
        """composition of two `hom`
        
        `(h1 * h2)(d) == h1(h2(d))`

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x += 1") * dom.op("x == 0")  # select x==0, then do x += 1
        >>> h(dom.full) == dom(x=1, y={0, 1})
        True
        """
        self.f.checkh(other)
        return self.f.makehom(hom_circ(self.h, other.h))

    def __and__(self, object other):
        """intersection with a `ddd` or another `hom`

        `(h & d1)(d2) == h(d1) & d2`
        `(h1 & h2)(d) == h1(d) & h2(d)`

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x += 1")
        >>> d = h(dom.full)
        >>> values = list(d.values())
        >>> assert len(values) == 4
        >>> assert {"x": 1, "y": 0} in values
        >>> assert {"x": 1, "y": 1} in values
        >>> assert {"x": 2, "y": 0} in values
        >>> assert {"x": 2, "y": 1} in values
        >>> (h & dom.full)(dom.full) == dom(x=1, y={0, 1})
        True
        >>> (h & dom.op("x <= 1"))(dom.full) == dom(x=1, y={0, 1})
        True
        """
        cdef ddd d
        cdef hom h
        if isinstance(other, ddd):
            d = <ddd>other
            self.f.checkd(d)
            return self.f.makehom(hom_intersect_Hom_DDD(self.h, d.d))
        elif isinstance(other, hom):
            h = <hom>other
            self.f.checkh(h)
            if not other.is_selector():
                raise ValueError("not a selector")
            return self.f.makehom(hom_intersect_Hom_Hom(self.h, h.h))
        else:
            raise TypeError(f"expected 'hom' or 'ddd' object but got"
                            f" '{other.__class__.__name__}'")

    def __sub__(self, ddd other):
        """difference with a `ddd`

        `(h - d1)(d2) == h(d1) - d2`

        >>> dom = domain(x=2, y=2)
        >>> d = dom(x=1, y=1)
        >>> h = dom.op("x += 1") * dom.op("x == 0")
        >>> (h - d)(dom.full) == dom(x=1, y=0)
        True
        """
        self.f.checkd(other)
        return self.f.makehom(hom_minus_Hom_DDD(self.h, other.d))

    cpdef hom ite(self, hom then, hom orelse=None):
        """if-then-else composition

        `h.ite(h1, h2)(d)` is `h1(d)` if `h(d)` is not empty, otherwise it is
        `h2(d)`. If `h2` is omitted, it is replaced with the identity `hom`
        
        >>> dom = domain(x=2, y=2)
        >>> cond = dom.op("x == 0")
        >>> then = dom.op("x += 1")
        >>> h = cond.ite(then)
        >>> h(dom.full) == dom(x=1, y={0, 1})
        True
        >>> h = cond.ite(then, dom.const(x=0, y=0))
        >>> h(dom.full) == dom(x=1, y={0, 1}) | dom(x=0, y=0)
        True
        """
        if not self.is_selector():
            raise ValueError("not a selector")
        self.f.checkh(then)
        if orelse is None:
            return self.f.makehom(hom_ITE(self.h, then.h, self.f.id.h))
        else:
            self.f.checkh(orelse)
            return self.f.makehom(hom_ITE(self.h, then.h, orelse.h))

    cpdef hom fixpoint (self):
        """fixpoint homomorphism

        `h.fixpoint(d)` is equivalent to compute `d = h(d)` until a fixpoint is
        reached.

        Note: this operation is not guaranteed to converge, use `lfp` and `gfp`
        instead to have such a guarantee.
        """
        return self.f.makehom(fixpoint(self.h))

    cpdef hom lfp (self):
        """least fixpoint homomorphism

        This is `(h | id).fixpoint()`, where `id` is the identity homomorphism,
        that is guaranteed to converge. This results in an homomorphism that
        tends to grow its argument.

        >>> dom = domain(x=10)
        >>> h = dom.op("x < 9").ite(dom.op("x += 1"))
        >>> (h.lfp())(dom(x=0)) == dom.full
        True
        """
        return (self | self.f.id).fixpoint()

    cpdef hom gfp(self):
        """greatest fixpoint homomorphism

        This is `(h & id).fixpoint()`, where `id` is the identity homomorphism,
        that is guaranteed to converge. This results in an homomorphism that
        tends to shrink its arguments.

        >>> dom = domain(x=10)
        >>> h = dom.op("x < 9").ite(dom.op("x += 1"))
        >>> (h.gfp())(dom.full) == dom(x=9)
        True
        """
        return (self & self.f.id).fixpoint()

    cpdef hom invert(self, ddd potential=None):
        """predecessor homomorphism

        If `h(d1)` == d2` then `h.invert()(d2) == d1`, where `d1` is included
        into the domain from which `h` is. If the domain needs to be further
        restricted to a subdomain `p` (for instance a set of reachable states),
        use `h.invert(p)`.

        >>> dom = domain(x=2, y=2)
        >>> h = dom.op("x += 1") * dom.op("x == 0")  # selects x==0, then x+=1
        >>> f = h.invert()
        >>> f(dom(x=1, y=1)) == dom(x=0, y=1)
        True
        """
        cdef DDD p
        if potential is not None:
            self.f.checkd(potential)
            p = potential.d
        else:
            p = self.f.full.d
        return self.f.makehom(self.h.invert(p))

    cpdef bint is_selector(self):
        """check whether the homomorphism is a selector

        A selector is a homomorphism that only selects paths of a `ddd` but
        does not change the valuations and does not add paths.
        """
        return self.h.is_selector()

    cpdef hom clip(self):
        """restriction tho the domain

        `h(d)` is not guaranteed to be included in the domain of `h`,
        but `h.clip()(d)` is as it is `h & h.domain.full`

        >>> dom = domain(x=(0, 1))
        >>> d = dom(x=0)
        >>> h = dom.op("x += 5")
        >>> h(d) <= dom.full
        False
        >>> for v in h(d).values():
        ...     print(v)
        {'x': 5}
        >>> h.clip()(d) <= dom.full
        True
        >>> len(h.clip()(d))
        0
        """
        return self & self.f.full


##
## hierarchical domains
##

cdef extern from "dddwrap.h" :
    # sdd
    cdef SDD sdd_new_SDDs(int var, const SDD &val, const SDD &s)
    cdef SDD sdd_new_SDDd(int var, const DDD &val, const SDD &s)
    cdef const SDD sdd_ONE
    cdef SDD sdd_new_ONE()
    cdef SDD sdd_new_EMPTY()
    cdef SDD sdd_new_TOP()
    cdef bint sdd_is_STOP(SDD &s)
    cdef bint sdd_is_ONE(SDD &s)
    cdef bint sdd_is_NULL(SDD &s)
    cdef bint sdd_is_TOP(SDD &s)
    cdef SDD sdd_concat(SDD &a, SDD &b)
    cdef SDD sdd_union(SDD &a, SDD &b)
    cdef SDD sdd_intersect(SDD &a, SDD &b)
    cdef SDD sdd_minus(SDD &a, SDD &b)
    cdef bint sdd_eq(SDD &a, SDD &b)
    cdef bint sdd_ne(SDD &a, SDD &b)
    # sdd iterators
    ctypedef DDD* DDD_star
    ctypedef vector[pair[DDD_star,SDD]] sdd_iterator
    cdef sdd_iterator sdd_iterator_begin(SDD s)
    cdef void sdd_iterator_next(sdd_iterator i)
    cdef bint sdd_iterator_end(sdd_iterator i, SDD s)
    cdef SDD sdd_iterator_sdd(sdd_iterator i)
    cdef bint sdd_iterator_value_is_DDD(sdd_iterator i)
    cdef bint sdd_iterator_value_is_SDD(sdd_iterator i)
    cdef bint sdd_iterator_value_is_GSDD(sdd_iterator i)
    cdef SDD *sdd_iterator_SDD_value(sdd_iterator i)
    cdef SDD *sdd_iterator_GSDD_value(sdd_iterator i)
    cdef DDD *sdd_iterator_DDD_value(sdd_iterator i)
    # shom
    cdef Shom shom_new_Shom (const SDD &s)
    cdef Shom shom_new_Shom_null ()
    cdef Shom shom_new_Shom_var_ddd(int var, const DDD &val, const Shom &s)
    cdef Shom shom_new_Shom_var_sdd(int var, const SDD &val, const Shom &s)
    cdef Shom shom_neg(const Shom &s)
    cdef bint shom_eq(const Shom &a, const Shom &b)
    cdef bint shom_ne(const Shom &a, const Shom &b)
    cdef SDD shom_call(const Shom &h, const SDD &s)
    cdef Shom shom_union(const Shom &a, const Shom &b)
    cdef Shom shom_circ(const Shom &a, const Shom &b)
    cdef Shom shom_intersect_Shom_SDD(const Shom &a, const SDD &b)
    cdef Shom shom_intersect_SDD_Shom(const SDD &a, const Shom &b)
    cdef Shom shom_intersect_Shom_Shom(const Shom &a, const Shom &b)
    cdef Shom shom_minus_Shom_SDD(const Shom &a, const SDD &b)
    cdef Shom shom_minus_Shom_Shom(const Shom &a, const Shom &b)
    cdef Shom shom_invert(const Shom &s, const SDD &d)
    cdef Shom fixpoint(const Shom &s)


cdef class sdomain(_domain):
    def __cinit__(self, **doms):
        self.vmap = {}
        self.ddoms = {}
        self.vars = tuple(doms)
        self.depth = len(self.vars)
        self.full = sdd.__new__(sdd)
        self.one = sdd.__new__(sdd)
        self.empty = sdd.__new__(sdd)
        self.id = shom.__new__(shom)
        self.full.f = self.one.f = self.empty.f = self.id.f = self
        self.id.h = Shom()

    def __init__(self, **doms):
        """
        >>> dom = sdomain(a=domain(x=2, y=2), b=domain(u=2, v=2))
        >>> dom.vars
        ('a', 'b')
        >>> dom.depth
        2
        >>> dom.doms
        {'a': {'x': {0, 1}, 'y': {0, 1}}, 'b': {'u': {0, 1}, 'v': {0, 1}}}
        >>> len(dom.full)
        16
        """
        cdef int rank
        cdef str name
        cdef object dom
        cdef sdd tmp
        for rank, (name, dom) in enumerate(doms.items()):
            if not isinstance(dom, _domain):
                raise TypeError(f"expected 'domain' or 'sdomain' object but got"
                                f" '{dom.__class__.__name__}'")
            self.vmap[name] = rank
            self.vmap[rank] = name
            self.ddoms[name] = self.ddoms[rank] = dom
        tmp = self()
        self.full.s = tmp.s
        self.empty.s = sdd_new_EMPTY()
        self.one.s = sdd_new_ONE()

    def __eq__(self, object other):
        """
        >>> dom1 = sdomain(a=domain(x=2, y=2), b=domain(u={0, 1}, v={0, 1}))
        >>> dom2 = sdomain(a=domain(x={0, 1}, y={0, 1}), b=domain(u=2, v=2))
        >>> dom3 = sdomain(a=domain(x=2, y=2), b=domain(m=2, n=2))
        >>> dom1 == dom2
        True
        >>> dom3 == dom1
        False
        """
        cdef int r
        cdef sdomain oth
        if not isinstance(other, sdomain):
            return False
        oth = <sdomain>other
        return (self.vars == oth.vars
                and all(self.ddoms[r] == oth.ddoms[r]
                        for r in range(self.depth)))

    def __ne__(self, object other):
        return not self.__eq__(other)

    @property
    def doms(self):
        """
        >>> sdomain(a=domain(x=2, y=2), b=domain(u=2, v=2)).doms
        {'a': {'x': {0, 1}, 'y': {0, 1}}, 'b': {'u': {0, 1}, 'v': {0, 1}}}
        """
        return {v: self.ddoms[v].doms for v in self.vars}

    cdef inline void checks(self, sdd s):
        if s.f != self:
            raise ValueError("not same domains")

    cdef inline void checkh(self, shom h):
        if h.f != self:
            raise ValueError("not same domains")

    cdef inline sdd makesdd(self, SDD s):
        cdef sdd obj = sdd.__new__(sdd)
        obj.f = self
        obj.s = s
        return obj

    cdef inline shom makeshom(self, Shom h):
        cdef shom obj = shom.__new__(shom)
        obj.f = self
        obj.h = h
        return obj

    def __call__(self, **values):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> ab(a=xy(x=0, y=0)) == ab(a=xy(x=0, y=0), b=uv.full)
        True
        """
        cdef SDD s = sdd_new_ONE()
        cdef int r
        cdef str n
        cdef object dom
        for r in reversed(range(self.depth)):
            n = self.vmap[r]
            dom = self.ddoms[r]
            if isinstance(dom, domain):
                if n in values:
                    s = sdd_new_SDDd(r, (<ddd>(values[n])).d, s)
                else:
                    s = sdd_new_SDDd(r, (<domain>dom).full.d, s)
            else:
                if n in values:
                    s = sdd_new_SDDs(r, (<sdd>(values[n])).s, s)
                else:
                    s = sdd_new_SDDs(r, (<sdomain>dom).full.s, s)
        return self.makesdd(s)

    def const(self, sdd vals=None, **values):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> h = ab.const(a=xy(x=0, y=0))
        >>> h(ab.full) == ab(a=xy(x=0, y=0), b=uv.full)
        True
        """
        cdef sdd s
        if vals is None:
            s = self(**values)
        elif values:
            raise TypeError("expected no keywords arguments when a positional"
                            " argument has been supplied")
        else:
            s = vals
        return self.makeshom(Shom(s.s))

    def op(self, **values):
        # FIXME: build a shom from shom/hom on its variables
        raise NotImplementedError

    def save(self, str path, *sdds, **headers):
        # FIXME: collect and save inner DDD, save SDD nesting as header
        raise NotImplementedError

    def load(self, str path):
        # FIXME: reload saved DDD and SDD nesting
        raise NotImplementedError


##
## sdd
##


cdef class sedge(_edge):
    def __cinit__(self, str var, _dd val, sdd succ):
        self.var = var
        self.val = val
        self.succ = succ

    cdef inline tuple tuple(self):
        return (self.succ.f.vmap[self.var], self.val)

    cdef inline void check(self, sedge other):
        if self.succ.f != other.succ.f:
            raise ValueError("not same domains")

    @property
    def domain(self):
        return self.succ.f

    def __eq__(self, object other):
        cdef sedge oth
        if not isinstance(other, sedge):
            return False
        oth = <sedge>other
        return (self.succ.f == oth.succ.f
                and self.var == oth.var
                and self.val == oth.val
                and self.succ == oth.succ)

    def __ne__(self, object other):
        return not self.__eq__(other)

    def __lt__(self, sedge other):
        self.check(other)
        return self.tuple() < other.tuple()

    def __le__(self, sedge other):
        self.check(other)
        return self.tuple() <= other.tuple()

    def __gt__(self, sedge other):
        self.check(other)
        return self.tuple() > other.tuple()

    def __ge__(self, sedge other):
        self.check(other)
        return self.tuple() >= other.tuple()


cdef class sdd(_dd):
    def __init__(self):
        raise TypeError("class 'sdd' should not be instantiated directly")

    @property
    def domain(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s = ab(a=xy(x=0, y=0), b=uv(u=1, v=1))
        >>> s.domain is ab
        True
        """
        return self.f

    @property
    def vars(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s = ab(a=xy(x=0, y=0), b=uv(u=1, v=1))
        >>> s.vars
        ('a', 'b')
        >>> e = next(iter(s))
        >>> e.succ.vars
        ('b',)
        """
        return self.f.vars[self.s.variable():]

    @property
    def head(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s = ab(a=xy(x=0, y=0), b=uv(u=1, v=1))
        >>> s.head
        'a'
        >>> e = next(iter(s))
        >>> e.succ.head
        'b'
        """
        return self.f.vmap[self.s.variable()]

    @property
    def stop(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> ab.one.stop
        True
        >>> ab.empty.stop
        True
        >>> s = ab(a=xy(x=0, y=0), b=uv(u=1, v=1))
        >>> s.stop
        False
        >>> e = next(iter(s))
        >>> e.succ.stop
        False
        >>> e = next(iter(e.succ))
        >>> e.succ.stop
        True
        """
        return sdd_is_STOP(self.s)

    def __or__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> s01 != s10
        True
        >>> s01 & s10 == ab.empty
        True
        >>> s00 | s01 | s10 | s11 == ab.full
        True
        >>> s01 | ab.empty == s01
        True
        """
        self.f.checks(other)
        return self.f.makesdd(sdd_union(self.s, other.s))

    def __xor__(self, sdd other):
        return (self | other) - (self & other)

    def __and__(self, object other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s01 != s10
        True
        >>> s01 & s10 == ab.empty
        True
        >>> s01 & ab.full == s01
        True
        """
        cdef sdd s
        cdef shom h
        if isinstance(other, sdd):
            s = <sdd>other
            self.f.checks(s)
            return self.f.makesdd(sdd_intersect(self.s, s.s))
        elif isinstance(other, shom):
            h = <shom>other
            self.f.checkh(h)
            return self.f.makeshom(shom_intersect_SDD_Shom(self.s, h.h))
        else:
            raise TypeError(f"expected 'sdd' or 'shom' object but got"
                            f" '{other.__class__.__name__}'")

    def __invert__(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> ~s00 == ab.full - s00
        True
        >>> ~s00 == s01 | s10 | s11
        True
        """
        return self.f.full - self

    def __sub__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> ab.full - s00 == s01 | s10 | s11
        True
        """
        self.f.checks(other)
        return self.f.makesdd(sdd_minus(self.s, other.s))

    def __eq__(self, object other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> ab.full == s00 | s01 | s10 | s11
        True
        >>> s01 == s10
        False
        """
        cdef sdd oth
        if not isinstance(other, sdd):
            return False
        oth = <sdd>other
        return self.f == oth.f and sdd_eq(self.s, oth.s)

    def __ne__(self, object other):
        return not self.__eq__(other)

    def __le__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> s00 | s01 | s10 | s11 <= ab.full
        True
        >>> s00 | s01 | s10 <= ab.full
        True
        >>> s00 | s01 | s10 <= s01 | s10 | s11
        False
        """
        return (self | other) == other

    def __lt__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> s00 | s01 | s10 | s11 < ab.full
        False
        >>> s00 | s01 | s10 < ab.full
        True
        >>> s00 | s01 | s10 < s01 | s10 | s11
        False
        """
        return self != other and self <= other

    def __ge__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> ab.full >= s00 | s01 | s10 | s11
        True
        >>> ab.full >= s00 | s01 | s10
        True
        >>> s00 | s01 | s10 >= s01 | s10 | s11
        False
        """
        return (self | other) == self

    def __gt__(self, sdd other):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> s10 = ab(a=xy(x=1), b=uv(u=0))
        >>> s11 = ab(a=xy(x=1), b=uv(u=1))
        >>> ab.full > s00 | s01 | s10 | s11
        False
        >>> ab.full > s00 | s01 | s10
        True
        >>> s00 | s01 | s10 > s01 | s10 | s11
        False
        """
        return self != other and self >= other

    def __len__(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> len(s00)
        4
        >>> len(s00 | s01)
        8
        >>> len(s00 & s01)
        0
        >>> len(ab.empty)
        0
        >>> len(ab.one)
        1
        >>> len(ab.full)
        16
        """
        return int(self.s.nbStates())

    def __bool__(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s00 = ab(a=xy(x=0), b=uv(u=0))
        >>> s01 = ab(a=xy(x=0), b=uv(u=1))
        >>> bool(s00)
        True
        >>> bool(s00 | s01)
        True
        >>> bool(s00 & s01)
        False
        >>> bool(ab.empty)
        False
        >>> bool(ab.one)
        True
        """
        return self.s.nbStates() > 0

    def __hash__(self):
        return int(self.s.set_hash())

    cdef SDD _pick(self, SDD s):
        cdef sdd_iterator it
        cdef SDD* SDD_ptr
        cdef DDD* DDD_ptr
        cdef sdd sdd_val
        cdef ddd ddd_val
        cdef sdomain sdd_dom
        cdef domain ddd_dom
        if sdd_is_STOP(s):
            return s
        it = sdd_iterator_begin(s)
        if sdd_iterator_end(it, s):
            return sdd_new_EMPTY()
        if sdd_iterator_value_is_DDD(it):
            DDD_ptr = sdd_iterator_DDD_value(it)
            ddd_dom = self.f.ddoms[s.variable()]
            ddd_val = ddd_dom.makeddd(DDD_ptr[0]).pick()
            return sdd_new_SDDd(s.variable(),
                                ddd_val.d,
                                self._pick(sdd_iterator_sdd(it)))
        else:
            if sdd_iterator_value_is_SDD(it):
                SDD_ptr = sdd_iterator_SDD_value(it)
            elif sdd_iterator_GSDD_value(it):
                SDD_ptr = sdd_iterator_GSDD_value(it)
            else:
                raise RuntimeError("unknown DD type")
            sdd_dom = self.f.ddoms[s.variable()]
            sdd_val = sdd_dom.makesdd(SDD_ptr[0]).pick()
            return sdd_new_SDDs(s.variable(),
                                sdd_val.s,
                                self._pick(sdd_iterator_sdd(it)))

    def pick(self, as_dict=False):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> p = ab.full.pick()
        >>> p <= ab.full
        True
        >>> len(p)
        1
        """
        cdef sdd p = self.f.makesdd(self._pick(self.s))
        cdef dict d
        if as_dict:
            for d in p.values():
                return d
        else:
            return p

    def __iter__(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> # ab.full  =>  (a)---xy.full-->(b)---uv.full-->[ONE]
        >>> for i, e in enumerate(sorted(ab.full)):
        ...     assert i == 0
        ...     assert e.var == "a"
        ...     assert e.val == xy.full
        ...     for j, f in enumerate(sorted(e.succ)):
        ...         assert j == 0
        ...         assert f.var == "b"
        ...         assert f.val == uv.full
        ...         assert f.succ == ab.one
        """
        cdef sdd_iterator it
        cdef SDD* SDD_ptr
        cdef DDD* DDD_ptr
        cdef object dom
        cdef domain ddd_dom
        cdef sdomain sdd_dom
        if not self.stop:
            dom = self.f.ddoms[self.head]
            if isinstance(dom, domain):
                ddd_dom = <domain>dom
            else:
                sdd_dom = <sdomain>dom
            it = sdd_iterator_begin(self.s)
            while not sdd_iterator_end(it, self.s):
                if sdd_iterator_value_is_DDD(it):
                    DDD_ptr = sdd_iterator_DDD_value(it)
                    yield sedge(self.head,
                                ddd_dom.makeddd(DDD_ptr[0]),
                                self.f.makesdd(sdd_iterator_sdd(it)))
                else:
                    if sdd_iterator_value_is_SDD(it):
                        SDD_ptr = sdd_iterator_SDD_value(it)
                    elif sdd_iterator_value_is_GSDD(it):
                        SDD_ptr = sdd_iterator_GSDD_value(it)
                    else:
                        raise RuntimeError("unknown DD type")
                    yield sedge(self.head,
                                sdd_dom.makesdd(SDD_ptr[0]),
                                self.f.makesdd(sdd_iterator_sdd(it)))
                sdd_iterator_next(it)

    def values(self):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> values = list(ab.full.values())
        >>> len(values)
        16
        >>> for a in ({'x': x, 'y': y} for x in [0, 1] for y in [0, 1]):
        ...     for b in ({'u': u, 'v': v} for u in [0, 1] for v in [0, 1]):
        ...         assert {'a': a, 'b': b} in values
        """
        cdef sedge e
        cdef dict s
        if self.stop:
            yield {}
        else:
            for e in self:
                for s in e.succ.values():
                    for v in e.val.values():
                        yield {e.var: v} | s

    def domains(self, dict doms=None):
        """
        >>> xy = domain(x=2, y=2)
        >>> uv = domain(u=2, v=2)
        >>> ab = sdomain(a=xy, b=uv)
        >>> s = ab(a=xy(x=0), b=uv(u=1))
        >>> s.domains() == {'a': {'x': {0}, 'y': {0, 1}}, 'b': {'u': {1}, 'v': {0, 1}}}
        True
        """
        cdef sedge e
        if doms is None:
            doms = {}
        for e in self:
            doms[e.var] = e.val.domains()
            e.succ.domains(doms)
        return doms

    def _dot(self, out, nid, node, parent=None):
        nid[node] = len(nid)
        if node.stop:
            out.write(f'    "n{nid[node]}" [shape=square, label="1"];\n')
        elif parent is None:
            out.write(f'    "n{nid[node]}" [label="{node.head}"];\n')
        else:
            out.write(f'    "n{nid[node]}" [label="{node.head}@{parent}"];\n')
        for e in node:
            if None in nid and e.val in nid[None]:
                lbl = nid[None][e.val]
            else:
                nid.setdefault(None, {})
                lbl = nid[None][e.val] = len(nid[None])
                e.val._dot(out, nid, e.val, lbl) 
            if e.succ not in nid:
                self._dot(out, nid, e.succ)
            out.write(f'    n{nid[node]} -> n{nid[e.succ]} [label="@{lbl}"];\n')

    def dot(self, path):
        path = Path(path)
        path_dot = path.with_suffix(".dot")
        with path_dot.open("w") as out:
            out.write("digraph sdd {\n")
            self._dot(out, defaultdict(), self)
            out.write("}\n")
        if (fmt := path.suffix.lower().lstrip(".")) != "dot":
            check_call(["dot", f"-T{fmt}", "-o", path, path_dot])


##
## shom
##


cdef class shom:
    def __init__(self):
        raise TypeError("class 'shom' should not be instantiated directly")

    def __call__(self, sdd s):
        return self.f.makesdd(shom_call(self.h, s.s))
