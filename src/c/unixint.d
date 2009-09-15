/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    unixint.c -- Unix interrupt interface.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#ifdef __sun__
/* For SA_SIGINFO in Solaris. We could have used _XOPEN_SOURCE=600, but
 * this requires C99 and the default GCC for Solaris (3.4.3) does not
 * support this C standard. */
#define __EXTENSIONS__
#endif
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <ecl/ecl.h>
#if defined(HAVE_FENV_H) && !defined(ECL_AVOID_FENV_H)
# ifndef _GNU_SOURCE
#  define _GNU_SOURCE
# endif
# include <fenv.h>
#endif
#include <signal.h>
#ifdef ECL_USE_MPROTECT
# ifndef SA_SIGINFO
#  error "We cannot use the mmap code without siginfo"
# endif
# include <sys/mman.h>
#endif
#if defined(mingw32) || defined(_MSC_VER)
# include <windows.h>
#endif
#if !defined(_MSC_VER)
# include <unistd.h>
#endif
#define ECL_DEFINE_FENV_CONSTANTS
#include <ecl/internal.h>

static struct {
	int code;
	char *text;
} known_signals[] = {
#ifdef SIGHUP
	{ SIGHUP, "+SIGHUP+" },
#endif
#ifdef SIGINT
	{ SIGINT, "+SIGINT+" },
#endif
#ifdef SIGQUIT
	{ SIGQUIT, "+SIGQUIT+" },
#endif
#ifdef SIGILL
	{ SIGILL, "+SIGILL+" },
#endif
#ifdef SIGTRAP
	{ SIGTRAP, "+SIGTRAP+" },
#endif
#ifdef SIGABRT
	{ SIGABRT, "+SIGABRT+" },
#endif
#ifdef SIGEMT
	{ SIGEMT, "+SIGEMT+" },
#endif
#ifdef SIGFPE
	{ SIGFPE, "+SIGFPE+" },
#endif
#ifdef SIGKILL
	{ SIGKILL, "+SIGKILL+" },
#endif
#ifdef SIGBUS
	{ SIGBUS, "+SIGBUS+" },
#endif
#ifdef SIGSEGV
	{ SIGSEGV, "+SIGSEGV+" },
#endif
#ifdef SIGSYS
	{ SIGSYS, "+SIGSYS+" },
#endif
#ifdef SIGPIPE
	{ SIGPIPE, "+SIGPIPE+" },
#endif
#ifdef SIGALRM
	{ SIGALRM, "+SIGALRM+" },
#endif
#ifdef SIGTERM
	{ SIGTERM, "+SIGTERM+" },
#endif
#ifdef SIGURG
	{ SIGURG, "+SIGURG+" },
#endif
#ifdef SIGSTOP
	{ SIGSTOP, "+SIGSTOP+" },
#endif
#ifdef SIGTSTP
	{ SIGTSTP, "+SIGTSTP+" },
#endif
#ifdef SIGCONT
	{ SIGCONT, "+SIGCONT+" },
#endif
#ifdef SIGCHLD
	{ SIGCHLD, "+SIGCHLD+" },
#endif
#ifdef SIGTTIN
	{ SIGTTIN, "+SIGTTIN+" },
#endif
#ifdef SIGTTOU
	{ SIGTTOU, "+SIGTTOU+" },
#endif
#ifdef SIGIO
	{ SIGIO, "+SIGIO+" },
#endif
#ifdef SIGXCPU
	{ SIGXCPU, "+SIGXCPU+" },
#endif
#ifdef SIGXFSZ
	{ SIGXFSZ, "+SIGXFSZ+" },
#endif
#ifdef SIGVTALRM
	{ SIGVTALRM, "+SIGVTALRM+" },
#endif
#ifdef SIGPROF
	{ SIGPROF, "+SIGPROF+" },
#endif
#ifdef SIGWINCH
	{ SIGWINCH, "+SIGWINCH+" },
#endif
#ifdef SIGINFO
	{ SIGINFO, "+SIGINFO+" },
#endif
#ifdef SIGUSR1
	{ SIGUSR1, "+SIGUSR1+" },
#endif
#ifdef SIGUSR2
	{ SIGUSR2, "+SIGUSR2+" },
#endif
#ifdef SIGTHR
	{ SIGTHR, "+SIGTHR+" },
#endif
	{ -1, "" }
};

