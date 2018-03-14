cdef extern from "ddd/DDD.h" :
    cdef cppclass DDD

cdef extern from "ddd/SDD.h" :
    cdef cppclass SDD

cdef class xdd :
    pass

cdef class ddd (xdd) :
    cdef DDD *d
    cpdef str varname (ddd self)
    cpdef ddd pick (ddd self)
    cpdef dict dict_pick (ddd self)
    cpdef tuple vars (ddd self)
    cpdef bint stop (ddd self)

cdef class sdd (xdd) :
    cdef SDD *s
    cpdef str varname (sdd self)
    cpdef sdd pick (sdd self)
    cpdef dict dict_pick (sdd self)
    cpdef tuple vars (sdd self)
    cpdef bint stop (sdd self)

cdef ddd makeddd (DDD *d)
cdef sdd makesdd (SDD *s)

