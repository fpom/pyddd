from libcpp.pair cimport pair
from libcpp.vector cimport vector
from libcpp.string cimport string

import collections, itertools

edge = collections.namedtuple("edge", ["varname", "varnum", "value", "child"])

cdef dict VARS = {}
cdef dict SRAV = {}

cdef class xdd :
    pass

##
## DDD
##

cdef extern from "ddd/DDD.h" :
    cdef cppclass DDD :
        @staticmethod
        void varName (int var, const string &name)
        @staticmethod
        const string getvarName (int var)
        DDD (const DDD &)
        DDD (int var, short val, const DDD &d)
        bint empty () const
        bint set_equal (const DDD &b) const
        long double set_size () const
        int variable() const
        size_t hash () const

cdef extern from "dddwrap.h" :
    cdef const DDD ddd_ONE
    cdef DDD *ddd_new_ONE()
    cdef DDD *ddd_new_EMPTY()
    cdef DDD *ddd_new_TOP()
    cdef bint ddd_STOP(DDD &d)
    cdef DDD *ddd_concat (DDD &a, DDD &b)
    cdef DDD *ddd_union (DDD &a, DDD &b)
    cdef DDD *ddd_intersect (DDD &a, DDD &b)
    cdef DDD *ddd_minus (DDD &a, DDD &b)
    ctypedef pair[short,DDD] *ddd_iterator
    cdef ddd_iterator ddd_iterator_begin (DDD *d)
    cdef void ddd_iterator_next (ddd_iterator i)
    cdef bint ddd_iterator_end (ddd_iterator i, DDD *d)
    cdef DDD *ddd_iterator_ddd (ddd_iterator i)
    cdef short ddd_iterator_value (ddd_iterator i)

cdef ddd makeddd (DDD *d) :
    cdef ddd obj = ddd.__new__(ddd)
    obj.d = d
    return obj

