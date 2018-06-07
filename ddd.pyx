from libcpp.pair cimport pair
from libcpp.vector cimport vector
from libcpp.set cimport set as cset
from libcpp cimport bool

import collections, itertools, functools, operator, os.path, os, subprocess, ast

edge = collections.namedtuple("edge", ["varname", "varnum", "value", "child"])

cdef dict VARS = {}
cdef dict SRAV = {}

cdef int _varpos (str var, bint dddvar) :
    cdef int pos
    if var in VARS :
        pos = VARS[var]
    else :
        pos = VARS[var] = len(VARS)
        SRAV[pos] = var
        if dddvar :
            DDD.varName(pos, var.encode())
    return pos

cdef class xdd :
    cdef void _dot (self, str ext, list files) :
        cdef str base
        if ext in ["", "dot"] :
            pass
        elif ext in ["pdf", "eps", "png"] :
            for base in files :
                if os.path.exists(base + ".dot") :
                    subprocess.check_call(["dot", "-T%s" % ext,
                                           "-o", ".".join([base, ext]),
                                           base + ".dot"])
                    os.unlink(base + ".dot")
        else :
            for base in files :
                if os.path.exists(base + ".dot") :
                    subprocess.check_call(["dot2tex", "--figonly",
                                           "-o", base + ".tex",
                                           base + ".dot"])
                    os.unlink(base + ".dot")

##
## DDD
##

cdef extern from "dddwrap.h" namespace "std" :
    cdef cppclass ostringstream :
        string str()

cdef extern from "dddwrap.h" :
    ctypedef short val_t
    cdef const DDD ddd_ONE
    cdef DDD ddd_new_ONE()
    cdef DDD ddd_new_EMPTY()
    cdef DDD ddd_new_TOP()
    cdef DDD ddd_new_range(int var, val_t val1, val_t val2, const DDD&d)
    cdef bint ddd_is_STOP(DDD &d)
    cdef bint ddd_is_ONE(DDD &d)
    cdef bint ddd_is_NULL(DDD &d)
    cdef bint ddd_is_TOP(DDD &d)
    cdef DDD ddd_concat (DDD &a, DDD &b)
    cdef DDD ddd_union (DDD &a, DDD &b)
    cdef DDD ddd_intersect (DDD &a, DDD &b)
    cdef DDD ddd_minus (DDD &a, DDD &b)
    ctypedef pair[val_t,DDD] *ddd_iterator
    cdef ddd_iterator ddd_iterator_begin (DDD d)
    cdef void ddd_iterator_next (ddd_iterator i)
    cdef bint ddd_iterator_end (ddd_iterator i, DDD d)
    cdef DDD ddd_iterator_ddd (ddd_iterator i)
    cdef val_t ddd_iterator_value (ddd_iterator i)
    cdef long ddd_val_size
    cdef void saveDDD (ofstream &s, vector[DDD] l)
    cdef void loadDDD (ifstream &s, vector[DDD] &l)
    cdef void ddd_print (DDD d, ostringstream &s)

cdef extern from "dddwrap.h" namespace "std" :
    cdef cppclass ofstream :
        ofstream ()
        ofstream (const string &filename)
        void close ()
        ofstream& write (const char* s, int n)
    cdef cppclass ifstream :
        ifstream ()
        ifstream (const string &filename)
        void close ()
        bool eof ()
    void getline (ifstream& i, string& s)

cdef ddd makeddd (DDD d) :
    cdef ddd obj = ddd.__new__(ddd)
    obj.d = d
    return obj

def ddd_save (str path, *ddds, **headers) :
    cdef ofstream f = ofstream(path.encode())
    cdef vector[DDD] vec
    cdef ddd d
    cdef int i
    cdef bytes line
    cdef dict varmap = {}
    cdef tuple h
    vec.resize(len(ddds))
    for i, d in enumerate(ddds) :
        vec[i] = d.d
        varmap.update(d.varmap())
    headers["Count"] = len(ddds)
    headers["Variables"] = varmap
    for h in sorted(headers.items()) :
        line = ("%s: %r\n" % h).encode()
        f.write(line, len(line))
    f.write(b"\n", 1)
    saveDDD(f, vec)
    f.close()

