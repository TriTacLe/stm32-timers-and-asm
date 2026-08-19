CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=gnu11
LDLIBS = -lm

golden: golden.c
	$(CC) $(CFLAGS) -o $@ golden.c $(LDLIBS)

verify_fast: verify_fast.c
	$(CC) $(CFLAGS) -o $@ verify_fast.c $(LDLIBS)

run: golden
	./golden

# the two checks that do not need the board. verify_fast compares the board
# algorithm against the golden one, check_golden_table compares the constants
# the firmware ships with against what golden actually prints
test: verify_fast golden
	./verify_fast
	python3 check_golden_table.py

clean:
	rm -f golden verify_fast
