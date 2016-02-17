CC=gcc
CFLAGS=-Wall -g
LDFLAGS=-lrt
#LD_LIBRARY_PATH=/usr/lib/powerpc64le-linux-gnu/

all: iogen

iogen: main.o
	$(CC) -o $@ $^ $(LDFLAGS)
    
%.o: %.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -rf *.o
	rm -rf iogen