def ddd_load (str path) :
    cdef ifstream f = ifstream(path.encode())
    cdef set required = {"Count", "Variables"}
    cdef dict headers = {}
    cdef vector[DDD] vec
    cdef int pos, count = 0
    cdef dict varmap
    cdef str var, r
    cdef bytes line, h, s
    cdef string rawline
    cdef object obj
    cdef DDD d
    # read headers
    while True :
        getline(f, rawline)
        line = rawline.strip()
        if not line :
            break
        try :
            h, line = (s.strip() for s in line.split(b":", 1))
            obj = ast.literal_eval(line.strip().decode())
        except :
            raise ValueError("invalid header line: %r" % line.decode())
        if h == b"Count" :
            count = obj
            if "Count" in required :
                required.remove("Count")
            else :
                raise ValueError("duplicated header 'Count'")
        elif h == b"Variables" :
            varmap = obj
            if "Variables" in required :
                required.remove("Variables")
            else :
                raise ValueError("duplicated header 'Variables'")
        else :
            headers[h.decode()] = obj
    if required :
        raise ValueError("missing headers: %s" % ", ".join(repr(r) for r in required))
    # read DDDs
    vec.resize(count)
    for var, pos in varmap.items() :
        VARS[var] = pos
        SRAV[pos] = var
        DDD.varName(pos, var.encode())
    loadDDD(f, vec)
    # done
    f.close()
    return headers, [makeddd(d) for d in vec]

cpdef long valsize () :
    return ddd_val_size

