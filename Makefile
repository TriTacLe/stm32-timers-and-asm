REPORT_DIR := Practical_1B
REPORT_PDF := $(REPORT_DIR)/prac1B_lxxtri004_shrgil004.pdf

.PHONY: help pull report view-report latest clean-report

help:
	@printf '%s\n' \
	  'make report       Build the Practical 1B PDF (two LaTeX passes)' \
	  'make view-report  Build and open the PDF' \
	  'make latest       Pull the newest main branch, then build and open' \
	  'make clean-report Remove temporary LaTeX files'

pull:
	git pull --ff-only

report:
	$(MAKE) -C $(REPORT_DIR) report

view-report: report
	@if command -v open >/dev/null 2>&1; then \
	  open "$(REPORT_PDF)"; \
	elif command -v xdg-open >/dev/null 2>&1; then \
	  xdg-open "$(REPORT_PDF)"; \
	else \
	  printf 'Built %s; open it with your PDF reader.\n' "$(REPORT_PDF)"; \
	fi

latest:
	$(MAKE) pull
	$(MAKE) view-report

clean-report:
	$(MAKE) -C $(REPORT_DIR) clean-report
