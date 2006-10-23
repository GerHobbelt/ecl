/*
    init.c  -- Lisp Initialization.
*/
/*
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <stdio.h>
#include <ecl/ecl.h>
#include <ecl/internal.h>

/*
 * HOOKS.
 *
 * The following functions are only used to bootstrap ECL. They divert
 * the calls to the interpreted code which is loaded by bare.lsp. Once
 * the whole of ECL is built, the file cinit.o will be replaced by the
 * actual initialization code, and the compiled function will be
 * called instead.
 */

extern cl_object
si_safe_eval(cl_narg arg, cl_object form, cl_object env, cl_object error_value, ...)
{
	return cl_funcall(4, @'si::safe-eval', form, env, error_value);
}

extern cl_object
si_signal_simple_error(cl_narg narg, cl_object condition, cl_object continuable, cl_object format, cl_object format_args, ...)
{
	cl_va_list args;
	cl_va_start(args, format_args, narg, 4);
	return cl_apply(6, @'si::signal-simple-error', condition, continuable, format, format_args, cl_grab_rest_args(args));
}

extern cl_object
cl_array_dimensions(cl_narg narg, cl_object array, ...)
{
	return funcall(2, @'ARRAY-DIMENSIONS', array);
}

extern cl_object
cl_vector_push_extend(cl_narg narg, cl_object elt, cl_object vector, ...)
{
	cl_index fp;
	if (narg != 2) {
		FEerror("Too many arguments to interim cl_vector_push_extend (cinit.d)", 0);
	}
	fp = vector->vector.fillp;
	if (fp < vector->vector.dim) {
		vector->vector.fillp = fp+1;
		vector->vector.self.t[fp+1] = elt;
		@(return MAKE_FIXNUM(fp))
	}
	return funcall(3, @'VECTOR-PUSH-EXTEND', elt, vector);
}

static cl_object si_simple_toplevel ()
{
	cl_object sentence;
	int i;

	/* Simple minded top level loop */
	printf(";*** Lisp core booted ****\nECL (Embeddable Common Lisp)  %d pages\n", MAXPAGE);
	fflush(stdout);
	for (i = 1; i<fix(si_argc()); i++) {
	  cl_object arg = si_argv(MAKE_FIXNUM(i));
	  cl_load(1, arg);
	}
	while (1) {
	  printf("\n> ");
	  sentence = @read(3, Cnil, Cnil, OBJNULL);
	  if (sentence == OBJNULL)
	    @(return);
	  prin1(si_eval_with_env(1, sentence), Cnil);
	}
}

int
main(int argc, char **args)
{
	cl_object top_level;

	/* This should be always the first call */
	cl_boot(argc, args);

	/* We are computing unnormalized numbers at some point */
	si_trap_fpe(Ct, Cnil);

#ifdef ECL_CMU_FORMAT
	SYM_VAL(@'*load-verbose*') = Cnil;
#endif
	SYM_VAL(@'*package*') = cl_core.system_package;
	SYM_VAL(@'*features*') = CONS(make_keyword("ECL-MIN"), SYM_VAL(@'*features*'));
	top_level = _intern("TOP-LEVEL", cl_core.system_package);
	cl_def_c_function(top_level, si_simple_toplevel, 0);
	funcall(1, top_level);
	return(0);
}

#ifdef __cplusplus
extern "C" void init_LSP(cl_object);
#endif

void init_LSP(cl_object o) {}
