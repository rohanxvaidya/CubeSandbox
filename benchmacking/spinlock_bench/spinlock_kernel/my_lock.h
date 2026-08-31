/* SPDX-License-Identifier: GPL-2.0 */
#undef TRACE_SYSTEM
#define TRACE_SYSTEM my_lock

#if !defined(_TRACE_MY_LOCK_H) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_MY_LOCK_H

#include <linux/sched.h>
#include <linux/tracepoint.h>
//#include <trace/events/trace.h>

TRACE_EVENT(my_lock_begin,

	TP_PROTO(void *lock, unsigned int flags),

	TP_ARGS(lock, flags),

	TP_STRUCT__entry(
		__field(void *, lock_addr)
		__field(unsigned int, flags)
	),

	TP_fast_assign(
		__entry->lock_addr = lock;
		__entry->flags = flags;
	),

	TP_printk("%p (flags=%s)", __entry->lock_addr,"SPIN")
);

TRACE_EVENT(my_lock_end,

	TP_PROTO(void *lock, int ret),

	TP_ARGS(lock, ret),

	TP_STRUCT__entry(
		__field(void *, lock_addr)
		__field(int, ret)
	),

	TP_fast_assign(
		__entry->lock_addr = lock;
		__entry->ret = ret;
	),

	TP_printk("%p (ret=%d)", __entry->lock_addr, __entry->ret)
);


TRACE_EVENT(my_lock_end_3,

 TP_PROTO(void *lock, int ret, unsigned long long t1, unsigned long long t2, unsigned long long t3),

        TP_ARGS(lock, ret, t1, t2, t3),

        TP_STRUCT__entry(
                __field(void *, lock_addr)
                __field(int, ret)
                __field(unsigned long long, t1)
                __field(unsigned long long, t2)
                __field(unsigned long long, t3)
        ),

        TP_fast_assign(
                __entry->lock_addr = lock;
                __entry->ret = ret;
                __entry->t1 = t1;
                __entry->t2 = t2;
                __entry->t3 = t3;
        ),

       TP_printk("%p (ret=%d), T1=%llu, T2=%llu, T3=%llu", __entry->lock_addr, __entry->ret, __entry->t1, __entry->t2, __entry->t3)
);

TRACE_EVENT(my_lock_begin_8,

       TP_PROTO(void *lock, unsigned int flags),

       TP_ARGS(lock, flags),

       TP_STRUCT__entry(
               __field(void *, lock_addr)
               __field(unsigned int, flags)
       ),

       TP_fast_assign(
               __entry->lock_addr = lock;
               __entry->flags = flags;
       ),

       TP_printk("%p (flags=%s)", __entry->lock_addr,"SPIN")
);

TRACE_EVENT(my_lock_end_8,

 TP_PROTO(void *lock, int ret, unsigned long long t1, unsigned long long t2, unsigned long long t3, unsigned long long t4, unsigned long long t5, unsigned long long t6, unsigned long long t7, unsigned long long t8),

        TP_ARGS(lock, ret, t1, t2, t3, t4, t5, t6, t7, t8),

        TP_STRUCT__entry(
                __field(void *, lock_addr)
                __field(int, ret)
                __field(unsigned long long, t1)
                __field(unsigned long long, t2)
                __field(unsigned long long, t3)
                __field(unsigned long long, t4)
                __field(unsigned long long, t5)
                __field(unsigned long long, t6)
                __field(unsigned long long, t7)
                __field(unsigned long long, t8)
        ),

        TP_fast_assign(
                __entry->lock_addr = lock;
                __entry->ret = ret;
                __entry->t1 = t1;
                __entry->t2 = t2;
                __entry->t3 = t3;
                __entry->t4 = t4;
                __entry->t5 = t5;
                __entry->t6 = t6;
                __entry->t7 = t7;
                __entry->t8 = t8;
        ),

       TP_printk("%p (ret=%d), T1=%llu, T2=%llu, T3=%llu, T4=%llu, T5=%llu, T6=%llu, T7=%llu, T8=%llu", __entry->lock_addr, __entry->ret, __entry->t1, __entry->t2, __entry->t3, __entry->t4, __entry->t5, __entry->t6, __entry->t7, __entry->t8)
);




#endif /* _TRACE_LOCK_H */

/* This part must be outside protection */
#include <trace/define_trace.h>
