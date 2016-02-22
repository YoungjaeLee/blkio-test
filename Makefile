CC=gcc
CFLAGS=-Wall -g
LDFLAGS=-lrt
#LD_LIBRARY_PATH=/usr/lib/powerpc64le-linux-gnu/

all: iogen test

test: test.o 
	$(CC) -o $@ $^

iogen: main.o util.o
	$(CC) -o $@ $^ $(LDFLAGS)
    
%.o: %.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -rf *.o
	rm -rf iogen test