/******************************* ------- ******************************/

#ifdef HAVE_SIGPROCMASK
# define handler_fn_protype(name, sig, info, aux) name(sig, info, aux)
# define call_handler(name, sig, info, aux) name(sig, info, aux)
# define reinstall_signal(x,y)
# define copy_siginfo(x,y) memcpy(x, y, sizeof(struct sigaction))
static void
mysignal(int code, void (*handler)(int, siginfo_t *, void*))
{
	struct sigaction new_action, old_action;
#ifdef SA_SIGINFO
	new_action.sa_sigaction = handler;
	sigemptyset(&new_action.sa_mask);
	new_action.sa_flags = SA_SIGINFO;
# ifdef SA_ONSTACK
	if (code == SIGSEGV) {
		new_action.sa_flags |= SA_ONSTACK;
	}
# endif
#else
	new_action.sa_handler = handler;
	sigemptyset(&new_action.sa_mask);
	new_action.sa_flags = 0;
#endif
	sigaction(code, &new_action, &old_action);
}
#else /* HAVE_SIGPROCMASK */
# define handler_fn_protype(name, sig, info, aux) name(sig)
# define call_handler(name, sig, info, aux) name(sig)
# define mysignal(x,y) signal(x,y)
# define reinstall_signal(x,y) signal(x,y)
# define copy_siginfo(x,y)
#endif

static bool
interrupts_disabled_by_C(cl_env_ptr the_env)
{
	return the_env->disable_interrupts;
}

static bool
interrupts_disabled_by_lisp(cl_env_ptr the_env)
{
	return (ecl_get_option(ECL_OPT_BOOTED) &&
		ecl_symbol_value(@'si::*interrupts-enabled*') == Cnil);
}

static void
jump_to_sigsegv_handler(cl_env_ptr the_env)
{
	ecl_frame_ptr destination = frs_sch(OBJNULL);
	if (destination) {
		the_env->nvalues = 0;
		ecl_unwind(the_env, destination);
	}
	ecl_internal_error("SIGSEGV without handler to jump to.");
}

static cl_object
handler_fn_protype(lisp_signal_handler, int sig, siginfo_t *info, void *aux)
{
#if defined(ECL_THREADS) && !defined(_MSC_VER) && !defined(mingw32)
	cl_env_ptr the_env = ecl_process_env();
        if (sig == ecl_get_option(ECL_OPT_THREAD_INTERRUPT_SIGNAL)) {
		return the_env->own_process->process.interrupt;
        }
#endif
	switch (sig) {
	case SIGINT: {
                cl_object function = SYM_FUN(@'si::terminal-interrupt');
                return function? function : Cnil;
        }
	case SIGFPE: {
		cl_object condition = @'arithmetic-error';
#ifdef _MSC_VER
                switch (_fpecode) {
                case _FPE_INVALID:
                        condition = @'floating-point-invalid-operation';
                        break;
                case _FPE_OVERFLOW:
                        condition = @'floating-point-overflow';
                        break;
                case _FPE_UNDERFLOW:
                        condition = @'floating-point-underflow';
                        break;
                case _FPE_ZERODIVIDE:
                        condition = @'division-by-zero';
                        break;
                }
#endif
#if defined(HAVE_FENV_H) & !defined(ECL_AVOID_FENV_H)
		if (fetestexcept(FE_DIVBYZERO))
			condition = @'division-by-zero';
		else if (fetestexcept(FE_INVALID))
			condition = @'floating-point-invalid-operation';
		else if (fetestexcept(FE_OVERFLOW))
			condition = @'floating-point-overflow';
		else if (fetestexcept(FE_UNDERFLOW))
			condition = @'floating-point-underflow';
		else if (fetestexcept(FE_INEXACT))
			condition = @'floating-point-inexact';
                feclearexcept(FE_ALL_EXCEPT);
#endif
#ifdef SA_SIGINFO
		if (info) {
			if (info->si_code == FPE_INTDIV || info->si_code == FPE_FLTDIV)
				condition = @'division-by-zero';
			if (info->si_code == FPE_FLTOVF)
				condition = @'floating-point-overflow';
			if (info->si_code == FPE_FLTUND)
				condition = @'floating-point-underflow';
			if (info->si_code == FPE_FLTRES)
				condition = @'floating-point-inexact';
			if (info->si_code == FPE_FLTINV)
				condition = @'floating-point-invalid-operation';
		}
#endif
		si_trap_fpe(@'last', Ct);
                return condition;
	}
	case SIGSEGV:
                return @'ext::segmentation-violation';
#ifdef SIGBUS
	case SIGBUS:
                return @'ext::segmentation-violation';
#endif
	default:
		return MAKE_FIXNUM(sig);
	}
}

