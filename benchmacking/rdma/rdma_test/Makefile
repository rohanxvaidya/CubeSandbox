CC ?= gcc
#CFLAGS ?= -O2 -g -Wall -Wextra -std=c11 -finstrument-functions
CFLAGS ?= -O2 -g -Wall -Wextra -std=c11 
LDFLAGS ?=
LDLIBS ?= -lrdmacm -libverbs

TARGET := rdma_test_tool
SRC := rdma_test_tool.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) $(LDLIBS)

clean:
	rm -f $(TARGET)
