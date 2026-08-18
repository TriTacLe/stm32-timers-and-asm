CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=gnu11
LDLIBS = -lm

golden: golden.c
	$(CC) $(CFLAGS) -o $@ golden.c $(LDLIBS)

run: golden
	./golden

clean:
	rm -f golden
