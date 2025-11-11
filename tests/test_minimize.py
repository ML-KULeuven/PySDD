from pysdd.sdd import SddManager, Vtree
from pysdd.iterator import SddIterator
from pysdd.util import sdd_to_dot, vtree_to_dot
import sys
import os
import logging
from pathlib import Path
import tempfile


logger = logging.getLogger("pysdd")

directory = Path(tempfile.gettempdir())
counter = 0


def test_min1():
    vtree = Vtree(var_count=4, var_order=[1, 4, 2, 3], vtree_type="right")
    sdd = SddManager.from_vtree(vtree)
    sdd.auto_gc_and_minimize_off()
    a, b, c, d = sdd.vars
    f = ((a & b) | (c & d))
    f.ref()
    if directory:
        names = {
            1: 'a', -1: '-a',
            2: 'b', -2: '-b',
            3: 'c', -3: '-c',
            4: 'd', -4: '-d'
        }
        # with (directory / "vtree1_before_a.gv").open("w") as out:
        #     print(sdd.vtree().dot(), file=out)
        # with (directory / "vtree1_before_b.gv").open("w") as out:
        #     print(vtree_to_dot(sdd.vtree(), sdd, litnamemap=names, show_id=True), file=out)
        # with (directory / "sdd1_before_a.gv").open("w") as out:
        #     print(sdd.dot(), file=out)
        # with (directory / "sdd1_before_b.gv").open("w") as out:
        #     print(sdd_to_dot(sdd), file=out)
    sdd.minimize()
    # if directory:
    #     with (directory / "vtree2_after.gv").open("w") as out:
    #         print(sdd.vtree().dot(), file=out)
    #     with (directory / "sdd1_after.gv").open("w") as out:
    #         print(sdd.dot(), file=out)
    f.deref()

    wmc = f.wmc(log_mode=False)
    mc = wmc.propagate()
    # print(f"mc = {mc}")
    assert mc == 7.0


def test_min2():
    sdd = SddManager(var_count=3)
    a, b, c = sdd.vars
    fa = b | c
    fa.ref()
    fb = b
    fb.ref()
    fc = c
    fc.ref()
    if directory:
        names = {
            1: 'a', -1: '-a',
            2: 'b', -2: '-b',
            3: 'c', -3: '-c'
        }
        # with (directory / "vtree2_before_a.gv").open("w") as out:
        #     print(sdd.vtree().dot(), file=out)
        # with (directory / "vtree2_before_b.gv").open("w") as out:
        #     print(vtree_to_dot(sdd.vtree(), sdd, litnamemap=names, show_id=True), file=out)
        # with (directory / "sdd2_before_a.gv").open("w") as out:
        #     print(sdd.dot(), file=out)
        # with (directory / "sdd2_before_b.gv").open("w") as out:
        #     print(sdd_to_dot(sdd), file=out)

def test_refcount():
    sdd = SddManager(var_count=2)
    a, b = sdd.vars
    f = a | b
    assert f.ref_count() == 1
    f.ref()
    assert f.ref_count() == 2
    f.deref()
    assert f.ref_count() == 1
    # equivalent formula will
    # ref same formula object
    f2 = b | a
    assert f2.ref_count() == 2
    assert f.ref_count() == 2
    del f2
    assert f.ref_count() == 1

if __name__ == "__main__":
    logger.setLevel(logging.DEBUG)
    sh = logging.StreamHandler(sys.stdout)
    logger.addHandler(sh)
    directory = Path(os.environ.get('TESTDIR', Path(".")))
    print(f"Saving files to {directory}")
    test_min1()
    test_min2()