#define unblock_signal(sig)
#ifdef HAVE_SIGPROCMASK
# undef unblock_signal
static void
unblock_signal(int signal)
{
	struct sigaction oact;
	sigset_t block_mask;
	sigaction(signal, NULL, &oact);
	block_mask = oact.sa_mask;
	sigaddset(&block_mask, signal);
# ifdef ECL_THREADS
	pthread_sigmask(SIG_UNBLOCK, &block_mask, NULL);
# else
	sigprocmask(SIG_UNBLOCK, &block_mask, NULL);
# endif
}
#endif

static void
handle_signal_now(cl_object signal_code)
{
        switch (type_of(signal_code)) {
        case t_fixnum:
                FEerror("Serious signal ~D caught.", 1, signal_code);
                break;
        case t_symbol:
                cl_error(1, signal_code);
                break;
        case t_cfun:
        case t_cfunfixed:
        case t_bytecodes:
        case t_bclosure:
                cl_funcall(1, signal_code);
        default:
                break;
        }
}

static void
handle_or_queue(cl_object signal_code, int code)
{
	int old_errno = errno;
	cl_env_ptr the_env = ecl_process_env();
	/*
	 * If interrupts are disabled by C we are not so eager on
	 * detecting when the interrupts become enabled again. We
	 * queue the signal and are done with that.
	 */
	if (interrupts_disabled_by_lisp(the_env)) {
		if (!the_env->pending_interrupt) {
			the_env->pending_interrupt = signal_code;
		}
		errno = old_errno;
	}
	/*
	 * If interrupts are disabled by C, and we have not pushed a
	 * pending signal, save this signal and return. On platforms
	 * in which mprotect() works, we block all write access to the
	 * environment for a cheap check of pending interrupts. On other
	 * platforms we change the value of disable_interrupts to 3, so
	 * that we detect changes.
	 */
	else if (interrupts_disabled_by_C(the_env)) {
		the_env->disable_interrupts = 3;
		if (!the_env->pending_interrupt) {
			the_env->pending_interrupt = signal_code;
#ifdef ECL_USE_MPROTECT
			if (mprotect(the_env, sizeof(*the_env), PROT_READ) < 0) {
				ecl_internal_error("Unable to mprotect environment.");
                        }
#endif
		}
		errno = old_errno;
	}
	/*
	 * If interrupts are enabled, that means we are in a safe area
	 * and may execute arbitrary lisp code. We can thus call the
	 * appropriate handlers.
	 */
	else {
                errno = old_errno;
                if (code) unblock_signal(code);
                handle_signal_now(signal_code);
        }
}