cdef class ddd (xdd) :
    def __init__ (self, **valuation) :
        """Create a `ddd` storing the values provided in `valuation`.

        >>> d = ddd(a=1, b=2, c=3)
        >>> d.vars()
        ('a', 'b', 'c')
        >>> list(d)
        [(1, 2, 3)]

        Note that variables are ordered lexicographically, so that:

        >>> ddd(a=1, b=2) == ddd(b=2, a=1)
        True

        `ddd`s are equipped with all the usual comparisons: `==` and
        `!=` for equality, and `<`, `<=`, `>`, and `>=` for inclusion.
        """
        cdef int pos
        cdef val_t val
        cdef str var
        if valuation :
            self.d = ddd_new_ONE()
        else :
            self.d = ddd_new_EMPTY()
        for var in sorted(valuation) :
            _varpos(var, True)
        for pos, val in sorted(((VARS[var], val) for var, val in valuation.items()),
                               reverse=True) :
            self.d = DDD(pos, val, self.d)
    @classmethod
    def from_range (cls, str var, val_t start, val_t stop, ddd d=None) :
        cdef ddd suite
        if start > stop :
            raise ValueError("start should not be greater that stop")
        if d is None :
            suite = ddd.one()
        else :
            suite = d
        if var not in VARS :
            _varpos(var, True)
        return makeddd(ddd_new_range(VARS[var], start, stop, suite.d))
    @classmethod
    def from_values (cls, str var, values) :
        cdef list l
        cdef set s
        cdef dict d
        cdef tuple t
        cdef val_t v
        cdef ddd res = ddd.empty()
        if isinstance(values, list) :
            l = <list>values
            for v in l :
                res |= ddd(**{var: v})
        elif isinstance(values, set) :
            s = <set>values
            for v in s :
                res |= ddd(**{var: v})
        elif isinstance(values, dict) :
            d = <dict>values
            for v in d :
                res |= ddd(**{var: v})
        elif isinstance(values, tuple) :
            t = <tuple>values
            for v in t :
                res |= ddd(**{var: v})
        else :
            res = functools.reduce(operator.or_,
                                   (cls(**{var:v}) for v in values),
                                   res)
        return res
    cpdef void save (ddd self, str path) :
        ddd_save(path, self)
    @classmethod
    def load (cls, str path) :
        return ddd_load(path)[0][0]
    cpdef void print_stats (self, bint reinit=True) :
        self.d.pstats(reinit)
    cpdef void dot (ddd self, str path) :
        cdef sdd s = sdd(x=self)
        cdef str line, node
        cdef object src, tgt
        dirname = os.path.dirname(path)
        basename, ext = os.path.splitext(os.path.basename(path))
        ext = ext.lower() or ".dot"
        sddbase = os.path.join(dirname, basename)
        dddbase = os.path.join(dirname, "d3" + basename)
        s.dot(sddbase)
        with open(dddbase + ".dot") as src :
            with open(sddbase + ".dot", "w") as tgt :
                node = "Mod_0"
                for line in src :
                    if "[shape=invhouse]" in line :
                        node = line.split()[0]
                    elif node not in line :
                        tgt.write(line)
        os.unlink(dddbase + ".dot")
        self._dot(ext.strip("."), [sddbase])
    def __add__ (ddd self, ddd other) :
        """Concatenation: `a+b` replaces "one" terminals of `a` by `b`.

        >>> d = ddd(a=1) + ddd(b=2)
        >>> list(d)
        [(1, 2)]

        Note that variables are *not* reordered upon concatenation, so that:

        >>> ddd(a=1) + ddd(b=2) != ddd(b=2) + ddd(a=1)
        True
        """
        return makeddd(ddd_concat(self.d, other.d))
    def __or__ (ddd self, ddd other) :
        """Union: `a|b` contains all the elements contained in `a` or `b`.

        >>> d = ddd(a=1, b=2) | ddd(a=3, b=4)
        >>> list(sorted(d))
        [(1, 2), (3, 4)]
        """
        return makeddd(ddd_union(self.d, other.d))
    def __and__ (ddd self, ddd other) :
        """Intersection: `a&b` contains all the elements contained in both `a` and `b`.

        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) & ddd(a=1, b=2)
        >>> list(d)
        [(1, 2)]
        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) & ddd(a=4, b=5)
        >>> list(d)
        []
        """
        return makeddd(ddd_intersect(self.d, other.d))
    def __sub__ (ddd self, ddd other) :
        """Difference: `a-b` contains the elements from `a` that are not in `b`.

        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) - ddd(a=1, b=2)
        >>> list(d)
        [(1, 3)]
        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) - ddd(a=4, b=5)
        >>> list(sorted(d))
        [(1, 2), (1, 3)]
        >>> d = ddd(a=1, b=2) - (ddd(a=1, b=2) | ddd(a=1, b=3))
        >>> list(d)
        []
        """
        return makeddd(ddd_minus(self.d, other.d))
    def __eq__ (ddd self, ddd other) :
        return self.d.set_equal(other.d)
    def __ne__ (ddd self, ddd other) :
        return not self.d.set_equal(other.d)
    def __le__ (ddd self, ddd other) :
        return (self | other) == other
    def __lt__ (ddd self, ddd other) :
        return self != other and self <= other
    def __ge__ (ddd self, ddd other) :
        return (self | other) == self
    def __gt__ (ddd self, ddd other) :
        return self != other and self >= other
    def __len__ (ddd self) :
        """Number of unique elements in the `ddd`.

        >>> len(ddd(a=1, b=2) | ddd(a=1, b=3))
        2
        >>> len(ddd(a=1, b=2) | ddd(a=1, b=3) | ddd(a=1, b=2))
        2
        """
        return int(self.d.set_size())
    def __bool__ (ddd self) :
        """Test for emptyness.

        >>> bool(ddd(a=1, b=2))
        True
        >>> bool(ddd(a=1, b=2) - ddd(a=1, b=2))
        False
        """
        return len(self) > 0
    def __hash__ (ddd self) :
        """Hash value: `ddd`s are immutable structures that can be used as
        `dict` keys or `set` elements.

        >>> d = ddd(a=1, b=2)
        >>> e = ddd(a=2, b=3)
        >>> all(k is v for k, v in {d: d, e: e}.items())
        True
        """
        return int(self.d.hash())
    cpdef str varname (ddd self) :
        """Name of the variable at the first layer of the `ddd`.

        >>> ddd(a=1, b=2).varname()
        'a'
        """
        return self.d.getvarName(self.d.variable()).decode()
    cpdef ddd pick (ddd self) :
        """Pick one element in the `ddd` and return it as a `ddd`.

        >>> d = ddd(a=1, b=2) | ddd(a=1, b=3)
        >>> list(d.pick())  # returns `1` for `a` and `2` or `3` for `b`
        [(1, ...)]
        """
        cdef ddd_iterator it
        if ddd_is_STOP(self.d) :
            return self
        else :
            it = ddd_iterator_begin(self.d)
            child = makeddd(ddd_iterator_ddd(it))
            return makeddd(DDD(self.d.variable(), ddd_iterator_value(it),
                               ddd_ONE)) + child.pick()
    cpdef dict dict_pick (ddd self) :
        """Pick one element in the `ddd` and return it as a `dict`.

        >>> d = ddd(a=1, b=2) | ddd(a=1, b=3)
        >>> d.dict_pick()  # returns `1` for `a` and `2` or `3` for `b`
        {...'a': 1...}
        """
        return dict(zip(self.vars(), next(iter(self.pick()))))
    def __iter__ (ddd self) :
        """Yield all the elements in the `ddd`, as `tuple`s ordered like the
        variables (as returned by method `vars`).

        >>> list(ddd(a=1, b=2, c=3))
        [(1, 2, 3)]
        """
        cdef val_t val
        cdef tuple vec
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        while not ddd_iterator_end(it, self.d) :
            val = ddd_iterator_value(it)
            child = makeddd(ddd_iterator_ddd(it))
            if ddd_is_STOP(child.d) :
                yield (val,)
            else :
                for vec in child :
                    yield (val,) + vec
            ddd_iterator_next(it)
    cpdef dict dom (ddd self, dict d=None) :
        cdef dict ret = {} if d is None else d
        cdef str var = self.varname()
        cdef set val
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        if var in ret :
            val = ret[var]
        else :
            val = ret[var] = set()
        while not ddd_iterator_end(it, self.d) :
            child = makeddd(ddd_iterator_ddd(it))
            val.add(ddd_iterator_value(it))
            if not ddd_is_STOP(child.d) :
                child.dom(ret)
            ddd_iterator_next(it)
        return ret
    cpdef tuple vars (ddd self) :
        """Return the `tuple` of variables names on the `ddd`.

        >>> ddd(a=1, b=2, c=3).vars()
        ('a', 'b', 'c')
        """
        cdef ddd child
        cdef ddd_iterator it
        if ddd_is_STOP(self.d) :
            return ()
        else :
            it = ddd_iterator_begin(self.d)
            child = makeddd(ddd_iterator_ddd(it))
            return (self.varname(),) + child.vars()
    cpdef dict varmap (ddd self) :
        """Return the `dict` of variables names on the `ddd` mapped to their numbers.

        >>> ddd(a=1, b=2, c=3).varmap() == {'a': 0, 'b': 1, 'c': 2}
        True
        """
        cdef ddd child
        cdef dict d
        cdef ddd_iterator it
        if ddd_is_STOP(self.d) :
            return {}
        else :
            it = ddd_iterator_begin(self.d)
            child = makeddd(ddd_iterator_ddd(it))
            d = child.varmap()
            d[self.varname()] = self.d.variable()
            return d
    def items (ddd self) :
        """Yield all the elements in the `ddd`, as `dict`s.

        >>> list(ddd(a=1, b=2, c=3).items())
        [{...'a': 1...}]
        """
        cdef tuple var = self.vars()
        cdef tuple val
        for val in self :
            yield dict(zip(var, val))
    def edges (ddd self) :
        """Iterate over the edges of the `ddd`, yielding `namedtuple`s with
        fields:
          - `varname`: name of the variable at this `ddd`
          - `varnum`: number of the variable (used internally)
          - `value`: value on the edge
          - `child`: `ddd` at the end of the edge

        >>> d = ddd(a=1, b=2) | ddd(a=2, b=3)
        >>> list(sorted(d.edges()))
        [edge(varname='a', varnum=0, value=1, child=<ddd.ddd ...>),
         edge(varname='a', varnum=0, value=2, child=<ddd.ddd ...>)]
        """
        cdef str var
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        if not ddd_is_STOP(self.d) :
            while not ddd_iterator_end(it, self.d) :
                val = ddd_iterator_value(it)
                child = makeddd(ddd_iterator_ddd(it))
                yield edge(self.varname(), self.d.variable(), val, child)
                ddd_iterator_next(it)
    @classmethod
    def one (cls) :
        """Return the accepting terminal. This is the basic leaf for accepted
        sequences.
        """
        return makeddd(ddd_new_ONE())
    @classmethod
    def empty (cls) :
        """Return non-accepting terminal. As DDD are a zero-suppressed variant
        of decision diagrams, paths leading to null are suppressed.
        Only the empty set is represented by null.
        """
        return makeddd(ddd_new_EMPTY())
    @classmethod
    def top (cls) :
        """The approximation terminal. This represents *any* finite set of
        assignment sequences. In a "normal" usage pattern, top
        terminals should not be produced.
        """
        return makeddd(ddd_new_TOP())
    cpdef bint stop (ddd self) :
        """Test whether the `ddd` is a dead-end, i.e., it is `one` or `empty`.

        >>> ddd().stop()
        True
        >>> ddd() == ddd.one()
        True
        >>> ddd(a=1).stop()
        False
        >>> ddd.one().stop()
        True
        >>> ddd.empty().stop()
        True
        """
        return ddd_is_STOP(self.d)
    cpdef ddd drop (ddd self, variables) :
        return self._drop(set(variables))
    cdef ddd _drop (ddd self, set variables) :
        cdef str var
        cdef int num
        cdef bint cut
        cdef ddd ret, tail
        cdef ddd_iterator it
        if ddd_is_STOP(self.d) :
            return self
        var = self.varname()
        num = self.d.variable()
        cut = var in variables
        ret = self.empty()
        it = ddd_iterator_begin(self.d)
        while not ddd_iterator_end(it, self.d) :
            if cut :
                ret |= makeddd(ddd_iterator_ddd(it))._drop(variables)
            else :
                tail = makeddd(ddd_iterator_ddd(it))._drop(variables)
                ret |= makeddd(DDD(num, ddd_iterator_value(it), tail.d))
            ddd_iterator_next(it)
        return ret
    cpdef str dumps (ddd self) :
        cdef ostringstream oss
        ddd_print(self.d, oss)
        return oss.str().decode()

