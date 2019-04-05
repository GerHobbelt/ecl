/* -*- Mode: C; c-basic-offset: 2; indent-tabs-mode: nil -*- */
/* vim: set filetype=c tabstop=2 shiftwidth=2 expandtab: */

/*
 * sinh.d - trascendental functions: exponential
 *
 * Copyright (c) 1984 Taiichi Yuasa and Masami Hagiya
 * Copyright (c) 1990 Giuseppe Attardi
 * Copyright (c) 2001 Juan Jose Garcia Ripoll
 *
 * See file 'LICENSE' for the copyright details.
 *
 */

#define ECL_INCLUDE_MATH_H
#include <ecl/ecl.h>
#include <ecl/internal.h>
#include <ecl/impl/math_dispatch.h>

#pragma STDC FENV_ACCESS ON

cl_object
cl_exp(cl_object x)
{
  @(return ecl_exp(x));
}

static cl_object
ecl_exp_rational(cl_object x)
{
  return ecl_make_single_float(expf(ecl_to_float(x)));
}

static cl_object
ecl_exp_single_float(cl_object x)
{
  return ecl_make_single_float(expf(ecl_single_float(x)));
}

static cl_object
ecl_exp_double_float(cl_object x)
{
  return ecl_make_double_float(exp(ecl_double_float(x)));
}

#ifdef ECL_LONG_FLOAT
static cl_object
ecl_exp_long_float(cl_object x)
{
  return ecl_make_long_float(expl(ecl_long_float(x)));
}
#endif

static cl_object
ecl_exp_complex(cl_object x)
{
  cl_object y, y1;
  y = x->gencomplex.imag;
  x = ecl_exp(x->gencomplex.real);
  y1 = ecl_cos(y);
  y = ecl_sin(y);
  y = ecl_make_complex(y1, y);
  return ecl_times(x, y);
}

MATH_DEF_DISPATCH1(exp, @[exp], @[number],
                   ecl_exp_rational, ecl_exp_rational, ecl_exp_rational,
                   ecl_exp_single_float, ecl_exp_double_float, ecl_exp_long_float,
                   ecl_exp_complex);
