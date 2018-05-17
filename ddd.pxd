from libcpp.string cimport string

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
        void pstats (bint reinit)

cdef class ddd (xdd) :
    cdef DDD *d
    cpdef str varname (ddd self)
    cpdef ddd pick (ddd self)
    cpdef dict dict_pick (ddd self)
    cpdef tuple vars (ddd self)
    cpdef bint stop (ddd self)
    cpdef void print_stats (self, bint reinit=*)

cdef ddd makeddd (DDD *d)

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
        void pstats (bint reinit)

cdef class sdd (xdd) :
    cdef SDD *s
    cpdef str varname (sdd self)
    cpdef sdd pick (sdd self)
    cpdef dict dict_pick (sdd self)
    cpdef tuple vars (sdd self)
    cpdef bint stop (sdd self)
    cpdef void print_stats (self, bint reinit=*)

cdef sdd makesdd (SDD *s)

##
## Shom
##

cdef extern from "ddd/SHom.h" :
    cdef cppclass Shom :
        Shom ()
        Shom (const SDD &s)
        Shom (const Shom &h)
        size_t hash() const

cdef class shom :
    cdef Shom *h
    cpdef shom fixpoint (shom self)
    cpdef shom star (shom self)
    cpdef shom invert (shom self, sdd potential)
    cpdef str dumps (shom self)

cdef shom makeshom (Shom *h)
