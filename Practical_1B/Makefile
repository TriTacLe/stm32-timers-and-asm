# make 1        run the Task 1 golden measure on the PC
# make 2..5     build the board image for that task, FLASH=1 to program it too
# make 3        builds all four optimisation levels and prints the text sizes
# make test     host cross checks, make report builds the PDF
OPT ?= -O2
FLASH ?= 0

.PHONY: 1 2 3 4 5 test report clean clean-report

1:
	$(MAKE) -C Task1_PC run

2 4 5:
	$(MAKE) -C board clean all TASK=$@ OPT=$(OPT)
	@if [ "$(FLASH)" = 1 ]; then $(MAKE) -C board flash; fi

3:
	@for o in -O0 -O1 -O2 -Os; do \
	  $(MAKE) -s -C board clean all TASK=2 OPT=$$o >/dev/null; \
	  printf '%-4s ' $$o; arm-none-eabi-size board/build/Practical_1B.elf | tail -1; \
	done

test:
	$(MAKE) -C Task1_PC test

report:
	@if command -v pdflatex >/dev/null 2>&1; then \
	  pdflatex -interaction=nonstopmode -halt-on-error prac1B_lxxtri004_shrgil004.tex && \
	  pdflatex -interaction=nonstopmode -halt-on-error prac1B_lxxtri004_shrgil004.tex; \
	elif command -v tectonic >/dev/null 2>&1; then \
	  tectonic --keep-logs prac1B_lxxtri004_shrgil004.tex; \
	else \
	  echo "Error: install pdflatex (preferred) or tectonic." >&2; \
	  exit 1; \
	fi

clean-report:
	rm -f prac1B_lxxtri004_shrgil004.{aux,log,out,toc}

clean:
	$(MAKE) -C board clean
	$(MAKE) -C Task1_PC clean
	$(MAKE) clean-report