static void
handler_fn_protype(non_evil_signal_handler, int sig, siginfo_t *siginfo, void *data)
{
        int old_errno = errno;
        cl_object signal_object;
	reinstall_signal(sig, non_evil_signal_handler);
	if (!ecl_get_option(ECL_OPT_BOOTED)) {
		ecl_internal_error("Got signal before environment was installed"
				   " on our thread.");
	}
        signal_object = call_handler(lisp_signal_handler, sig, siginfo, data);
        errno = old_errno;
        handle_or_queue(signal_object, sig);
}

static void
handler_fn_protype(sigsegv_handler, int sig, siginfo_t *info, void *aux)
{
	cl_env_ptr the_env;
	reinstall_signal(sig, sigsegv_handler);
	if (!ecl_get_option(ECL_OPT_BOOTED)) {
		ecl_internal_error("Got signal before environment was installed"
				   " on our thread.");
	}
	the_env = ecl_process_env();
#ifdef HAVE_SIGPROCMASK
# ifdef ECL_DOWN_STACK
	if ((char*)info->si_addr > the_env->cs_barrier &&
	    (char*)info->si_addr <= the_env->cs_org) {
		jump_to_sigsegv_handler(the_env);
                return;
	}
# else
	if ((char*)info->si_addr < the_env->cs_barrier &&
	    (char*)info->si_addr >= the_env->cs_org) {
		jump_to_sigsegv_handler(the_env);
                return;
	}
# endif
        handle_or_queue(@'ext::segmentation-violation', SIGSEGV);
#else
	/*
	 * We cannot distinguish between a stack overflow and a simple
	 * access violation. Thus we assume the worst case and jump to
	 * the outermost handler.
	 */
	jump_to_sigsegv_handler(the_env);
#endif
}

#ifdef SIGBUS
static void
handler_fn_protype(sigbus_handler, int sig, siginfo_t *info, void *aux)
{
        cl_env_ptr the_env;
	reinstall_signal(sig, sigsegv_handler);
#if defined(SA_SIGINFO) && defined(ECL_USE_MPROTECT)
	/* We access the environment when it was protected. That
	 * means there was a pending signal. */
	the_env = ecl_process_env();
	if ((void*)the_env == (void*)info->si_addr) {
		cl_object signal = the_env->pending_interrupt;
		mprotect(the_env, sizeof(*the_env), PROT_READ | PROT_WRITE);
		the_env->pending_interrupt = NULL;
		the_env->disable_interrupts = 0;
                unblock_signal(SIGBUS);
		handle_signal_now(signal);
                return;
	}
#endif
        handle_or_queue(@'ext::segmentation-violation', SIGBUS);
}
#endif

cl_object
si_check_pending_interrupts(void)
{
	ecl_check_pending_interrupts();
	@(return)
}

void
ecl_check_pending_interrupts(void)
{
	const cl_env_ptr env = ecl_process_env();
	cl_object sig;
	env->disable_interrupts = 0;
	sig = env->pending_interrupt;
	if (sig) {
		handle_signal_now(sig);
	}
}

cl_object
si_catch_signal(cl_object code, cl_object boolean)
{
	int code_int = fixnnint(code);
	int i;
#ifdef GBC_BOEHM
# ifdef SIGSEGV
	if ((code_int == SIGSEGV) && ecl_get_option(ECL_OPT_INCREMENTAL_GC))
		FEerror("It is not allowed to change the behavior of SIGSEGV.",
			0);
# endif
# ifdef SIGBUS
	if (code_int == SIGBUS)
		FEerror("It is not allowed to change the behavior of SIGBUS.",
			0);
# endif
#endif
#if defined(ECL_THREADS) && !defined(_MSC_VER) && !defined(mingw32)
	if (code_int == ecl_get_option(ECL_OPT_THREAD_INTERRUPT_SIGNAL)) {
		FEerror("It is not allowed to change the behavior of ~D", 1,
                        MAKE_FIXNUM(code_int));
	}
#endif
	for (i = 0; known_signals[i].code >= 0; i++) {
		if (known_signals[i].code == code_int) {
			if (Null(boolean))
				mysignal(code_int, SIG_DFL);
			else if (code_int == SIGSEGV)
				mysignal(code_int, sigsegv_handler);
#ifdef SIGBUS
			else if (code_int == SIGBUS)
				mysignal(code_int, sigbus_handler);
#endif
			else
				mysignal(code_int, non_evil_signal_handler);
			@(return Ct)
		}
	}
	@(return Cnil)
}

