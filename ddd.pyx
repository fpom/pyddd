from libcpp.pair cimport pair
from libcpp.string cimport string

import collections

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
    cdef ddd_iterator ddd_iterator_end (DDD *d)
    cdef DDD *ddd_iterator_ddd (ddd_iterator i)
    cdef short ddd_iterator_value (ddd_iterator i)

cdef ddd makeddd (DDD *d) :
    cdef ddd obj = ddd.__new__(ddd)
    obj.d = d
    return obj

edge = collections.namedtuple("edge", ["varname", "varnum", "value", "child"])

cdef dict VARS = {}

cdef class ddd :
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
                VARS[var] = len(VARS)
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
        {'a': 1, 'b': ...}
        """
        return dict(zip(self.vars(), next(iter(self.pick()))))
    def __iter__ (ddd self) :
        """Yield all the elements is the `ddd`, as `tuple`s ordered like the
        variables (as returned by method `vars`).

        >>> list(ddd(a=1, b=2, c=3))
        [(1, 2, 3)]
        """
        cdef short val
        cdef tuple vec
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        while it != ddd_iterator_end(self.d) :
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
        """Yield all the elements is the `ddd`, as `dict`s.

        >>> list(ddd(a=1, b=2, c=3).items())
        [{'a': 1, 'b': 2, 'c': 3}]
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
        """
        cdef str var
        cdef ddd child
        cdef ddd_iterator it = ddd_iterator_begin(self.d)
        if not ddd_STOP(self.d[0]) :
            while it != ddd_iterator_end(self.d) :
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
