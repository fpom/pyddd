#include <string>
#include "ddd/DDD.h"

#define ddd_ONE DDD::one
#define ddd_new_ONE() new DDD(DDD::one)
#define ddd_new_EMPTY() new DDD(DDD::null)
#define ddd_new_TOP() new DDD(DDD::top)

#define ddd_STOP(d) (d == DDD::one) || (d == DDD::null)

#define ddd_concat(a,b) new DDD(a ^ b)
#define ddd_union(a,b) new DDD(a + b)
#define ddd_intersect(a,b) new DDD(a * b)
#define ddd_minus(a,b) new DDD(a - b)

#define ddd_iterator GDDD::const_iterator
#define ddd_iterator_begin(d) d->begin()
#define ddd_iterator_next(i) i++
#define ddd_iterator_end(i,d) (i == d->end())
#define ddd_iterator_value(i) i->first
#define ddd_iterator_ddd(i) new DDD(i->second)

#define sdd_ONE GSDD::one
#define sdd_new_ONE() new SDD(GSDD::one)
#define sdd_new_EMPTY() new SDD(GSDD::null)
#define sdd_new_TOP() new SDD(GSDD::top)
#define sdd_STOP(s) (s == GSDD::one) || (s == GSDD::null)
#define sdd_concat(a,b) new SDD(a ^ b)
#define sdd_union(a,b) new SDD(a + b)
#define sdd_intersect(a,b) new SDD(a * b)
#define sdd_minus(a,b) new SDD(a - b)
#define sdd_eq(a,b) a == b
#define sdd_ne(a,b) a != b

#define sdd_new_SDDs(var,val,s) new SDD(var, val, s)
#define sdd_new_SDDd(var,val,s) new SDD(var, val, s)

#define sdd_iterator GSDD::const_iterator
#define sdd_iterator_begin(s) s->begin()
#define sdd_iterator_next(i) i++
#define sdd_iterator_end(i,s) (i == s->end())
#define sdd_iterator_sdd(i) new SDD(i->second)
#define sdd_iterator_value_is_SDD(i) (dynamic_cast<SDD*>(i->first) != NULL)
#define sdd_iterator_value_is_DDD(i) (dynamic_cast<DDD*>(i->first) != NULL)
#define sdd_iterator_value_is_GSDD(i) (dynamic_cast<GSDD*>(i->first) != NULL)
#define sdd_iterator_SDD_value(i) dynamic_cast<SDD*>(i->first)
#define sdd_iterator_GSDD_value(i) new SDD(dynamic_cast<GSDD*>(i->first)[0])
#define sdd_iterator_DDD_value(i) dynamic_cast<DDD*>(i->first)
