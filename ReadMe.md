## Highlights & Introduction
This repository contains the code and documentation for the practicals for the  EEE3096S: Embedded Systems II course, a third-year module in Electrical Engineering at the University of Cape Town (UCT).

## Repository Structure
The repository is organised as follows:
- Each practical has its own dedicated folder (e.g., `Practical 1`, `Practical 2`, etc.)
- Within each practical's folder, you will find:
  - The practical manual.
  - The practical skeleton's code.

## Practicals Overview
Each practical is geared to run concurrently with what is taught in class

## Reading the Practical 1B report

From the repository root, build the LaTeX report with:

```sh
make report
```

Use `make view-report` to build and open the PDF. To first pull the newest
changes from the shared `main` branch, then build and open it, run:

```sh
make latest
```

The report prefers `pdflatex` (included with MacTeX on macOS) and falls back to
Tectonic for a lightweight local preview. The generated PDF and LaTeX temporary
files stay local and are ignored by Git.
