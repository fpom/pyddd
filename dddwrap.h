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
#define ddd_iterator_end(d) d->end()
#define ddd_iterator_value(i) i->first
#define ddd_iterator_ddd(i) new DDD(i->second)