#ifdef _MSC_VER
static LPTOP_LEVEL_EXCEPTION_FILTER old_W32_exception_filter = NULL;

LONG WINAPI W32_exception_filter(struct _EXCEPTION_POINTERS* ep)
{
	LONG excpt_result;

	excpt_result = EXCEPTION_CONTINUE_EXECUTION;
	switch (ep->ExceptionRecord->ExceptionCode)
	{
		/* Catch all arithmetic exceptions */
		case EXCEPTION_INT_DIVIDE_BY_ZERO:
                        handle_or_queue(@'division-by-zero', 0);
                        return;
		case EXCEPTION_INT_OVERFLOW:
                        handle_or_queue(@'arithmetic-error', 0);
                        return;
		case EXCEPTION_FLT_DIVIDE_BY_ZERO:
                        handle_or_queue(@'floating-point-overflow', 0);
                        return;
		case EXCEPTION_FLT_OVERFLOW:
                        handle_or_queue(@'floating-point-overflow', 0);
                        return;
		case EXCEPTION_FLT_UNDERFLOW:
                        handle_or_queue(@'floating-point-underflow', 0);
                        return;
		case EXCEPTION_FLT_INEXACT_RESULT:
                        handle_or_queue(@'floating-point-indexact', 0);
                        return;
		case EXCEPTION_FLT_DENORMAL_OPERAND:
		case EXCEPTION_FLT_INVALID_OPERATION:
                        handle_or_queue(@'floating-point-invalid-operation', 0);
                        return;
		case EXCEPTION_FLT_STACK_CHECK:
                        handle_or_queue(@'arithmetic-error', 0);
                        return;
		/* Catch segmentation fault */
		case EXCEPTION_ACCESS_VIOLATION:
                        handle_or_queue(@'ext::segmentation-violation', 0);
                        return;
		/* Catch illegal instruction */
		case EXCEPTION_ILLEGAL_INSTRUCTION:
			handle_or_queue(MAKE_FIXNUM(SIGILL), 0);
			break;
		/* Do not catch anything else */
		default:
			excpt_result = EXCEPTION_CONTINUE_SEARCH;
			break;
	}
        if (old_W32_exception_filter)
                return old_W32_exception_filter(ep);
	return excpt_result;
}

BOOL WINAPI W32_console_ctrl_handler(DWORD type)
{
	switch (type)
	{
		/* Catch CTRL-C */
		case CTRL_C_EVENT:
			handle_or_queue(@'si::terminal-interrupt');
			return TRUE;
	}
	return FALSE;
}
#endif