##
## SDD
##

cdef extern from "dddwrap.h" :
    cdef SDD sdd_new_SDDs (int var, const SDD &val, const SDD &s)
    cdef SDD sdd_new_SDDd (int var, const DDD &val, const SDD &s)
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
    ctypedef DDD* DDD_star
    ctypedef vector[pair[DDD_star,SDD]] sdd_iterator
    cdef sdd_iterator sdd_iterator_begin (SDD s)
    cdef void sdd_iterator_next (sdd_iterator i)
    cdef bint sdd_iterator_end (sdd_iterator i, SDD s)
    cdef SDD sdd_iterator_sdd (sdd_iterator i)
    cdef bint sdd_iterator_value_is_DDD (sdd_iterator i)
    cdef bint sdd_iterator_value_is_SDD (sdd_iterator i)
    cdef bint sdd_iterator_value_is_GSDD (sdd_iterator i)
    cdef SDD *sdd_iterator_SDD_value (sdd_iterator i)
    cdef SDD *sdd_iterator_GSDD_value (sdd_iterator i)
    cdef DDD *sdd_iterator_DDD_value (sdd_iterator i)
    cdef int exportDot(const SDD &s, const string &path)
    cdef void sdd_print (SDD d, ostringstream &s)

cdef sdd makesdd (SDD s) :
    cdef sdd obj = sdd.__new__(sdd)
    obj.s = s
    return obj

