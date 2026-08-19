"""
The firmware carries the ten golden inputs and their answers as constants, and
lights the pass LED when the board agrees with all ten. A typo in that table
would show up as a failure that is not real, or worse, hide one that is. This
runs the golden program and checks the table in main.c still matches it.
"""
import re
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
main_c = here.parent / "board" / "Core" / "Src" / "main.c"


def array(name, text):
    m = re.search(name + r"\[GOLDEN_COUNT\]\s*=\s*\{(.*?)\}", text, re.S)
    if not m:
        sys.exit("could not find " + name + " in main.c")
    return [int(v.strip().rstrip("U")) for v in m.group(1).split(",") if v.strip()]


def golden_rows():
    out = subprocess.run(["./golden"], cwd=here, capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            rows.append((int(parts[0]), int(parts[1])))
    return rows


text = main_c.read_text()
inputs = array("golden_in", text)
answers = array("golden_out", text)
rows = golden_rows()

if len(inputs) != len(answers):
    sys.exit("the two tables in main.c are different lengths")
if len(rows) != len(inputs):
    sys.exit("golden printed %d rows, main.c has %d entries" % (len(rows), len(inputs)))

bad = 0
for (gi, go), fi, fa in zip(rows, inputs, answers):
    if gi != fi or go != fa:
        print("mismatch, golden says isqrt(%d) = %d, main.c has isqrt(%d) = %d" % (gi, go, fi, fa))
        bad += 1

print("checked %d golden entries, %d mismatches" % (len(rows), bad))
sys.exit(1 if bad else 0)
