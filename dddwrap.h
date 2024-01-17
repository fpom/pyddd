#include <fstream>
#include <sstream>
#include "ddd/DDD.h"

#define val_t GDDD::val_t

#define ddd_new_ONE() DDD(DDD::one)
#define ddd_new_EMPTY() DDD(DDD::null)
#define ddd_is_STOP(d) (d == DDD::one) || (d == DDD::null)

#define ddd_concat(a,b) DDD(a ^ b)
#define ddd_union(a,b) DDD(a + b)
#define ddd_intersect(a,b) DDD(a * b)
#define ddd_minus(a,b) DDD(a - b)

#define ddd_iterator GDDD::const_iterator
#define ddd_iterator_begin(d) d.begin()
#define ddd_iterator_next(i) i++
#define ddd_iterator_end(i,d) (i == d.end())
#define ddd_iterator_value(i) i->first
#define ddd_iterator_ddd(i) DDD(i->second)

#define hom_eq(a,b) (a == b)
#define hom_ne(a,b) (a != b)
#define hom_call(h,d) DDD(h(d))
#define hom_union(a,b) (a + b)
#define hom_circ(a,b) (a & b)
#define hom_intersect_DDD_Hom(a,b) (a * b)
#define hom_intersect_Hom_DDD(a,b) (a * b)
#define hom_intersect_Hom_Hom(a,b) (a * b)
#define hom_minus_Hom_DDD(a,b) (a - b)
#define hom_ITE(a,b,c) ITE(a, b, c)
#define hom_neg(a) (! a)

#define sdd_ONE GSDD::one
#define sdd_new_ONE() SDD(GSDD::one)
#define sdd_new_EMPTY() SDD(GSDD::null)
#define sdd_new_TOP() SDD(GSDD::top)
#define sdd_is_STOP(s) (s == GSDD::one) || (s == GSDD::null)
#define sdd_is_ONE(s) (s == GSDD::one)
#define sdd_is_NULL(s) (s == GSDD::null)
#define sdd_is_TOP(s) (s == GSDD::top)
#define sdd_concat(a,b) SDD(a ^ b)
#define sdd_union(a,b) SDD(a + b)
#define sdd_intersect(a,b) SDD(a * b)
#define sdd_minus(a,b) SDD(a - b)
#define sdd_eq(a,b) a == b
#define sdd_ne(a,b) a != b

#define sdd_new_SDDs(var,val,s) SDD(var, val, s)
#define sdd_new_SDDd(var,val,s) SDD(var, val, s)