cl_object
si_trap_fpe(cl_object condition, cl_object flag)
{
        cl_env_ptr the_env = ecl_process_env();
#ifndef FE_ALL_EXCEPT
# define FE_ALL_EXCEPT FE_DIVBYZERO | FE_OVERFLOW | FE_UNDERFLOW | FE_INVALID
#endif
        const int all = FE_ALL_EXCEPT;
	int bits = 0;
        if (condition == @'last') {
		bits = the_env->trap_fpe_bits;
        } else {
                if (condition == @'division-by-zero')
                        bits = FE_DIVBYZERO;
                else if (condition == @'floating-point-overflow')
                        bits = FE_OVERFLOW;
                else if (condition == @'floating-point-underflow')
                        bits = FE_UNDERFLOW;
                else if (condition == @'floating-point-invalid-operation')
                        bits = FE_INVALID;
                else if (condition == @'floating-point-inexact')
                        bits = FE_INEXACT;
                else if (condition == Ct)
                        bits = FE_DIVBYZERO | FE_OVERFLOW | FE_UNDERFLOW | FE_INVALID;
		else if (FIXNUMP(condition))
			bits = fix(condition) & all;
                if (flag == Cnil) {
                        bits = the_env->trap_fpe_bits & ~bits;
                } else {
                        bits = the_env->trap_fpe_bits | bits;
                }
        }
#if !defined(ECL_AVOID_FPE_H)
# ifdef HAVE_FENV_H
        feclearexcept(all);
# endif
# if defined(_MSC_VER) || defined(mingw32)
	_fpreset();
# endif
# ifdef HAVE_FEENABLEEXCEPT
        fedisableexcept(all & ~bits);
        feenableexcept(all & bits);
# endif
#endif
        the_env->trap_fpe_bits = bits;
	@(return MAKE_FIXNUM(bits))
}

void
init_unixint(int pass)
{
	if (pass == 0) {
#ifdef SIGSEGV
		if (ecl_get_option(ECL_OPT_TRAP_SIGSEGV)) {
			mysignal(SIGSEGV, sigsegv_handler);
		}
#endif
#if defined(SIGBUS) /*&& !defined(GBC_BOEHM)*/
		if (ecl_get_option(ECL_OPT_TRAP_SIGBUS)) {
			mysignal(SIGBUS, sigbus_handler);
		}
#endif
#ifdef SIGINT
		if (ecl_get_option(ECL_OPT_TRAP_SIGINT)) {
			mysignal(SIGINT, non_evil_signal_handler);
		}
#endif
#ifdef SIGRTMIN
# define DEFAULT_THREAD_INTERRUPT_SIGNAL SIGRTMIN + 2
#else
# define DEFAULT_THREAD_INTERRUPT_SIGNAL SIGUSR1
#endif
#if defined(ECL_THREADS) && !defined(_MSC_VER) && !defined(mingw32)
                {
                        int signal = ecl_get_option(ECL_OPT_THREAD_INTERRUPT_SIGNAL);
                        if (signal == 0) {
                                signal = DEFAULT_THREAD_INTERRUPT_SIGNAL;
                                ecl_set_option(ECL_OPT_THREAD_INTERRUPT_SIGNAL,
                                               signal);
                        }
                        mysignal(signal, non_evil_signal_handler);
                }
#endif
#ifdef _MSC_VER
		old_W32_exception_filter =
                        SetUnhandledExceptionFilter(W32_exception_filter);
                if (ecl_get_option(ECL_OPT_TRAP_SIGINT)) {
                        SetConsoleCtrlHandler(W32_console_ctrl_handler, TRUE);
                }
#endif
	} else {
		int i;
		for (i = 0; known_signals[i].code >= 0; i++) {
			cl_object name =
				_ecl_intern(known_signals[i].text,
					    cl_core.system_package);
			si_Xmake_constant(name, MAKE_FIXNUM(known_signals[i].code));
		}
		ECL_SET(@'si::*interrupts-enabled*', Ct);
#ifdef SIGFPE
		if (ecl_get_option(ECL_OPT_TRAP_SIGFPE)) {
			mysignal(SIGFPE, non_evil_signal_handler);
			si_trap_fpe(Ct, Ct);
# ifdef ECL_IEEE_FP
                        /* By default deactivate errors and accept
                         * denormals in floating point computations */
                        si_trap_fpe(@'floating-point-invalid-operation', Cnil);
                        si_trap_fpe(@'division-by-zero', Cnil);
# endif
		}
#endif
		ecl_process_env()->disable_interrupts = 0;
	}
}
