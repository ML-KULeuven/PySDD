from pysdd.util import nnf_file_wmc, sdd_file_wmc, psdd_file_wmc
from pysdd import cli
import sys
import os
import math
import logging
from pathlib import Path


logger = logging.getLogger("pysdd")
directory = None
counter = 0
here = Path(__file__).parent

def file_contents_equal(path1, path2):
    with open(path1) as f1:
        lines1 = [l.strip() for l in f1.readlines()]
    with open(path2) as f2:
        lines2 = [l.strip() for l in f2.readlines()]
    return lines1 == lines2


def test_nnf1():
    weights = {
        +3: 0.5, +2: 0.5, +1: 1,
        -3: 0.5, -2: 0.5, -1: 1
    }
    wmc = nnf_file_wmc(here / "rsrc" / "test.cnf.nnf", weights)
    assert wmc == 1.0


def test_nnf2():
    weights = {
        +3: 0.5, +2: 0.5, +1: 1,
        -3: 0.5, -2: 0.5, -1: 0
    }
    wmc = nnf_file_wmc(here / "rsrc" / "test.cnf.nnf", weights)
    assert wmc == 0.75


def test_sdd1():
    weights = {
        +3: 0.5, +2: 0.5, +1: 1,
        -3: 0.5, -2: 0.5, -1: 1
    }
    wmc = sdd_file_wmc(here / "rsrc" / "test.sdd", weights)
    print("WMC", wmc)
    assert wmc == 1.0, f"{wmc} != 1.0"


def test_sdd2():
    weights = {
        +3: 0.5, +2: 0.5, +1: 1,
        -3: 0.5, -2: 0.5, -1: 0
    }
    wmc = sdd_file_wmc(here / "rsrc" / "test.sdd", weights)
    print("WMC", wmc)
    assert wmc == 0.75, f"{wmc} != 0.75"


def test_psdd1():
    wmc = psdd_file_wmc(here / "rsrc" / "test.psdd", None)
    wmc = math.exp(wmc)
    print("WMC", wmc)


def test_dimacs1():
    fn_dimacs = here / "rsrc" / "dimacs1.txt"
    fn_vtree = here / "rsrc" / "dimacs1.vtree"
    fn_vtree_sol = here / "rsrc" / "dimacs1_solution.vtree"
    fn_sdd = here / "rsrc" / "dimacs1.sdd"
    cli.main(["-c", str(fn_dimacs), "-W", str(fn_vtree), "-R", str(fn_sdd)])
    assert file_contents_equal(fn_vtree, fn_vtree_sol)
    with fn_vtree.open("r") as fp:
        print(fp.read())


if __name__ == "__main__":
    logger.setLevel(logging.DEBUG)
    sh = logging.StreamHandler(sys.stdout)
    logger.addHandler(sh)
    directory = Path(os.environ.get('TESTDIR', Path(__file__).parent))
    print(f"Saving files to {directory}")
    test_nnf1()
    test_nnf2()
    test_sdd1()
    test_sdd2()
    test_psdd1()
    test_dimacs1()
