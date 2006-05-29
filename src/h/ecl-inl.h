/*
 * Loops over a proper list
 */
#ifdef ECL_SAFE
#define loop_for_in(list) { \
  cl_object __slow; \
  bool __flag = TRUE; \
  for (__slow = list; !endp(list); list = CDR(list)) { \
    if ((__flag = !__flag)) { \
      if (__slow == list) FEcircular_list(list); \
      __slow = CDR(__slow); \
    }
#else
#define loop_for_in(list) { \
  for (; !endp(list); list = CDR(list)) {
#endif
#define end_loop_for_in }}

/*
 * Loops over a dotted list
 */
#ifdef ECL_SAFE
#define loop_for_on(list) \
  if (!CONSP(list)) { \
    if (list != Cnil) FEtype_error_list(list); \
  }else { \
    cl_object __slow; \
    bool __flag = TRUE; \
    for (__slow = list; CONSP(list); list = CDR(list)) { \
      if ((__flag = !__flag)) { \
        if (__slow == list) FEcircular_list(list); \
        __slow = CDR(__slow); \
      }
#else
#define loop_for_on(list) \
  if (!CONSP(list)) { \
    if (list != Cnil) FEtype_error_list(list); \
  else { \
    for (; CONSP(list); list = CDR(list)) {
#endif
#define end_loop_for_on }}

/* The following is unused */
#if 0 && defined(GBC_BOEHM) && defined(__GNUC__)

#define alloc_object fast_alloc_object
#define make_cons fast_make_cons

extern void *GC_malloc(size_t);
extern void *GC_malloc_atomic(size_t);

static inline cl_object
fast_alloc_object(enum type t)
{
  cl_object x;
  switch (t) {
  case t_cons:
    x = GC_malloc(sizeof(struct cons)); break;
  case t_fixnum:
    return MAKE_FIXNUM(0);
  case t_character:
    return code_char(' ');
  case t_bignum:
    x = GC_malloc(sizeof(struct bignum)); break;
  case t_ratio:
    x = GC_malloc(sizeof(struct ratio)); break;
  case t_shortfloat:
    x = GC_malloc_atomic(sizeof(struct shortfloat_struct)); break;
  case t_longfloat:
    x = GC_malloc_atomic(sizeof(struct longfloat_struct)); break;
  case t_complex:
    x = GC_malloc(sizeof(struct complex)); break;
  case t_symbol:
    x = GC_malloc(sizeof(struct symbol)); break;
  case t_package:
    x = GC_malloc(sizeof(struct package)); break;
  case t_hashtable:
    x = GC_malloc(sizeof(struct hashtable)); break;
  case t_array:
    x = GC_malloc(sizeof(struct array)); break;
  case t_vector:
    x = GC_malloc(sizeof(struct vector)); break;
  case t_base_string:
    x = GC_malloc(sizeof(struct base_string)); break;
  case t_bitvector:
    x = GC_malloc(sizeof(struct bitvector)); break;
  case t_stream:
    x = GC_malloc(sizeof(struct stream)); break;
  case t_random:
    x = GC_malloc_atomic(sizeof(struct random)); break;
  case t_readtable:
    x = GC_malloc(sizeof(struct readtable)); break;
  case t_pathname:
    x = GC_malloc(sizeof(struct pathname)); break;
  case t_cfun:
    x = GC_malloc(sizeof(struct cfun)); break;
  case t_cclosure:
    x = GC_malloc(sizeof(struct cclosure)); break;
#ifdef CLOS
  case t_instance:
    x = GC_malloc(sizeof(struct instance)); break;
  case t_gfun:
    x = GC_malloc(sizeof(struct gfun)); break;
#else
  case t_structure:
    x = GC_malloc(sizeof(struct structure)); break;
#endif
#ifdef THREADS
  case t_cont:
    x = GC_malloc(sizeof(struct cont)); break;
  case t_thread:
    x = GC_malloc(sizeof(struct thread)); break;
#endif
  default:
    error("allocation botch!");
  }
  x->c.t = t;
  return x;
}

static inline
cl_object fast_make_cons(cl_object a, cl_object b)
{
  cl_object x = GC_malloc(sizeof(struct cons));
  x->c.t = t_cons;
  x->c.c_car = a;
  x->c.c_cdr = b;
  return x;
}

#endif