cdef xdd sdd_iterator_value (sdd_iterator i) :
    cdef DDD* d
    cdef SDD* s
    if sdd_iterator_value_is_DDD(i) :
        d = sdd_iterator_DDD_value(i)
        return makeddd(d[0])
    elif sdd_iterator_value_is_SDD(i) :
        s = sdd_iterator_SDD_value(i)
        return makesdd(s[0])
    elif sdd_iterator_value_is_GSDD(i) :
        s = sdd_iterator_GSDD_value(i)
        return makesdd(s[0])
    else :
        raise NotImplementedError("cannot cast arc label")

cdef class sdd (xdd) :
    def __init__ (self, **valuation) :
        """Create a `sdd` storing the values provided in `valuation`.

        >>> s = sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        >>> s.vars()
        ('a', 'b', 'c')
        >>> list(s.nest())
        [((1, 2), (3,), ((4, 5),))]

        Note that variables are ordered lexicographically, so that:

        >>> sdd(a=ddd(x=1), b=ddd(y=2)) == sdd(b=ddd(y=2), a=ddd(x=1))
        True

        `sdd`s are equipped with all the usual comparisons: `==` and
        `!=` for equality, and `<`, `<=`, `>`, and `>=` for inclusion.
        """
        cdef int pos
        cdef xdd val
        cdef str var
        self.s = sdd_new_ONE()
        for var in sorted(valuation) :
            _varpos(var, False)
        for pos, val in sorted(((VARS[var], val) for var, val in valuation.items()),
                               reverse=True) :
            if isinstance(val, ddd) :
                self.s = sdd_new_SDDd(pos, (<ddd>val).d, self.s)
            else :
                self.s = sdd_new_SDDs(pos, (<sdd>val).s, self.s)
    cpdef void print_stats (self, bint reinit=True) :
        self.s.pstats(reinit)
    cpdef void dot (sdd self, str path) :
        dirname = os.path.dirname(path)
        basename, ext = os.path.splitext(os.path.basename(path))
        ext = ext.strip(".").lower()
        if ext not in ["", "dot", "pdf", "eps", "png", "tex"] :
            raise ValueError("unsupported output format %r" % ext)
        sddbase = os.path.join(dirname, basename)
        dddbase = os.path.join(dirname, "d3" + basename)
        exportDot(self.s, sddbase.encode("utf-8"))
        self._dot(ext, [sddbase, dddbase])
    def __add__ (sdd self, sdd other) :
        """Concatenation: `a+b` replaces "one" terminals of `a` by `b`.

        >>> s = sdd(a=ddd(x=1), b=ddd(y=2)) + sdd(c=sdd(i=ddd(u=1, v=2)))
        >>> s == sdd(a=ddd(x=1), b=ddd(y=2), c=sdd(i=ddd(u=1, v=2)))
        True

        Note that variables are *not* reordered upon concatenation, so that:

        >>> sdd(a=ddd(x=1)) + sdd(b=ddd(y=2)) != sdd(b=ddd(y=2)) + sdd(a=ddd(x=1))
        True
        """
        return makesdd(sdd_concat(self.s, other.s))
    def __or__ (sdd self, sdd other) :
        """Union: `a|b` contains all the elements contained in `a` or `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2)) | sdd(a=ddd(x=3), b=ddd(y=4))
        >>> list(sorted(d.nest()))
        [((1,), (2,)),
         ((3,), (4,))]
        """
        return makesdd(sdd_union(self.s, other.s))
    def __and__ (sdd self, sdd other) :
        """Intersection: `a&b` contains all the elements contained in both `a` and `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2))
        >>> e = sdd(a=ddd(x=3), b=ddd(y=4))
        >>> (d | e) & e == e
        True
        """
        return makesdd(sdd_intersect(self.s, other.s))
    def __sub__ (sdd self, sdd other) :
        """Difference: `a-b` contains the elements from `a` that are not in `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2))
        >>> e = sdd(a=ddd(x=3), b=ddd(y=4))
        >>> (d | e) - e == d
        True
        """
        return makesdd(sdd_minus(self.s, other.s))
    def __eq__ (sdd self, sdd other) :
        return sdd_eq(self.s, other.s)
    def __ne__ (sdd self, sdd other) :
        return sdd_ne(self.s, other.s)
    def __le__ (sdd self, sdd other) :
        return (self | other) == other
    def __lt__ (sdd self, sdd other) :
        return self != other and self <= other
    def __ge__ (sdd self, sdd other) :
        return (self | other) == self
    def __gt__ (sdd self, sdd other) :
        return self != other and self >= other
    def __len__ (sdd self) :
        """Number of unique elements in the `sdd`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2))
        >>> e = sdd(a=ddd(x=3), b=ddd(y=4))
        >>> len(d)
        1
        >>> len(d | e)
        2
        """
        return int(self.s.nbStates())
    def __bool__ (sdd self) :
        """Test for emptyness.

        >>> bool(sdd(a=ddd(x=1), b=ddd(y=2)))
        True
        >>> bool(sdd(a=ddd(x=1)) - sdd(a=ddd(x=1)))
        False
        """
        return len(self) > 0
    def __hash__ (sdd self) :
        """Hash value: `sdd`s are immutable structures that can be used as
        `dict` keys or `set` elements.

        >>> s = sdd(i=ddd(u=4, v=5))
        >>> t = sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=s)
        >>> all(k is v for k, v in {s: s, t: t}.items())
        True
        """
        return int(self.s.set_hash())
    cpdef str varname (sdd self) :
        """Name of the variable at the first layer of the `sdd`.

        >>> sdd(a=ddd(x=1), b=ddd(y=2)).varname()
        'a'
        """
        try :
            return SRAV[self.s.variable()]
        except KeyError :
            return "#%s" % self.s.variable()
    cpdef sdd pick (sdd self) :
        """Pick one element in the `sdd` and return it as a `sdd`.

        >>> s = (sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        ...      | sdd(a=ddd(x=2, y=3), b=ddd(z=3), c=sdd(i=ddd(u=1, v=2))))
        >>> len(s), len(s.pick())
        (2, 1)
        >>> set(s.pick().nest()).issubset(set(s.nest()))
        True
        """
        cdef sdd_iterator it
        cdef xdd val
        cdef ddd d
        cdef sdd s
        if sdd_is_STOP(self.s) :
            return self
        else :
            it = sdd_iterator_begin(self.s)
            child = makesdd(sdd_iterator_sdd(it))
            val = sdd_iterator_value(it)
            if isinstance(val, ddd) :
                d = (<ddd>val).pick()
                return makesdd(sdd_new_SDDd(self.s.variable(), d.d,
                                            sdd_ONE)) + child.pick()
            else :
                s = (<sdd>val).pick()
                return makesdd(sdd_new_SDDs(self.s.variable(), s.s,
                                            sdd_ONE)) + child.pick()
    cpdef dict dict_pick (sdd self) :
        """Pick one element in the `sdd` and return it as a `dict`.

        >>> s = (sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        ...      | sdd(a=ddd(x=2, y=3), b=ddd(z=3), c=sdd(i=ddd(u=1, v=2))))
        >>> s.dict_pick()
        {...'b': {'z': 3}...}
        """
        cdef xdd v
        return dict(zip(self.vars(), [v.dict_pick() for v in next(iter(self.pick()))]))
    def __iter__ (sdd self) :
        """Yield all the elements is the `sdd`, as `tuple`s ordered like the
        variables (as returned by method `vars`).

        >>> list(sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5))))
        [(<ddd.ddd ...>, <ddd.ddd ...>, <ddd.sdd ...>)]
        """
        cdef xdd val
        cdef tuple vec
        cdef sdd child
        cdef sdd_iterator it = sdd_iterator_begin(self.s)
        while not sdd_iterator_end(it, self.s) :
            child = makesdd(sdd_iterator_sdd(it))
            val = sdd_iterator_value(it)
            if sdd_is_STOP(child.s) :
                yield (val,)
            else :
                for vec in child :
                    yield (val,) + vec
            sdd_iterator_next(it)
    cpdef tuple vars (sdd self) :
        """Return the `tuple` of variables names on the `sdd`.

        >>> sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5))).vars()
        ('a', 'b', 'c')
        """
        cdef xdd child
        cdef sdd_iterator it
        if sdd_is_STOP(self.s) :
            return ()
        else :
            it = sdd_iterator_begin(self.s)
            child = makesdd(sdd_iterator_sdd(it))
            return (self.varname(),) + child.vars()
    cpdef dict varmap (sdd self) :
        cdef sdd child
        cdef dict d
        cdef sdd_iterator it
        if sdd_is_STOP(self.s) :
            return {}
        else :
            it = sdd_iterator_begin(self.s)
            child = makesdd(sdd_iterator_sdd(it))
            d = child.varmap()
            d[self.varname()] = self.s.variable()
            return d
    def items (sdd self) :
        """Yield all the elements in the `sdd`, as `dict`s.

        >>> s = sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        >>> i = [{'a': [{'y': 2, 'x': 1}],
        ...       'b': [{'z': 3}],
        ...       'c': [{'i': [{'v': 5, 'u': 4}]}]}]
        >>> list(s.items()) == i
        True
        """
        cdef tuple var = self.vars()
        cdef tuple val
        cdef xdd v
        for val in self :
            yield dict(zip(var, [list(v.items()) for v in val]))
    def nest (sdd self) :
        """Yield all the elements in the `sdd` as nested `tuple`s.

        >>> s = (sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        ...      | sdd(a=ddd(x=2, y=3), b=ddd(z=3), c=sdd(i=ddd(u=1, v=2))))
        >>> list(sorted(s.nest()))
        [((1, 2), (3,), ((4, 5),)),
         ((2, 3), (3,), ((1, 2),))]
        """
        cdef tuple val, t
        cdef xdd v
        cdef list l
        for val in self :
            l = []
            for v in val :
                if isinstance(v, sdd) :
                    l.append(v.nest())
                else :
                    l.append(iter(v))
            for t in itertools.product(*l) :
                yield t
    def edges (sdd self) :
        """Iterate over the edges of the `sdd`, yielding `namedtuple`s with
        fields:
          - `varname`: name of the variable at this `sdd`
          - `varnum`: number of the variable (used internally)
          - `value`: value on the edge (`ddd` or `sdd`)
          - `child`: `sdd` at the end of the edge

        >>> s = (sdd(a=ddd(x=1, y=2), b=ddd(z=3), c=sdd(i=ddd(u=4, v=5)))
        ...      | sdd(a=ddd(x=2, y=3), b=ddd(z=3), c=sdd(i=ddd(u=1, v=2))))
        >>> list(s.edges())
        [edge(varname='a', varnum=0, value=<ddd.ddd ...>, child=<ddd.sdd ...>),
         edge(varname='a', varnum=0, value=<ddd.ddd ...>, child=<ddd.sdd ...>)]
        """
        cdef str var
        cdef sdd child
        cdef xdd val
        cdef sdd_iterator it = sdd_iterator_begin(self.s)
        if not sdd_is_STOP(self.s) :
            while not sdd_iterator_end(it, self.s) :
                val = sdd_iterator_value(it)
                child = makesdd(sdd_iterator_sdd(it))
                yield edge(self.varname(), self.s.variable(), val, child)
                sdd_iterator_next(it)
    @classmethod
    def one (cls) :
        """Return the accepting terminal. This is the basic leaf for accepted
        sequences.
        """
        return makesdd(sdd_new_ONE())
    @classmethod
    def empty (cls) :
        """Return non-accepting terminal. As SDD are a zero-suppressed variant
        of decision diagrams, paths leading to null are suppressed.
        Only the empty set is represented by null.
        """
        return makesdd(sdd_new_EMPTY())
    @classmethod
    def top (cls) :
        """The approximation terminal. This represents *any* finite set of
        assignment sequences. In a "normal" usage pattern, top
        terminals should not be produced.
        """
        return makesdd(sdd_new_TOP())
    cpdef bint stop (sdd self) :
        """Test whether the `sdd` is a dead-end, i.e., it is `one` or `empty`.

        >>> sdd().stop()
        True
        >>> sdd() == sdd.one()
        True
        >>> sdd(a=ddd(x=1)).stop()
        False
        >>> sdd.one().stop()
        True
        >>> sdd.empty().stop()
        True
        """
        return sdd_is_STOP(self.s)
    cpdef sdd drop (sdd self, variables) :
        return self._drop(set(variables))
    cdef sdd _drop (sdd self, set variables) :
        cdef str var = self.varname()
        cdef xdd val
        cdef ddd d
        cdef sdd s, t
        cdef bint cut
        cdef sdd ret
        cdef sdd_iterator it
        if sdd_is_STOP(self.s) :
            return self
        cut = var in variables
        ret = self.empty()
        it = sdd_iterator_begin(self.s)
        while not sdd_iterator_end(it, self.s) :
            if cut :
                ret |= makesdd(sdd_iterator_sdd(it))._drop(variables)
            else :
                val = sdd_iterator_value(it)
                if isinstance(val, ddd) :
                    d = (<ddd>val).drop(variables)
                    t = makesdd(sdd_iterator_sdd(it))._drop(variables)
                    ret |= makesdd(sdd_new_SDDd(self.s.variable(), d.d, t.s))
                else :
                    s = (<sdd>val)._drop(variables)
                    t = makesdd(sdd_iterator_sdd(it))._drop(variables)
                    ret |= makesdd(sdd_new_SDDs(self.s.variable(), s.s, t.s))
            sdd_iterator_next(it)
        return ret
    cpdef str dumps (sdd self) :
        cdef ostringstream oss
        sdd_print(self.s, oss)
        return oss.str().decode()

