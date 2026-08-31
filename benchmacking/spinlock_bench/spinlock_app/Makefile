CC = gcc
CFLAGS = -Wall -Werror -O2 -pthread -std=gnu11 -D_GNU_SOURCE
LDFLAGS = -pthread -static

SRCS = spinlock_bench.c
OBJS = $(SRCS:.c=.o)
DEPS = $(SRCS:.c=.d)

all: spinlock_bench

spinlock_bench: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(DEPS)

clean:
	rm -f spinlock_bench $(OBJS) $(DEPS)

rebuild: clean all
