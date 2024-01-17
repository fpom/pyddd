from libcpp.string cimport string

cdef extern from "dddwrap.h":
    ctypedef short val_t

cdef extern from "ddd/DDD.h":
    cdef cppclass DDD:
        DDD()
        DDD(const DDD &)
        DDD(int var, val_t val, const DDD &d)
        DDD(int var, val_t val)
        DDD(int var, val_t min, val_t max, const DDD &d)
        bint empty() const
        bint set_equal(const DDD &b) const
        long double set_size() const
        int variable() const
        size_t hash() const
        void pstats(bint reinit)

cdef extern from "ddd/Hom.h":
    cdef cppclass Hom:
        Hom()
        Hom(const DDD &d)
        Hom(const Hom &h)
        Hom invert(const DDD &d)
        size_t hash() const
        bint is_selector()

cdef class _domain:
    pass

cdef class domain(_domain):
    cdef dict vmap, ddoms, sdoms
    cdef readonly tuple vars
    cdef readonly int depth
    cdef readonly ddd full, one, empty
    cdef readonly hom id
    cdef DDD _from_set(self, int var, set dom, DDD tail)
    cdef inline ddd makeddd(self, DDD d)
    cdef inline hom makehom(self, Hom h)
    cdef inline void checkd(self, ddd d)
    cdef inline void checkh(self, hom h)
    cdef ddd _call_ddd(self, dict values)
    cdef hom _call_hom(self, str op)
    cpdef hom const(self, ddd d)
    cpdef hom op(self, str left, str op, object right)
    cdef Hom _hom_ass(self, int tgt, int src)
    cdef Hom _hom_inc(self, int tgt, int src)

cdef class _dd:
    pass

cdef class ddd(_dd):
    cdef domain f
    cdef DDD d
    cdef DDD _pick(self, DDD d)

cdef class _edge:
    pass

cdef class edge(_edge):
    cdef public str var
    cdef public val_t val
    cdef public ddd succ
    cdef inline tuple tuple(self)
    cdef inline void check(self, edge other)

cdef class _hom:
    pass

cdef class hom(_hom):
    cdef domain f
    cdef Hom h
    cpdef hom ite(self, hom then, hom orelse=*)
    cpdef hom fixpoint(self)
    cpdef hom lfp(self)
    cpdef hom gfp(self)
    cpdef hom invert(self, ddd potential=*)
    cpdef bint is_selector(self)
    cpdef hom clip(self)

cdef class sdomain(_domain):
    cdef dict vmap, ddoms
    cdef readonly tuple vars
    cdef readonly int depth
    cdef readonly sdd full, one, empty
    cdef readonly shom id
    cdef inline void checks(self, sdd s)
    cdef inline void checkh(self, shom h)
    cdef inline sdd makesdd(self, SDD s)
    cdef inline shom makeshom(self, Shom h)

cdef extern from "ddd/SDD.h":
    cdef cppclass SDD:
        SDD()
        SDD(const SDD &)
        SDD(int var, DDD val, const SDD)
        SDD(int var, SDD val, const SDD)
        long double nbStates() const
        bint empty() const
        size_t set_hash() const
        int variable() const

cdef class sdd(_dd):
    cdef sdomain f
    cdef SDD s

cdef extern from "ddd/SHom.h":
    cdef cppclass Shom:
        Shom()
        Shom(const SDD &s)
        Shom(const Shom &h)
        Shom fixpoint()
        size_t hash() const

cdef class shom(_hom):
    cdef sdomain f
    cdef Shom h