##
## Shom
##

cdef extern from "dddwrap.h" :
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
    cdef Shom shom_intersect_Shom_Shom(const Shom &a, const Shom &b)
    cdef Shom shom_minus_Shom_SDD(const Shom &a, const SDD &b)
    cdef Shom shom_minus_Shom_Shom(const Shom &a, const Shom &b)
    cdef void shom_print(const Shom &h, ostringstream &s)
    cdef Shom shom_invert(const Shom &s, const SDD &d)
    cdef Shom shom_addset(const cset[Shom] &s)
    ctypedef cset[Shom] shom_set
    cdef Shom fixpoint(const Shom &s)

cdef shom makeshom (Shom h) :
    cdef shom obj = shom.__new__(shom)
    obj.h = h
    return obj

cdef class shom :
    def __init__ (shom self, sdd s=None) :
        if s is not None :
            self.h = Shom(s.s)
        else :
            self.h = Shom()
    @classmethod
    def mkmap (cls, str var, xdd val, shom s=None) :
        cdef shom suite
        if var not in VARS :
            pos = VARS[var] = len(VARS)
            SRAV[pos] = var
        if s is None :
            suite = cls.empty()
        else :
            suite = s
        if isinstance(val, ddd) :
            return makeshom(shom_new_Shom_var_ddd(VARS[var], (<ddd>val).d, suite.h))
        elif isinstance(val, sdd) :
            return makeshom(shom_new_Shom_var_sdd(VARS[var], (<sdd>val).s, suite.h))
        else :
            raise TypeError("expected ddd or sdd for val, but got %r"
                            % val.__class__.__name__)
    @classmethod
    def ident (cls) :
        return shom()
    @classmethod
    def empty (cls) :
        return makeshom(shom_new_Shom_null())
    def __neg__ (shom self) :
        return makeshom(shom_neg(self.h))
    def __eq__ (shom self, shom other) :
        return shom_eq(self.h, other.h)
    def __ne__ (shom self, shom other) :
        return shom_ne(self.h, other.h)
    def __call__ (shom self, sdd dom) :
        return makesdd(shom_call(self.h, dom.s))
    def __hash__ (shom self) :
        return int(self.s.hash())
    cpdef shom fixpoint (shom self) :
        return makeshom(fixpoint(self.h))
    cpdef shom lfp (shom self) :
        return (self | shom()).fixpoint()
    cpdef shom gfp (shom self) :
        return (self & shom()).fixpoint()
    cpdef shom invert (shom self, sdd potential) :
        return makeshom(shom_invert(self.h, potential.s)) & potential
    def __or__ (shom self, shom other) :
        return makeshom(shom_union(self.h, other.h))
    def __mul__ (shom self, shom other) :
        return makeshom(shom_circ(self.h, other.h))
    def __and__ (shom self, other) :
        if isinstance(other, sdd) :
            return makeshom(shom_intersect_Shom_SDD(self.h, (<sdd>other).s))
        elif isinstance(other, shom) :
            return makeshom(shom_intersect_Shom_Shom(self.h, (<shom>other).h))
        else :
            raise TypeError("expected 'shom' of 'sdd', got %r"
                            % other.__class__.__name__)
    def __rand__ (shom self, sdd other) :
        return self & other
    def __sub__ (shom self, other) :
        if isinstance(other, sdd) :
            return makeshom(shom_minus_Shom_SDD(self.h, (<sdd>other).s))
        elif isinstance(other, shom) :
            return makeshom(shom_minus_Shom_Shom(self.h, (<shom>other).h))
        else :
            raise TypeError("expected 'shom' of 'sdd', got %r"
                            % other.__class__.__name__)
    cpdef str dumps (shom self) :
        cdef ostringstream oss
        shom_print(self.h, oss)
        return oss.str().decode()
    @classmethod
    def union (cls, *shoms) :
        cdef shom h
        cdef shom_set s
        for h in shoms :
            s.insert(h.h)
        return makeshom(shom_addset(s))