cdef class ddd (xdd) :
    cdef DDD *d
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
        cdef short val
        cdef str var
        self.d = ddd_new_ONE()
        for var in sorted(valuation) :
            if var not in VARS :
                pos = VARS[var] = len(VARS)
                SRAV[pos] = var
                DDD.varName(VARS[var], var.encode())
        for pos, val in sorted(((VARS[var], val) for var, val in valuation.items()),
                               reverse=True) :
            self.d = new DDD(pos, val, self.d[0])
    def __add__ (ddd self, ddd other) :
        """Concatenation: `a+b` replaces "one" terminals of `a` by `b`.

        >>> d = ddd(a=1) + ddd(b=2)
        >>> list(d)
        [(1, 2)]

        Note that variables are *not* reordered upon concatenation, so that:

        >>> ddd(a=1) + ddd(b=2) != ddd(b=2) + ddd(a=1)
        True
        """
        return makeddd(ddd_concat(self.d[0], other.d[0]))
    def __or__ (ddd self, ddd other) :
        """Union: `a|b` contains all the elements contained in `a` or `b`.

        >>> d = ddd(a=1, b=2) | ddd(a=3, b=4)
        >>> list(sorted(d))
        [(1, 2), (3, 4)]
        """
        return makeddd(ddd_union(self.d[0], other.d[0]))
    def __and__ (ddd self, ddd other) :
        """Intersection: `a&b` contains all the elements contained in both `a` and `b`.

        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) & ddd(a=1, b=2)
        >>> list(d)
        [(1, 2)]
        >>> d = (ddd(a=1, b=2) | ddd(a=1, b=3)) & ddd(a=4, b=5)
        >>> list(d)
        []
        """
        return makeddd(ddd_intersect(self.d[0], other.d[0]))
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
        return makeddd(ddd_minus(self.d[0], other.d[0]))
    def __eq__ (ddd self, ddd other) :
        return self.d.set_equal(other.d[0])
    def __ne__ (ddd self, ddd other) :
        return not self.d.set_equal(other.d[0])
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
        return not self.d.empty()
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
        if ddd_STOP(self.d[0]) :
            return self
        else :
            it = ddd_iterator_begin(self.d)
            child = makeddd(ddd_iterator_ddd(it))
            return makeddd(new DDD(self.d.variable(), ddd_iterator_value(it),
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
        cdef short val
        cdef tuple vec
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        while not ddd_iterator_end(it, self.d) :
            val = ddd_iterator_value(it)
            child = makeddd(ddd_iterator_ddd(it))
            if ddd_STOP(child.d[0]) :
                yield (val,)
            else :
                for vec in child :
                    yield (val,) + vec
            ddd_iterator_next(it)
    cpdef tuple vars (ddd self) :
        """Return the `tuple` of variables names on the `ddd`.

        >>> ddd(a=1, b=2, c=3).vars()
        ('a', 'b', 'c')
        """
        cdef ddd child
        cdef ddd_iterator it
        if ddd_STOP(self.d[0]) :
            return ()
        else :
            it = ddd_iterator_begin(self.d)
            child = makeddd(ddd_iterator_ddd(it))
            return (self.varname(),) + child.vars()
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
        if not ddd_STOP(self.d[0]) :
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
        return ddd_STOP(self.d[0])

##
## SDD
##

cdef extern from "ddd/SDD.h" :
    cdef cppclass SDD :
        SDD (const SDD &)
        long double nbStates() const
        bint empty() const
        size_t set_hash() const
        int variable() const

cdef extern from "dddwrap.h" :
    cdef SDD *sdd_new_SDDs (int var, const SDD &val, const SDD &s)
    cdef SDD *sdd_new_SDDd (int var, const DDD &val, const SDD &s)
    cdef const SDD sdd_ONE
    cdef SDD *sdd_new_ONE()
    cdef SDD *sdd_new_EMPTY()
    cdef SDD *sdd_new_TOP()
    cdef bint sdd_STOP(SDD &s)
    cdef SDD *sdd_concat(SDD &a, SDD &b)
    cdef SDD *sdd_union(SDD &a, SDD &b)
    cdef SDD *sdd_intersect(SDD &a, SDD &b)
    cdef SDD *sdd_minus(SDD &a, SDD &b)
    cdef bint sdd_eq(SDD &a, SDD &b)
    cdef bint sdd_ne(SDD &a, SDD &b)
    ctypedef DDD* DDD_star
    ctypedef vector[pair[DDD_star,SDD]] sdd_iterator
    cdef sdd_iterator sdd_iterator_begin (SDD *s)
    cdef void sdd_iterator_next (sdd_iterator i)
    cdef bint sdd_iterator_end (sdd_iterator i, SDD *s)
    cdef SDD *sdd_iterator_sdd (sdd_iterator i)
    cdef bint sdd_iterator_value_is_DDD (sdd_iterator i)
    cdef bint sdd_iterator_value_is_SDD (sdd_iterator i)
    cdef bint sdd_iterator_value_is_GSDD (sdd_iterator i)
    cdef SDD *sdd_iterator_SDD_value (sdd_iterator i)
    cdef SDD *sdd_iterator_GSDD_value (sdd_iterator i)
    cdef DDD *sdd_iterator_DDD_value (sdd_iterator i)

cdef sdd makesdd (SDD *s) :
    cdef sdd obj = sdd.__new__(sdd)
    obj.s = s
    return obj

cdef xdd sdd_iterator_value (sdd_iterator i) :
    if sdd_iterator_value_is_DDD(i) :
        return makeddd(sdd_iterator_DDD_value(i))
    elif sdd_iterator_value_is_SDD(i) :
        return makesdd(sdd_iterator_SDD_value(i))
    elif sdd_iterator_value_is_GSDD(i) :
        return makesdd(sdd_iterator_GSDD_value(i))
    else :
        raise NotImplementedError("cannot cast arc label")

cdef class sdd (xdd) :
    cdef SDD *s
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
            if var not in VARS :
                pos = VARS[var] = len(VARS)
                SRAV[pos] = var
        for pos, val in sorted(((VARS[var], val) for var, val in valuation.items()),
                               reverse=True) :
            if isinstance(val, ddd) :
                self.s = sdd_new_SDDd(pos, (<ddd>val).d[0], self.s[0])
            else :
                self.s = sdd_new_SDDs(pos, (<sdd>val).s[0], self.s[0])
    def __add__ (sdd self, sdd other) :
        """Concatenation: `a+b` replaces "one" terminals of `a` by `b`.

        >>> s = sdd(a=ddd(x=1), b=ddd(y=2)) + sdd(c=sdd(i=ddd(u=1, v=2)))
        >>> s == sdd(a=ddd(x=1), b=ddd(y=2), c=sdd(i=ddd(u=1, v=2)))
        True

        Note that variables are *not* reordered upon concatenation, so that:

        >>> sdd(a=ddd(x=1)) + sdd(b=ddd(y=2)) != sdd(b=ddd(y=2)) + sdd(a=ddd(x=1))
        True
        """
        return makesdd(sdd_concat(self.s[0], other.s[0]))
    def __or__ (sdd self, sdd other) :
        """Union: `a|b` contains all the elements contained in `a` or `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2)) | sdd(a=ddd(x=3), b=ddd(y=4))
        >>> list(sorted(d.nest()))
        [((1,), (2,)),
         ((3,), (4,))]
        """
        return makesdd(sdd_union(self.s[0], other.s[0]))
    def __and__ (sdd self, sdd other) :
        """Intersection: `a&b` contains all the elements contained in both `a` and `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2))
        >>> e = sdd(a=ddd(x=3), b=ddd(y=4))
        >>> (d | e) & e == e
        True
        """
        return makesdd(sdd_intersect(self.s[0], other.s[0]))
    def __sub__ (sdd self, sdd other) :
        """Difference: `a-b` contains the elements from `a` that are not in `b`.

        >>> d = sdd(a=ddd(x=1), b=ddd(y=2))
        >>> e = sdd(a=ddd(x=3), b=ddd(y=4))
        >>> (d | e) - e == d
        True
        """
        return makesdd(sdd_minus(self.s[0], other.s[0]))
    def __eq__ (sdd self, sdd other) :
        return sdd_eq(self.s[0], other.s[0])
    def __ne__ (sdd self, sdd other) :
        return sdd_ne(self.s[0], other.s[0])
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
        return not self.s.empty()
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
        return SRAV[self.s.variable()]
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
        if sdd_STOP(self.s[0]) :
            return self
        else :
            it = sdd_iterator_begin(self.s)
            child = makesdd(sdd_iterator_sdd(it))
            val = sdd_iterator_value(it)
            if isinstance(val, ddd) :
                return makesdd(sdd_new_SDDd(self.s.variable(), (<ddd>val).d[0],
                                            sdd_ONE)) + child.pick()
            else :
                return makesdd(sdd_new_SDDs(self.s.variable(), (<sdd>val).s[0],
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
            if sdd_STOP(child.s[0]) :
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
        if sdd_STOP(self.s[0]) :
            return ()
        else :
            it = sdd_iterator_begin(self.s)
            child = makesdd(sdd_iterator_sdd(it))
            return (self.varname(),) + child.vars()
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
        if not sdd_STOP(self.s[0]) :
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
        return sdd_STOP(self.s[0])
