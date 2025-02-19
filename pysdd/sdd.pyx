# -*- coding: UTF-8 -*-
"""
pysdd.sdd_c
~~~~~~~~~~~

SDD Python interface.

:author: Wannes Meert, Arthur Choi
:copyright: Copyright 2017-2019 KU Leuven and Regents of the University of California.
:license: Apache License, Version 2.0, see LICENSE for details.

"""
cimport cython
from . cimport sddapi_c
from . cimport compiler_c
from . cimport io_c
from . cimport fnf_c
from cpython cimport array
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from libc.time cimport clock_t

import os
import tempfile
from contextlib import redirect_stdout, redirect_stderr
import io
import cython
import collections


# IF HAVE_CYSIGNALS:  # IF is deprecated in cython, drop cysignals support for now
#     from cysignals.signals cimport sig_on, sig_off
# ELSE:
# for non-POSIX systems
noop = lambda: None
sig_on = noop
sig_off = noop


cdef class SddNode:
    cdef sddapi_c.SddNode* _sddnode
    cdef SddManager _manager
    cdef _name

    def __cinit__(self, manager):
        self._manager = manager
        self._name = "?"

    @staticmethod
    cdef wrap(sddapi_c.SddNode* node, SddManager manager):
        if node == NULL:
            return None
        wrapper = SddNode(manager)
        wrapper._sddnode = node
        if wrapper.garbage_collected():
            return None
        if sddapi_c.sdd_node_is_literal(node):
            wrapper._name = sddapi_c.sdd_node_literal(node)
        elif sddapi_c.sdd_node_is_true(node):
            wrapper._name = "True"
        elif sddapi_c.sdd_node_is_false(node):
            wrapper._name = "False"
        elif sddapi_c.sdd_node_is_decision(node):
            wrapper._name = "Decision"
        return wrapper


    @property
    def id(self):
        """Unique id of the SDD node.

        Every SDD node has an ID. When an SDD node is garbage collected, its structure is not
        freed but inserted into a gc-list. Moreover, this structure may be reused later by
        another, newly created SDD node, which will have its own new ID.

        :return: id
        """
        return sddapi_c.sdd_id(self._sddnode)

    def __hash__(self):
        return self.id

    def garbage_collected(self):
        """Returns true if the SDD node with the given ID has been garbage collected; returns false otherwise.

        This function may be helpful for debugging.
        """
        return sddapi_c.sdd_garbage_collected(self._sddnode, self.id) == 1

    @property
    def manager(self):
        return self._manager

    def is_literal(self):
        """The node is a literal.

        A functions that is useful for navigating the structure of an SDD (i.e., visiting all its nodes).
        """
        return sddapi_c.sdd_node_is_literal(self._sddnode)

    @property
    def literal(self):
        """Returns the signed integer (i.e., variable index or the negation of a variable index) of an SDD
        node representing a literal. Assumes that sdd node is literal(node) returns 1.
        """
        if not self.is_literal():
            return 0
        return sddapi_c.sdd_node_literal(self._sddnode)

    def is_true(self):
        """The node is a node representing true.

        A functions that is useful for navigating the structure of an SDD (i.e., visiting all its nodes).
        """
        return sddapi_c.sdd_node_is_true(self._sddnode)

    def is_false(self):
        """The node is a node representing false.

        A functions that is useful for navigating the structure of an SDD (i.e., visiting all its nodes).
        """
        return sddapi_c.sdd_node_is_false(self._sddnode)

    def is_decision(self):
        """The node is a decision node.

        A functions that is useful for navigating the structure of an SDD (i.e., visiting all its nodes).
        """
        return sddapi_c.sdd_node_is_decision(self._sddnode)

    def conjoin(self, SddNode other):
        return self._manager.conjoin(self, other)

    def __mul__(SddNode left, SddNode right):
        return left._manager.conjoin(left, right)

    def __and__(SddNode left, SddNode right):
        return left._manager.conjoin(left, right)

    def disjoin(self, SddNode other):
        return self._manager.disjoin(self, other)

    def __add__(SddNode left, SddNode right):
        return left._manager.disjoin(left, right)

    def __or__(SddNode left, SddNode right):
        return left._manager.disjoin(left, right)

    def negate(self):
        return self._manager.negate(self)

    def __neg__(SddNode node):
        return node._manager.negate(node)

    def __invert__(SddNode node):
        return node._manager.negate(node)

    def equiv(SddNode left, SddNode right):
        return (~left | right) & (left | ~right)

    def condition(SddNode node, lit):
        return node._manager.condition(lit, node)

    def model_count(self):
        return self._manager.model_count(self)

    def global_model_count(self):
        return self._manager.global_model_count(self)

    def node_size(self):
        """Returns the size of an SDD node (the number of its elements).

        Recall that the size is zero for terminal nodes (i.e., non-decision nodes).
        """
        return sddapi_c.sdd_node_size(self._sddnode)

    def size(self):
        """Returns the size of an SDD (rooted at node)."""
        return sddapi_c.sdd_size(self._sddnode)

    def count(self):
        """Returns the node count of an SDD (rooted at node)."""
        return sddapi_c.sdd_count(self._sddnode)

    def elements(self):
        """Returns an array containing the elements of an SDD node.

        :returns: A list of pairs [(prime, sub)]

        Internal working:
        If the node has m elements, the array will be of size 2m, with primes appearing at locations
        0, 2, . . . , 2m − 2 and their corresponding subs appearing at locations 1, 3, . . . , 2m − 1.
        Assumes that sdd node is decision(node) returns 1. Moreover, the returned array should not be
        freed.
        """
        cdef sddapi_c.SddNode** nodes;
        nodes = sddapi_c.sdd_node_elements(self._sddnode)
        # do not free memory of nodes
        m = self.node_size()
        primesubs = []
        for i in range(0, 2 * m, 2):
            primesubs.append((SddNode.wrap(nodes[i], self._manager),
                              SddNode.wrap(nodes[i + 1], self._manager)))
        return primesubs

    def bit(self):
        return sddapi_c.sdd_node_bit(self._sddnode)

    def set_bit(self, int bit):
        sddapi_c.sdd_node_set_bit(bit, self._sddnode)

    def vtree(self):
        """Returns the vtree of an SDD node."""
        return Vtree.wrap(sddapi_c.sdd_vtree_of(self._sddnode), is_ref=True)

    def vtree2(self):
        """Returns the vtree of an SDD node."""
        return Vtree.wrap(self._sddnode.vtree, is_ref=True)

    def vtree_next(self):
        cdef sddapi_c.SddNode* node = self._sddnode.vtree_next
        return SddNode.wrap(node, self._manager)

    def copy(self, SddManager manager=None):
        """Returns a copy of an SDD, with respect to a new manager dest manager.

        The destination manager, and the manager associated with the SDD to be copied,
        must have copies of the same vtree."""
        cdef sddapi_c.SddManager* dest_manager = self._manager._sddmanager
        if manager is not None:
            dest_manager = manager._sddmanager
        return SddNode.wrap(sddapi_c.sdd_copy(self._sddnode, dest_manager), self._manager)

    @staticmethod
    def _join_models(model1, model2):
        """Concatenate two models.

        :param model1: Dictionary with variable and value assignment
        :type model1: Dict[int, int]
        :param model2: Dictionary with variable assignment
        :type model1: Dict[int, int]

        Assumes that both dictionaries do not share keys.
        """
        model = model1.copy()
        model.update(model2)
        return model

    def models(self, Vtree vtree=None):
        """A generator for the models of an SDD."""
        if self.is_false():
            raise ValueError("False has no models")
        if vtree is None:
            if self.is_true():
                vtree = self.manager.vtree()
            else:
                vtree = self.vtree()
        if vtree.is_leaf():
            var = vtree.var()
            if self.is_true():
                yield {var:0}
                yield {var:1}
            elif self.is_literal():
                sign = 0 if self.literal < 0 else 1
                yield {var:sign}
        else:
            if self.is_true():  # sdd is true
                for left in self.models(vtree.left()):
                    for right in self.models(vtree.right()):
                        yield SddNode._join_models(left,right)
            elif self.vtree() == vtree:
                for prime,sub in self.elements():
                    if sub.is_false(): continue
                    for left in prime.models(vtree.left()):
                        for right in sub.models(vtree.right()):
                            yield SddNode._join_models(left,right)
            else:  # fill in gap in vtree
                true_sdd = self.manager.true()
                if Vtree.is_sub(self.vtree(),vtree.left()):
                    for left in self.models(vtree.left()):
                        for right in true_sdd.models(vtree.right()):
                            yield SddNode._join_models(left,right)
                else:
                   for left in true_sdd.models(vtree.left()):
                        for right in self.models(vtree.right()):
                            yield SddNode._join_models(left,right)

    def wmc(self, log_mode=True):
        """Create a WmcManager to perform Weighted Model Counting with this node as root.

        :param log_mode: Perform the computations in log mode or not (default = True)
        """
        return WmcManager(self, log_mode)


    ## Manual Garbage Collection (Sec 5.4)

    def ref_count(self):
        """Returns the reference count of an SDD node.

        The reference count of a terminal SDD is 0 (terminal SDDs are always live).
        """
        return sddapi_c.sdd_ref_count(self._sddnode)

    def ref(self):
        """References an SDD node if it is not a terminal node.

        Returns the node.
        """
        # TODO: Should we ref every Python SDDNode object on creation and deref on Python GC?
        sddapi_c.sdd_ref(self._sddnode, self._manager._sddmanager)

    def deref(self):
        """Dereferences an SDD node if it is not a terminal node.

        Returns the node. The number of dereferences to a node cannot be larger than the number of its references
        (except for terminal SDD nodes, for which referencing and dereferencing has no effect).
        """
        # TODO: This means the c-pointer might be invalid at one point. Set __sddnode to None?
        sddapi_c.sdd_deref(self._sddnode, self._manager._sddmanager)


    ## File I/O

    def print_ptr(self):
        #cdef long long t = <long long>self._sddnode
        #print(t)
        print("{0:x}".format(<size_t>&self._sddnode))

    def save(self, char* filename):
        return self._manager.save(filename, self)

    def save_as_dot(self, char* filename):
        return self._manager.save_as_dot(filename, self)

    def dot(self):
        return self._manager.dot(self)

    def __str__(self):
        return "SddNode(name={},id={})".format(self._name, self.id)

    def __repr__(self):
        return self.__str__()

    def __format__(self, format_spec):
        if format_spec:
            format = "{:" + format_spec + "}"
            format = format.format(self.__str__())
        else:
            format = self.__str__()
        return format

    def __eq__(SddNode self, SddNode other):
        return self._sddnode == other._sddnode


@cython.embedsignature(True)
cdef class SddManager:
    """Creates a new SDD manager, either given a vtree or using a balanced vtree over the given number of variables.

    :param var_count: Number of variables
    :param auto_gc_and_minimize: Automatic garbage collection
        Automatic garbage collection and automatic SDD minimization are activated in the created manager when
        auto gc and minimize is not 0.
    :param vtree: The manager copies the input vtree. Any manipulations performed by
        the manager are done on its own copy, and does not affect the input vtree.

    The creation and manipulation of SDDs are maintained by an SDD manager.
    The use of an SDD manager is analogous to the use of managers in OBDD packages
    such as CUDD [10]. For a discussion on the design and implementation of such
    systems, see [7].

    To declare an SDD manager, one provides an initial vtree. By declaring an
    initial vtree, we also declare an initial number of variables. See the section
    on creating vtrees, for a few ways to specify an initial vtree.

    Note that variables are referred to by an index. If there are n variables
    in an SDD manager, then the variables are referred to as 1, . . . , n. Literals
    are referred to by signed indices. For example, given the i-th variable, we
    refer to its positive literal by i and its negative literal by −i.
    """
    cdef sddapi_c.SddManager* _sddmanager
    cdef bint _prevent_transformation # Sect 5.2: Transformations with auto_gc_and_minimize can invalidate WMCManager
    cdef CompilerOptions options
    cdef public object root

    ## Creating managers (Sec 5.1.1)

    def __init__(self, long long var_count=1, bint auto_gc_and_minimize=False, Vtree vtree=None):
        pass

    def __cinit__(self, long long var_count=1, bint auto_gc_and_minimize=False, Vtree vtree=None):
        self.options = CompilerOptions()
        self.root = None
        if vtree is not None:
            self._sddmanager = sddapi_c.sdd_manager_new(vtree._vtree)
            if self._sddmanager is NULL:
                raise MemoryError("Could not create SddManager")
            self.auto_gc_and_minimize_off()
        else:
            self._sddmanager = sddapi_c.sdd_manager_create(var_count, auto_gc_and_minimize)
            if self._sddmanager is NULL:
                raise MemoryError("Could not create SddManager")
        # Since 2.0 you have to set options and initialize values to avoid segfault
        self.set_options()
        self._prevent_transformation = False

    def __dealloc__(self):
        if self._sddmanager is not NULL:
            sddapi_c.sdd_manager_free(self._sddmanager)

    @staticmethod
    def from_vtree(Vtree vtree):
        """Creates a new SDD manager, given a vtree.

        The manager copies the input vtree. Any manipulations performed by the manager are done on its own copy,
        and does not aﬀect the input vtree.
        """
        return SddManager(vtree=vtree)
        
    @staticmethod
    cdef wrap(sddapi_c.SddManager* sdd_manager, CompilerOptions options, object root=None):
        """Transform a C SddManager to a Python SddManager.

        :return: Python object for the SddManager
        """
        if sdd_manager == NULL:
            return None
        new_mgr = SddManager(var_count=1, auto_gc_and_minimize=False, vtree=None)
        new_mgr._sddmanager = sdd_manager
        new_mgr.set_options(options)
        new_mgr.root = root
        return new_mgr

    def set_options(self, options=None):
        if options is not None:
            self.options = options
        self.options.copy_options_to_c()
        sddapi_c.sdd_manager_set_options(&self.options._options, self._sddmanager)

    def add_var_before_first(self):
        """Let v be the leftmost leaf node in the vtree. A new leaf node labeled with variable n + 1 is created and
        made a left sibling of leaf v.
        """
        sddapi_c.sdd_manager_add_var_before_first(self._sddmanager)

    def add_var_after_last(self):
        """Let v be the rightmost leaf node in the vtree. A new leaf node labeled with variable n + 1 is created and
        made a right sibling of leaf v.
        """
        sddapi_c.sdd_manager_add_var_after_last(self._sddmanager)

    def add_var_before(self, sddapi_c.SddLiteral target_var):
        """Let v be the vtree leaf node labeled with variable target var. A new leaf node labeled with variable
        n + 1 is created and made a left sibling of leaf v.
        """
        sddapi_c.sdd_manager_add_var_before(target_var, self._sddmanager)

    def add_var_after(self, sddapi_c.SddLiteral target_var):
        """Let v be the vtree leaf node labeled with variable target var. A new leaf node labeled with variable
        n + 1 is created and made a right sibling of leaf v.
        """
        sddapi_c.sdd_manager_add_var_after(target_var, self._sddmanager)


    def add_var_before_lca(self, sddapi_c.SddLiteral[:] literals):
        """
        Let v be the smallest vtree which contains the variables of literals, where count is the number of literals.
        A new leaf node labeled with variable n + 1 is created and made a left sibling of v.
        """
        cdef int count = len(literals)
        sddapi_c.add_var_before_lca(count, &literals[0], self._sddmanager)

    def add_var_after_lca(self, sddapi_c.SddLiteral[:] literals):
        """
        Let v be the smallest vtree which contains the variables of literals, where count is the number of literals.
        A new leaf node labeled with variable n + 1 is created and made a right sibling of v.
        """
        cdef int count = len(literals)
        sddapi_c.add_var_after_lca(count, &literals[0], self._sddmanager)

    def move_var_before_first(self, sddapi_c.SddLiteral var):
        """Let v be the leftmost leaf node in the vtree. The leaf node labeled with variable
        var is moved to become a left sibling of leaf v.
        """
        sddapi_c.move_var_before_first(var, self._sddmanager)

    def move_var_after_last(self, sddapi_c.SddLiteral var):
        """Let v be the rightmost leaf node in the vtree. The leaf node labeled with variable
        var is moved to become a right sibling of leaf v.
        """
        sddapi_c.move_var_after_last(var, self._sddmanager)

    def move_var_before(self, sddapi_c.SddLiteral var, sddapi_c.SddLiteral target_var):
        """Let v be the vtree leaf node labeled with variable target var. The leaf node labeled with variable
        var is moved to become a left sibling of leaf v.
        """
        sddapi_c.move_var_before(var, target_var, self._sddmanager)

    def move_var_after(self, sddapi_c.SddLiteral var, sddapi_c.SddLiteral target_var):
        """Let v be the vtree leaf node labeled with variable target var. The leaf node labeled with variable
        var is moved to become a right sibling of leaf v.
        """
        sddapi_c.move_var_after(var, target_var, self._sddmanager)

    def remove_var_added_last(self):
        """Let v be the vtree leaf node with the variable that was added last to the vtree.
        This leaf is removed from the vtree.
        """
        sddapi_c.remove_var_added_last(self._sddmanager)


    ## Terminal SDDs (Sec 5.1.2)

    def true(self):
        """Returns an SDD representing the function true."""
        return SddNode.wrap(sddapi_c.sdd_manager_true(self._sddmanager), self)

    def false(self):
        """Returns an SDD representing the function false."""
        return SddNode.wrap(sddapi_c.sdd_manager_false(self._sddmanager), self)

    def literal(self, lit):
        """Returns an SDD representing a literal.

        Returns an SDD representing a literal. The variable literal is of the form ±i, where i is an index of
        a variable, which ranges from 1 to the number of variables in the manager. If literal is positive, then
        the SDD representing the positive literal of the i-th variable is returned. If literal is negative, then
        the SDD representing the negative literal is returned.

        :param lit: Literal (integer number)
        """
        if lit == 0:
            raise ValueError("Literal 0 does not exist")
        if lit > self.var_count():
            raise ValueError("Number of available literals is {} < {}".format(self.var_count(), lit))
        cdef long long literal_c = lit
        # if self.is_var_used(literal_c) == 0:
        #     return None # TODO in version 2.0 this is 0 if the variable is not yet in a formula
        return SddNode.wrap(sddapi_c.sdd_manager_literal(literal_c, self._sddmanager), self)

    def l(self, lit):
        """Short for literal(lit)"""
        return self.literal(lit)

    @property
    def vars(self):
        class SddManagerVars:
            def __init__(self, mgr):
                self._i = 1
                self._mgr = mgr

            def __iter__(self):
                return self

            def __next__(self):
                if self._i > self._mgr.var_count():
                    raise StopIteration()
                result = self._mgr.get_vars(self._i)
                self._i += 1
                return result

            def __getitem__(self, value):
                return self._mgr.get_vars(value)
        return SddManagerVars(self)


    def __getitem__(self, value):
        """Python get item syntax to get literals.

        Example: a = mysdd[1]
                 a, b, c = mysdd[1:4]
                 a, c = mysdd[(1,3)]
        """
        return self.get_vars(value)

    def get_vars(self, value):
        try:
            if isinstance(value, collections.abc.Iterable):
                literals = [self.literal(lit) for lit in value]
                return literals

            if type(value) == int:
                literal = self.literal(value)
                return literal

            if type(value) == slice:
                start = value.start if value.start is not None else 1
                stop = value.stop if value.stop is not None else self.var_count()
                step = value.step if value.step is not None else 1
                literals = [self.literal(lit) for lit in range(start, stop, step)]
                return literals

        except ValueError as err:
                raise KeyError(str(err))
        raise KeyError(f"Unknown type of key: {value} ({type(value)})")


    ## Automatic Garbage Collection and SDD Minimization (Sec 5.1.3)

    def auto_gc_and_minimize_on(self):
        """Activates automatic garbage collection and automatic SDD minimization."""
        sddapi_c.sdd_manager_auto_gc_and_minimize_on(self._sddmanager)

    def auto_gc_and_minimize_off(self):
        """Deactivates automatic garbage collection and automatic SDD minimization."""
        sddapi_c.sdd_manager_auto_gc_and_minimize_off(self._sddmanager)

    def is_auto_gc_and_minimize_on(self):
        """Is automatic garbage collection and automatic SDD minimization activated?"""
        cdef int rval = sddapi_c.sdd_manager_is_auto_gc_and_minimize_on(self._sddmanager)
        if rval == 1:
            return True
        return False

    # custom
    def set_prevent_transformation(self, prevent=True):
        """Prevent transformations when prevent=True and self.is_auto_gc_and_minimize_on()=True"""
        self._prevent_transformation = prevent

    def is_prevent_transformation_on(self):
        """Are transformations prevented when self.is_auto_gc_and_minimize_on()=True?"""
        return self._prevent_transformation


    ## Size and Count (Sec 5.1.4)


    ## Misc Functions (Sec 5.1.5)

    def copy(self, nodes):
        """Returns a new SDDManager, while copying the vtree and the SDD nodes of this manager.
        After this operation, the given list of nodes will contain the corresponding nodes in the new manager.
        :param nodes: A list of SddNodes to copy.
        :return: The new SDDManager
        """
        # init
        cdef int size_c = len(nodes)
        cdef sddapi_c.SddNode** nodes_c = <sddapi_c.SddNode**> PyMem_Malloc(size_c * sizeof(sddapi_c.SddNode*))
        if not nodes_c:
            raise MemoryError("Could not create array of SddNodes")
        cdef sddapi_c.SddManager* new_manager_c
        new_manager = None
        try:
            for i in range(0,size_c):
                nodes_c[i] = (<SddNode> nodes[i])._sddnode
            # copy
            new_manager_c = sddapi_c.sdd_manager_copy(size_c, nodes_c, self._sddmanager)
            # wrap results
            new_manager = SddManager.wrap(new_manager_c, options=self.options, root=None)
            for i in range(0,size_c):
                nodes[i] = SddNode.wrap(nodes_c[i], new_manager)
        finally:
            PyMem_Free(nodes_c)
        return new_manager

    def print_stdout(self):
        sddapi_c.sdd_manager_print(self._sddmanager)

    def var_count(self):
        """Returns the number of SDD variables currently associated with the manager."""
        return sddapi_c.sdd_manager_var_count(self._sddmanager)

    def vtree_copy(self):
        return Vtree.wrap(sddapi_c.sdd_manager_vtree_copy(self._sddmanager))

    def vtree(self):
        return Vtree.wrap(sddapi_c.sdd_manager_vtree(self._sddmanager), is_ref=True)

    def vtree_of_var(self, sddapi_c.SddLiteral var):
        """Returns the leaf node of a manager’s vtree, which is associated with var."""
        return Vtree.wrap(sddapi_c.sdd_manager_vtree_of_var(var, self._sddmanager), is_ref=True)

    def lca_of_literals(self, sddapi_c.SddLiteral[:] literals):
        """Returns the smallest vtree which contains the variables of literals, where count is the number of literals.
        
        If we view the variable of each literal as a leaf vtree node, the function will then return
        the lowest common ancestor (lca) of these leaf nodes.
        """
        cdef int count = len(literals)
        return Vtree.wrap(sddapi_c.sdd_manager_lca_of_literals(count, &literals[0], self._sddmanager))

    def is_var_used(self, var):
        """Returns 1 if var is referenced by a decision SDD node (dead or alive); returns 0 otherwise.

        :param var: Literal (number)
        """
        cdef sddapi_c.SddLiteral lit
        if isinstance(var, int):
            lit = var
        elif isinstance(var, SddNode):
            if not var.is_literal():
                raise ValueError("Expected a literal node")
            lit = var.literal
        else:
            raise ValueError("Unexpected type for var: {}".format(type(var)))
        if lit == 0:
            raise ValueError("Literal 0 does not exist")
        return sddapi_c.sdd_manager_is_var_used(lit, self._sddmanager)

    def var_order(self):
        """Return an array var order (whose length will be equal the number of variables in the manager)
        with the left-to-right variable ordering of the manager’s vtree.
        """
        cdef array.array var_order = array.array('q', [0]*self.var_count())
        sddapi_c.sdd_manager_var_order(var_order.data.as_longlongs, self._sddmanager)
        return var_order

    ## Queries and Transformations (Sec 5.2.1)
    # To avoid invalidating a WMC manager, the user should refrain from performing the SDD operations of Section 5.2.1
    # when auto garbage collection and SDD minimization is active.

    def apply(self, SddNode node1, SddNode node2, sddapi_c.BoolOp op):
        """Returns the result of combining two SDDs, where op can be CONJOIN (0) or DISJOIN (1)."""
        if self.is_prevent_transformation_on() and self.is_auto_gc_and_minimize_on():
            raise EnvironmentError("Transformation is not allowed when prevent_transformation and auto garbage "
                                   "collection and SDD minimization is active")
        return SddNode.wrap(sddapi_c.sdd_apply(node1._sddnode, node2._sddnode, op, self._sddmanager), self)

    def conjoin(self, SddNode node1, SddNode node2):
        """Returns the result of applying the corresponding Boolean operation on the given SDDs."""
        if self.is_prevent_transformation_on() and self.is_auto_gc_and_minimize_on():
            raise EnvironmentError("Transformation is not allowed when prevent_transformation and auto garbage "
                                   "collection and SDD minimization is active")
        return SddNode.wrap(sddapi_c.sdd_conjoin(node1._sddnode, node2._sddnode, self._sddmanager), self)

    def disjoin(self, SddNode node1, SddNode node2):
        """Returns the result of applying the corresponding Boolean operation on the given SDDs."""
        if self.is_prevent_transformation_on() and self.is_auto_gc_and_minimize_on():
            raise EnvironmentError("Transformation is not allowed when prevent_transformation and auto garbage "
                                   "collection and SDD minimization is active")
        return SddNode.wrap(sddapi_c.sdd_disjoin(node1._sddnode, node2._sddnode, self._sddmanager), self)

    def negate(self, SddNode node):
        """Returns the result of applying the corresponding Boolean operation on the given SDDs."""
        if self.is_prevent_transformation_on() and self.is_auto_gc_and_minimize_on():
            raise EnvironmentError("Transformation is not allowed when prevent_transformation and auto garbage "
                                   "collection and SDD minimization is active")
        return SddNode.wrap(sddapi_c.sdd_negate(node._sddnode, self._sddmanager), self)

    def condition(self, lit, SddNode node):
        """Returns the result of conditioning an SDD on a literal, where a literal is a positive or negative integer."""
        cdef sddapi_c.SddLiteral lit_int
        if type(lit) == int:
            lit_int = lit
        elif isinstance(lit, SddNode):
            if lit.is_literal():
                lit_int = lit.literal
            else:
                raise ValueError(f"SddNode needs to represent a literal")
        else:
            raise TypeError(f"Incorrect literal type ({type(lit)}), expects int or an SddNode")
        return SddNode.wrap(sddapi_c.sdd_condition(lit_int, node._sddnode, self._sddmanager), self)

    def exists(self, sddapi_c.SddLiteral var, SddNode node):
        """Returns the result of existentially (universally) quantifying out a variable from an SDD."""
        return SddNode.wrap(sddapi_c.sdd_exists(var, node._sddnode, self._sddmanager), self)

    def forall(self, sddapi_c.SddLiteral var, SddNode node):
        """Returns the result of existentially (universally) quantifying out a variable from an SDD."""
        return SddNode.wrap(sddapi_c.sdd_forall(var, node._sddnode, self._sddmanager), self)

    def exists_multiple(self, int[:] exists_map, SddNode node):
        """Returns the result of existentially quantifying out a set of variables from an SDD.

        This function is expected to be more efficient than existentially quantifying out variables one
        at a time. The array exists map speciﬁes the variables to be existentially quantiﬁed out.
        The length of exists map is expected to be n + 1, where n is the number of variables in the
        manager. exists map[i] should be 1 if variable i is to be quantiﬁed out; otherwise, exists
        map[i] should be 0. exists map[0] is unused.
        """
        if len(exists_map) != self.var_count() + 1:
            raise ValueError(f"Length exists_map is expected to be equal to the number of variables "
                             f"in the manager ({self.var_count() + 1}) but {len(exists_map)} is given.")
        return SddNode.wrap(sddapi_c.sdd_exists_multiple(&exists_map[0], node._sddnode, self._sddmanager), self)

    def exists_multiple_static(self, int[:] exists_map, SddNode node):
        """This is the same as sdd exists multiple, except that SDD minimization is never performed when
        quantifying out variables.

        This can be more eﬃcient than deactivating automatic SDD minimization and calling sdd exists multiple.

        A model of an SDD is a truth assignment of the SDD variables which also satisﬁes the SDD. The
        cardinality of a truth assignment is the number of variables assigned the value true. An SDD may
        not mention all variables in the SDD manager. An SDD model can be converted into a global model
        by including the missing variables, while setting their values arbitrarily.
        """
        if len(exists_map) != self.var_count() + 1:
            raise ValueError(f"Length exists_map is expected to be equal to the number of variables "
                             f"in the manager ({self.var_count() + 1}) but {len(exists_map)} is given.")
        return SddNode.wrap(sddapi_c.sdd_exists_multiple_static(&exists_map[0], node._sddnode, self._sddmanager), self)

    def minimize_cardinality(self, SddNode node):
        """Returns the SDD whose models are the minimum-cardinality models of the given SDD
        (i.e. with respect to the SDD variables).
        """
        rnode = SddNode.wrap(sddapi_c.sdd_minimize_cardinality(node._sddnode, self._sddmanager), self)
        self.root = rnode
        return rnode

    def global_minimize_cardinality(self, SddNode node):
        """Returns the SDD whose models are the minimum-cardinality global models of the given SDD
        (i.e., with respect to the manager variables).
        """
        rnode = SddNode.wrap(sddapi_c.sdd_global_minimize_cardinality(node._sddnode, self._sddmanager), self)
        self.root = rnode
        return rnode

    def minimum_cardinality(self, SddNode node):
        """Returns the minimum-cardinality of an SDD.

        The smallest cardinality attained by any of its models. The minimum-cardinality of an SDD is the
        same whether or not we consider the global models of the SDD.
        """
        return sddapi_c.sdd_minimum_cardinality(node._sddnode)

    def model_count(self, SddNode node):
        """Returns the model count of an SDD (i.e., with respect to the SDD variables)."""
        return sddapi_c.sdd_model_count(node._sddnode, self._sddmanager)

    def global_model_count(self, SddNode node):
        """Returns the global model count of an SDD (i.e., with respect to the manager variables)."""
        return sddapi_c.sdd_global_model_count(node._sddnode, self._sddmanager)

    def rename_variables(self, SddNode node, sddapi_c.SddLiteral[:] variable_map):
        """Returns an SDD which is obtained by renaming variables in the SDD node.  The array variable_map has size n+1, where n is the number of variables in the manager.  A variable i, 1 <= i <= n, that appears in the given SDD is renamed into variable variable_map[i] (variable_map[0] is not used)."""

        if len(variable_map) != self.var_count() + 1:
            raise ValueError(f"Length variable_map is expected to be equal to the number of variables "
                             f"in the manager ({self.var_count() + 1}) but {len(variable_map)} is given.")
        return SddNode.wrap(sddapi_c.sdd_rename_variables(node._sddnode, &variable_map[0], self._sddmanager), self)


    ## Size and Count (Sec 5.2.2 and Sec 5.1.4)

    def size(self):
        """Returns the size of all SDD nodes in the manager."""
        return sddapi_c.sdd_manager_size(self._sddmanager)

    def count(self):
        """Returns the node count of all SDD nodes in the manager."""
        return sddapi_c.sdd_manager_count(self._sddmanager)

    def live_size(self):
        """Returns the size of all live SDD nodes in the manager."""
        return sddapi_c.sdd_manager_live_size(self._sddmanager)

    def dead_size(self):
        """Returns the size of all dead SDD nodes in the manager."""
        return sddapi_c.sdd_manager_dead_size(self._sddmanager)

    def live_count(self):
        """Returns the node count of all live SDD nodes in the manager."""
        return sddapi_c.sdd_manager_live_count(self._sddmanager)

    def dead_count(self):
        """Returns the node count of all dead SDD nodes in the manager."""
        return sddapi_c.sdd_manager_dead_count(self._sddmanager)


    ## File I/O (Sec 5.2.3)

    def save_as_dot(self, char* filename, SddNode node):
        """Saves an SDD to ﬁle, formatted for use with Graphviz dot."""
        sddapi_c.sdd_save_as_dot(filename, node._sddnode)

    def shared_save_as_dot(self, char* filename):
        """Saves the SDD of the manager’s vtree (a shared SDD), formatted for use with Graphviz dot."""
        sig_on()
        sddapi_c.sdd_shared_save_as_dot(filename, self._sddmanager)
        sig_off()

    def read_sdd_file(self, char* filename):
        """Reads an SDD from ﬁle.

        The read SDD is guaranteed to be equivalent to the one in the ﬁle, but may have a diﬀerent
        structure depending on the current vtree of the manager. SDD minimization will not be
        performed when reading an SDD from ﬁle, even if auto SDD minimization is active.
        """
        return SddNode.wrap(sddapi_c.sdd_read(filename, self._sddmanager), self)

    def save(self, char* filename, SddNode node):
        """Saves an SDD to ﬁle.

        Typically, one also saves the corresponding vtree to ﬁle. This allows one to read the SDD
        back using the same vtree.
        """
        sddapi_c.sdd_save(filename, node._sddnode)

    def dot(self, SddNode node=None):
        """SDD for the given node, formatted for use with Graphviz dot."""
        if node is None:
            return self.dot_shared()
        fname = None
        cdef bytes fname_b
        cdef char* fname_c
        result = None
        with tempfile.TemporaryDirectory() as tmpdirname:
            fname = os.path.join(tmpdirname, "sdd.dot")
            fname_b = fname.encode()
            fname_c = fname_b
            self.save_as_dot(fname_c, node)
            with open(fname, "r") as ifile:
                result = ifile.read()
        return result

    def dot_shared(self):
        """Shared SDD, formatted for use with Graphviz dot."""
        fname = None
        cdef bytes fname_b
        cdef char* fname_c
        result = None
        with tempfile.TemporaryDirectory() as tmpdirname:
            fname = os.path.join(tmpdirname, "sdd.dot")
            fname_b = fname.encode()
            fname_c = fname_b
            self.shared_save_as_dot(fname_c)
            with open(fname, "r") as ifile:
                result = ifile.read()
        return result

    # Read CNF

    @staticmethod
    def from_cnf_file(char* filename, char* vtree_type="balanced"):
        """Create an SDD from the given CNF file."""
        cdef Fnf cnf = Fnf.from_cnf_file(filename)
        return SddManager.from_fnf(cnf, vtree_type)

    def read_cnf_file(self, filename):
        """Replace the SDD by an SDD representing the theory in the given CNF file."""
        cdef Fnf cnf = Fnf.from_cnf_file(filename)
        return self.fnf_to_sdd(cnf)

    @staticmethod
    def from_cnf_string(cnf, char* vtree_type="balanced"):
        """Create an SDD from the given CNF string."""
        with tempfile.TemporaryDirectory() as tmpdirname:
            fname = os.path.join(tmpdirname, "program.cnf")
            fname_b = fname.encode()
            fname_c = fname_b
            with open(fname, "w") as ofile:
                ofile.write(cnf)
            return SddManager.from_cnf_file(fname_c, vtree_type)
        return None, None


    # Read DNF

    @staticmethod
    def from_dnf_file(char* filename, char* vtree_type="balanced"):
        """Create an SDD from the given DNF file."""
        cdef Fnf dnf = Fnf.from_dnf_file(filename)
        return SddManager.from_fnf(dnf, vtree_type)

    def read_dnf_file(self, filename):
        """Replace the SDD by an SDD representing the theory in the given DNF file."""
        cdef Fnf dnf = Fnf.from_dnf_file(filename)
        return self.fnf_to_sdd(dnf)

    @staticmethod
    def from_dnf_string(dnf, char* vtree_type="balanced"):
        """Create an SDD from the given DNF string."""
        with tempfile.TemporaryDirectory() as tmpdirname:
            fname = os.path.join(tmpdirname, "program.dnf")
            fname_b = fname.encode()
            fname_c = fname_b
            with open(fname, "w") as ofile:
                ofile.write(dnf)
            return SddManager.from_dnf_file(fname_c, vtree_type)
        return None, None


    # Read FNF

    @staticmethod
    def from_fnf(Fnf fnf, char* vtree_type="balanced"):
        """Create an SDD from the given DNF file."""
        vtree = Vtree(var_count=fnf.var_count, vtree_type=vtree_type)
        mgr = SddManager(vtree=vtree)
        mgr.auto_gc_and_minimize_off()  # Having this on while building triggers segfault
        # cli.initialize_manager_search_state(self._sddmanager)  # not required anymore in 2.0?
        # TODO: Add interruption to compilation (e.g. for timeouts)
        rnode = SddNode.wrap(compiler_c.fnf_to_sdd(fnf._fnf, mgr._sddmanager), mgr)
        mgr.root = rnode
        # mgr.auto_gc_and_minimize_off()
        return mgr, rnode


    def fnf_to_sdd(self, Fnf fnf):
        rnode = SddNode.wrap(compiler_c.fnf_to_sdd(fnf._fnf, self._sddmanager), self)
        return rnode


    ## Manual Garbage Collection (Sec 5.4)

    def garbage_collect(self):
        """Performs a global garbage collection: Claims all dead SDD nodes in the manager.
        """
        sddapi_c.sdd_manager_garbage_collect(self._sddmanager)


    ## Manual SDD Minimization (Sec 5.5)

    def minimize(self):
        # type: (SddManager) -> str
        """Performs global garbage collection and then tries to minimize the size of a manager’s SDD.

        This function calls sdd vtree search on the manager’s vtree.

        To allow for a timeout, this function can be interrupted by the keyboard interrupt (SIGINT).
        """
        f = io.StringIO()
        with redirect_stdout(f):
            sig_on()
            sddapi_c.sdd_manager_minimize(self._sddmanager)
            sig_off()
        s = f.getvalue()
        return s

    def vtree_minimize(self, Vtree vtree):
        """Performs local garbage collection on vtree and then tries to minimize the size of the SDD of
        vtree by searching for a diﬀerent vtree. Returns the root of the resulting vtree.
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_minimize(vtree._vtree, self._sddmanager))

    def minimize_limited(self):
        sddapi_c.sdd_manager_minimize_limited(self._sddmanager)

    def init_vtree_size_limit(self, Vtree vtree):
        sddapi_c.sdd_manager_init_vtree_size_limit(vtree._vtree, self._sddmanager)

    def update_vtree_size_limit(self):
        sddapi_c.sdd_manager_update_vtree_size_limit(self._sddmanager)

    def set_vtree_search_convergence_threshold(self, float threshold):
        sddapi_c.sdd_manager_set_vtree_search_convergence_threshold(threshold, self._sddmanager)

    def set_vtree_search_time_limit(self, clock_t time_limit):
        """Set the time limits for the vtree search algorithm.

        A vtree operation is either a rotation or a swap. Times are in seconds and correspond to CPU time.
        Default values, in order, are 180, 60, 30, and 10 seconds.
        """
        sddapi_c.sdd_manager_set_vtree_search_time_limit(time_limit, self._sddmanager)

    def set_vtree_fragment_time_limit(self, clock_t time_limit):
        """Set the time limits for the vtree search algorithm.

        A vtree operation is either a rotation or a swap. Times are in seconds and correspond to CPU time.
        Default values, in order, are 180, 60, 30, and 10 seconds.
        """
        sddapi_c.sdd_manager_set_vtree_fragment_time_limit(time_limit, self._sddmanager)

    def set_vtree_operation_time_limit(self, clock_t time_limit):
        """Set the time limits for the vtree search algorithm.

        A vtree operation is either a rotation or a swap. Times are in seconds and correspond to CPU time.
        Default values, in order, are 180, 60, 30, and 10 seconds.
        """
        sddapi_c.sdd_manager_set_vtree_operation_time_limit(time_limit, self._sddmanager)

    def set_vtree_apply_time_limit(self, clock_t time_limit):
        """Set the time limits for the vtree search algorithm.

        A vtree operation is either a rotation or a swap. Times are in seconds and correspond to CPU time.
        Default values, in order, are 180, 60, 30, and 10 seconds.
        """
        sddapi_c.sdd_manager_set_vtree_apply_time_limit(time_limit, self._sddmanager)

    def set_vtree_operation_memory_limit(self, float memory_limit):
        """Sets the relative memory limit for rotation and swap operations. Default value is 3.0."""
        sddapi_c.sdd_manager_set_vtree_operation_memory_limit(memory_limit, self._sddmanager)

    def set_vtree_operation_size_limit(self, float size_limit):
        """Sets the relative size limit for rotation and swap operations.

        Default value is 1.2. A size limit l is relative to the size s of an SDD for a given vtree
        (s is called the reference size). Hence, using this size limit requires calling the following
        functions to set and update the reference size s, otherwise the behavior is not deﬁned.
        """
        sddapi_c.sdd_manager_set_vtree_operation_size_limit(size_limit, self._sddmanager)

    def init_vtree_size_limit(self, Vtree vtree):
        """Declares the size s of current SDD for vtree as the reference size for the relative size limit l.

        That is, a rotation or swap operation will fail if the SDD size grows to larger than s × l.
        """
        sddapi_c.sdd_manager_init_vtree_size_limit(vtree._vtree, self._sddmanager)

    def update_vtree_size_limit(self):
        """Updates the reference size for relative size limits.

        It is preferrable to invoke this function, as it is more eﬃcent than the function sdd manager
        init vtree size limit as it does not directly recompute the size of vtree.
        """
        sddapi_c.sdd_manager_update_vtree_size_limit(self._sddmanager)

    def set_vtree_cartesian_product_limit(self, sddapi_c.SddSize size_limit):
        """Sets the absolute size limit on the size of a cartesian product for right rotation and swap operations.

        Default value is 8, 192.
        """
        sddapi_c.sdd_manager_set_vtree_cartesian_product_limit(size_limit, self._sddmanager)


    ## Printing

    def __str__(self):
        """Prints various statistics that are collected by the SDD manager."""
        f = io.StringIO()
        with redirect_stderr(f):
            sddapi_c.sdd_manager_print(self._sddmanager)
        return f.getvalue()


cdef class Fnf:
    cdef compiler_c.Fnf* _fnf
    cdef public bint _type_cnf
    cdef public bint _type_dnf

    def __cinit__(self):
        self._type_cnf = False
        self._type_dnf = False

    def __dealloc__(self):
        if self._fnf is not NULL:
            fnf_c.free_fnf(self._fnf)

    @staticmethod
    cdef wrap(compiler_c.Fnf* fnf, cnf=False, dnf=False):
        rfnf = Fnf()
        rfnf._fnf = fnf
        return rfnf

    @property
    def var_count(self):
        return self._fnf.var_count

    @property
    def litset_count(self):
        return self._fnf.litset_count


    ## CNF/DNF to SDD Compiler (Sec 6)

    def read_cnf(self, char* filename):
        self._fnf =  io_c.read_cnf(filename)
        self._type_cnf = True
        print("Read CNF: vars={} clauses={}".format(self.var_count, self.litset_count))

    @staticmethod
    def from_cnf_file(char* filename):
        fnf = Fnf.wrap(io_c.read_cnf(filename))
        fnf._type_cnf = True
        print("Read CNF: vars={} clauses={}".format(fnf.var_count, fnf.litset_count))
        return fnf

    def read_dnf(self, char* filename):
        self._fnf =  io_c.read_dnf(filename)
        self._type_dnf = True
        print("Read CNF: vars={} clauses={}".format(self.var_count, self.litset_count))

    @staticmethod
    def from_dnf_file(char* filename):
        fnf = Fnf.wrap(io_c.read_dnf(filename))
        fnf._type_dnf = True
        print("Read CNF: vars={} clauses={}".format(fnf.var_count, fnf.litset_count))
        return fnf


@cython.embedsignature(True)
cdef class Vtree:
    """Returns a vtree over a given number of variables.

    :param var_count: Number of variables
    :param vtree_type: The type of a vtree may be "right" (right linear), "left" (left linear), "vertical", "balanced",
        or "random".
    :param var_order: The left-to-right variable ordering is given in array var_order. The contents of array
        var_order must be a permutation of the integers from 1 to var count.
    :param is_X_var: The constrained variables X, specified as an array of size var_count+1.
        For variables i where 1 =< i =< var_count,
        if is_X_var[i] is 1 then i is an element of X,
        and if it is 0 then i is not an element of X.
    :param filename: The name of the file from which to create a vtree.
    :return: A vtree
    """
    cdef sddapi_c.Vtree* _vtree
    cdef public bint is_ref  # Ref does not manage memory

    ## Creating Vtrees (Sec 5.3.1)

    def __init__(self, var_count=None, var_order=None, vtree_type="balanced", filename=None, is_X_var=None):
        pass

    def __cinit__(self, var_count=None, var_order=None, vtree_type="balanced", filename=None, is_X_var=None):
        cdef long long[:] var_order_c
        cdef long long[:] is_X_var_c
        cdef long long var_count_c
        cdef char* vtree_type_c
        cdef char* filename_c
        self.is_ref = False
        if type(vtree_type) == str:
            vtree_type = vtree_type.encode()
            vtree_type_c = vtree_type
        elif type(vtree_type) == bytes:
            vtree_type_c = vtree_type
        else:
            raise ValueError("Invalid type for vtree_type")
        #cdef bytes type_b = type.encode()
        #cdef char* type_c = type_b
        if var_count is not None and filename is not None:
            raise ValueError("Error: Arguments var_count and filename cannot be given together")
        elif var_count is not None:
            var_count_c = var_count

            if var_order is not None and is_X_var is not None:
                raise ValueError("Error: Arguments var_order and is_X_var cannot be given together")
            elif var_order is None and is_X_var is None: # new
                self._vtree = sddapi_c.sdd_vtree_new(var_count_c, vtree_type_c)
            elif var_order is None and is_X_var is not None: # new_X_constrained
                if isinstance(is_X_var, array.array):
                    is_X_var_c = is_X_var
                else:
                    is_X_var_c = array.array('q', is_X_var)

                self._vtree = sddapi_c.sdd_vtree_new_X_constrained(var_count_c, &is_X_var_c[0], vtree_type_c)
                if self._vtree is NULL:
                    raise MemoryError("Could not create Vtree")
            else: # new_with_var_order
                if isinstance(var_order, array.array):
                    var_order_c = var_order
                else:
                    var_order_c = array.array('q', var_order)

                self._vtree = sddapi_c.sdd_vtree_new_with_var_order(var_count_c, &var_order_c[0], vtree_type_c)
                if self._vtree is NULL:
                    raise MemoryError("Could not create Vtree")
        elif filename is not None:
            if type(filename) == str:
                filename = filename.encode()
                filename_c = filename
            elif type(filename) == bytes:
                filename_c = filename
            else:
                raise ValueError("Unknown type for filename: " + str(type(filename)))
            self._vtree = sddapi_c.sdd_vtree_read(filename_c)
            if self._vtree is NULL:
                raise MemoryError("Could not create Vtree")

    def __dealloc__(self):
        """Frees the memory of a vtree."""
        if not self.is_ref and self._vtree is not NULL:
            sddapi_c.sdd_vtree_free(self._vtree)

    def __eq__(Vtree self, Vtree other):
        return self._vtree == other._vtree

    def get_sdd_nodes(self, SddManager manager):
        """List of SDD nodes normalized for vtree.

        Only two sdd nodes for leaf vtrees: first is positive literal, second is negative literal.

        :param manager: SddManager associated with this Vtree
        :return: List of SddNodes
        """
        nodes = []
        cur_node = SddNode.wrap(self._vtree.nodes, manager)  # TODO: can we get manager from node?
        if cur_node is None:
            return nodes
        while cur_node is not None:
            nodes.append(cur_node)
            cur_node = cur_node.vtree_next()
        return nodes

    def get_sdd_rootnodes(self, SddManager manager):
        """List of SDD nodes that are a root for the shared SDD.

        :param manager: SddManager associated with this Vtree
        :return: List of SddNodes
        """
        nodes = self.get_sdd_nodes(manager)
        if len(nodes) == 0:
            left = self.left()
            if left is not None:
                nodes += left.get_sdd_rootnodes(manager)
            right = self.right()
            if right is not None:
                nodes += right.get_sdd_rootnodes(manager)
        return nodes

    @staticmethod
    def from_file(filename):
        """Create Vtree from file."""
        return Vtree(filename=filename)

    @staticmethod
    def new_with_var_order(var_count, var_order, vtree_type):
        """Returns a vtree over a given number of variables (var_count), whose left-to-right variable ordering is
        given in array var_order.

        :param var_count: Number of variables
        :param var_order: The left-to-right variable ordering. The contents of the array must be a permutation of the
            integers from 1 to var count.
        :param vtree_type: The type of a vtree may be "right" (right linear), "left" (left linear), "vertical",
        "balanced", or "random"
        :return: a vtree ordered according to var_order
        """
        return Vtree(var_count=var_count, var_order=var_order, vtree_type=vtree_type)

    @staticmethod
    def new_with_X_constrained(var_count, is_X_var, vtree_type):
        """Returns an X-constrained vtree over a given number of variables (var_count).

        :param var_count: Number of variables
        :param is_X_var: The constrained variables X, specified as an array of size var_count+1.
            For variables i where 1 =< i =< var_count,
            if is_X_var[i] is 1 then i is an element of X,
            and if it is 0 then i is not an element of X.
        :param vtree_type: The type of a vtree may be "right" (right linear), "left" (left linear), "vertical",
        "balanced", or "random".
        :return: an X-constrained vTree
        """
        return Vtree(var_count=var_count, is_X_var=is_X_var, vtree_type=vtree_type)

    @staticmethod
    cdef wrap(sddapi_c.Vtree* vtree, is_ref=False):
        """Transform a C Vtree to a Python Vtree.
        
        :param vtree: C-pointer to vtree
        :param is_ref: True if memory should not be managed by this Python object
        :return: Python object for Vtree
        """
        if vtree == NULL:
            return None
        rvtree = Vtree()
        rvtree._vtree = vtree
        rvtree.is_ref = is_ref
        return rvtree


    ## Size and Count (Sec 5.3.2)

    def size(self):
        """Returns the size (live+dead) of all SDD nodes in the vtree.

        :return: size
        """
        return sddapi_c.sdd_vtree_size(self._vtree)

    def live_size(self):
        """Returns the size (live only) of all SDD nodes in the vtree.

        :return: size
        """
        return sddapi_c.sdd_vtree_live_size(self._vtree)

    def dead_size(self):
        """Returns the size (dead only) of all SDD nodes in the vtree.

        :return: size
        """
        return sddapi_c.sdd_vtree_dead_size(self._vtree)

    def count(self):
        """Returns the node count (live+dead) of all SDD nodes in the vtree.

        :return: count
        """
        return sddapi_c.sdd_vtree_count(self._vtree)

    def live_count(self):
        """Returns the node count (live only) of all SDD nodes in the vtree.

        :return: count
        """
        return sddapi_c.sdd_vtree_live_count(self._vtree)

    def dead_count(self):
        """Returns the node count (dead only) of all SDD nodes in the vtree.

        :return: count
        """
        return sddapi_c.sdd_vtree_dead_count(self._vtree)

    def size_at(self):
        """Returns the size of all SDD nodes normalized for a vtree node
        (the root where this Vtree points at).

        For example, Vtree.size(vtree) returns the sum of Vtree.size_at(v)
        where v ranges over all nodes of vtree.

        :return: size
        """
        return sddapi_c.sdd_vtree_size_at(self._vtree)

    def live_size_at(self):
        return sddapi_c.sdd_vtree_live_size_at(self._vtree)

    def dead_size_at(self):
        return sddapi_c.sdd_vtree_dead_size_at(self._vtree)

    def count_at(self):
        """Returns the node count of all SDD nodes normalized for a vtree node
        (the root where this Vtree points at).

        For example, Vtree.size(vtree) returns the sum of Vtree.size_at(v)
        where v ranges over all nodes of vtree.

        :return: size
        """
        return sddapi_c.sdd_vtree_count_at(self._vtree)

    def live_count_at(self):
        return sddapi_c.sdd_vtree_live_count_at(self._vtree)

    def dead_count_at(self):
        return sddapi_c.sdd_vtree_dead_count_at(self._vtree)


    ## File I/O (Sec 5.3.3)

    def save(self, char* filename):
        """Saves a vtree to file."""
        sddapi_c.sdd_vtree_save(filename, self._vtree)

    def read(self, char* filename):
        """Reads a vtree from file."""
        cdef sddapi_c.Vtree* vtree_ptr = sddapi_c.sdd_vtree_read(filename)
        self._vtree = vtree_ptr

    def save_as_dot(self, char* filename):
        sddapi_c.sdd_vtree_save_as_dot(filename, self._vtree)

    def dot(self):
        """Vtree to Graphiv dot string."""
        fname = None
        cdef bytes fname_b
        cdef char* fname_c
        result = None
        with tempfile.TemporaryDirectory() as tmpdirname:
            fname = os.path.join(tmpdirname, "vtree.dot")
            fname_b = fname.encode()
            fname_c = fname_b
            self.save_as_dot(fname_c)
            with open(fname, "r") as ifile:
                result = ifile.read()
        return result

    ## Navigation (Sec 5.3.4)

    def is_leaf(self):
        """Returns 1 if vtree is a leaf node, and 0 otherwise."""
        return sddapi_c.sdd_vtree_is_leaf(self._vtree)

    def left(self):
        """Returns the left child of a vtree node
        (returns NULL if the vtree is a leaf node).
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_left(self._vtree), is_ref=True)

    def right(self):
        """Returns the right child of a vtree node
        (returns NULL if the vtree is a leaf node).
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_right(self._vtree), is_ref=True)

    def parent(self):
        """Returns the parent of a vtree node
        (return NULL if the vtree is a root node).
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_parent(self._vtree), is_ref=True)

    def root(self):
        parent = self.parent()
        if parent is None:
            return self
        return parent.root()

    ## Edit Operations (Sec 5.3.5)

    def rotate_left(self, SddManager sddmanager, int limited):
        """Rotates a vtree node left, given time and size limits.

        Time and size limits, among others, are enforced when limited is set to 1; if limited is set to 0,
        limits are deactivated.
        Returns 1 if the operation succeeds and 0 otherwise (i.e., limits exceeded).
        This operation assumes no dead SDD nodes inside or above vtree and does not introduce any new dead SDD nodes.
        """
        return sddapi_c.sdd_vtree_rotate_left(self._vtree, sddmanager._sddmanager, limited)

    def rotate_right(self, SddManager sddmanager, int limited):
        """Rotates a vtree node right, given time, size and cartesian-product limits.

        Time and size limits, among others, are enforced when limited is set to 1; if limited is set to 0,
        limits are deactivated.
        Returns 1 if the operation succeeds and 0 otherwise (i.e., limits exceeded).
        This operation assumes no dead SDD nodes inside or above vtree and does not introduce any new dead SDD nodes.
        """
        return sddapi_c.sdd_vtree_rotate_right(self._vtree, sddmanager._sddmanager, limited)

    def swap(self, SddManager sddmanager, int limited):
        """Swaps the children of a vtree node, given time, size and cartesian-product limits.

        Time and size limits, among others, are enforced when limited is set to 1; if limited is set to 0,
        limits are deactivated.
        Returns 1 if the operation succeeds and 0 otherwise (i.e., limits exceeded).
        This operation assumes no dead SDD nodes inside or above vtree and does not introduce any new dead SDD nodes.

        A size limit is interpreted using a context which consists of two elements. First, a vtree v which is used to
        define the live SDD nodes whose size is to be constrained by the limit. Second, an initial size s to be used
        as a reference point when measuring the amount of size increase. That is, a limit l will constrain the size
        of live SDD nodes in vtree v to <= l * s.
        """
        return sddapi_c.sdd_vtree_swap(self._vtree, sddmanager._sddmanager, limited)


    ## Misc Functions (Sec 5.3.7)

    @staticmethod
    def is_sub(Vtree vtree1, Vtree vtree2):
        """Returns 1 if vtree1 is a sub-vtree of vtree2 and 0 otherwise."""
        cdef bint rval
        rval = sddapi_c.sdd_vtree_is_sub(vtree1._vtree, vtree2._vtree)
        return rval

    @staticmethod
    def lca(Vtree vtree1, Vtree vtree2, Vtree root):
        """Returns the lowest common ancestor (lca) of vtree nodes vtree1 and vtree2, assuming that root is a common
        ancestor of these two nodes.
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_lca(vtree1._vtree, vtree2._vtree, root._vtree))

    def var_count(self):
        # type: () -> int
        """Returns the number of variables contained in the vtree."""
        return sddapi_c.sdd_vtree_var_count(self._vtree)

    def var(self):
        # type: () -> int
        """Returns the variable associated with a vtree node.

         If the vtree node is a leaf, and returns 0 otherwise.

         :return: variable
         """
        return sddapi_c.sdd_vtree_var(self._vtree)

    def position(self):
        """Returns the position of a given vtree node in the vtree inorder.

        Position indices start at 0.
        """
        return sddapi_c.sdd_vtree_position(self._vtree)

    def location(self, SddManager manager):
        """Returns the location of the pointer to the vtree root.

        This location can be used to access the new root of the vtree, which may have changed due to rotating some
        of the vtree nodes.
        """
        # cdef Vtree** vtreepp;
        sddapi_c.sdd_vtree_location(self._vtree, manager._sddmanager)
        # TODO: Pointer Pointer not supported by Cython. Is this function really necessary?


    ## Manual SDD Minimization (Sec 5.5)

    def minimize(self, SddManager manager):
        """Performs local garbage collection on vtree and then tries to minimize the size of the SDD of
        vtree by searching for a different vtree. Returns the root of the resulting vtree.
        """
        return Vtree.wrap(sddapi_c.sdd_vtree_minimize(self._vtree, manager._sddmanager))

    def init_vtree_size_limit(self, SddManager manager):
        """Declares the size s of current SDD for vtree as the reference size for the relative size limit l.

        That is, a rotation or swap operation will fail if the SDD size grows to larger than s × l.
        """
        sddapi_c.sdd_manager_init_vtree_size_limit(self._vtree, manager._sddmanager)


@cython.embedsignature(True)
cdef class WmcManager:
    """Creates a WMC manager for the SDD rooted at node and initializes literal weights.

    When log mode =6 0, all
    computations done by the manager will be in natural log-space. Literal weights are initialized to 0 in
    log-mode and to 1 otherwise. A number of functions are given below for passing values to, or recovering
    values from, a WMC manager. In log-mode, all these values are in natural logs. Finally, a WMC manager may
    become invalid if garbage collection or SDD minimization takes place.

    Note: To avoid invalidating a WMC manager, the user should refrain from performing the SDD operations like
    queries and transformations when auto garbage collection and SDD minimization is active. For this reason,
    the WMCManager will set the prevent_transformation flag on the SDDManager. This prevents transformations on the
    SDDManager when auto_gc_and_minize is on. When the WMCManager is not used anymore,
    Sddmanager.set_prevent_transformations(prevent=False) can be executed to re-allow transformations.

    Background:

    Weighted model counting (WMC) is performed with respect to a given SDD and literal weights, and is based on
    the following definitions:

    * The weight of a variable instantiation is the product of weights assigned to its literals.
    * The weighted model count of the SDD is the sum of weights attained by its models. Here, a model is an
      instantiation (of all variables in the manager) that satisfies the SDD.
    * The weighted model count of a literal is the sum of weights attained by its models that are also models of
      the given SDD.
    * The probability of a literal is the ratio of its weighted model count over the one for the given SDD.

    To facilitate the computation of weighted model counts with respect to changing literal weights, a WMC manager
    is created for the given SDD. This manager stores the weights of literals, allowing one to change them, and
    to recompute the corresponding weighted model count each time the weights change.
    """
    cdef sddapi_c.WmcManager* _wmcmanager
    cdef public SddNode node

    ## Weighted Model Counting (Sec 5.6)

    def __init__(self, SddNode node, bint log_mode=1):
        pass

    def __cinit__(self, SddNode node, bint log_mode=1):
        self._wmcmanager = sddapi_c.wmc_manager_new(node._sddnode, log_mode, node._manager._sddmanager)
        self.node = node
        node._manager.set_prevent_transformation(prevent=True)
        if self._wmcmanager is NULL:
            raise MemoryError()

    def __dealloc__(self):
        if self._wmcmanager is not NULL:
            sddapi_c.wmc_manager_free(self._wmcmanager)

    @property
    def zero_weight(self):
        """Returns -inf for log-mode and 0 otherwise."""
        return sddapi_c.wmc_zero_weight(self._wmcmanager)

    @property
    def one_weight(self):
        """Returns 0 for log-mode and 1 otherwise."""
        return sddapi_c.wmc_one_weight(self._wmcmanager)

    def propagate(self):
        """Returns the weighted model count of the SDD underlying the WMC manager (using the current literal weights).

        This function should be called each time the weights of literals are changed.
        """
        return sddapi_c.wmc_propagate(self._wmcmanager)

    def set_literal_weight(self, literal, sddapi_c.SddWmc weight):
        """Set weight of literal.

        Sets the weight of a literal in the given WMC manager (should pass the natural log of the weight in log-mode).

        This is a slow function, to set one or more literal weights fast use
        set_literal_weights_from_array.
        """
        cdef sddapi_c.SddLiteral literal_c = self._extract_literal(literal)
        sddapi_c.wmc_set_literal_weight(literal_c, weight, self._wmcmanager)

    def set_literal_weights_from_array(self, double[:] weights):
        """Set all literal weights.

        Expects an array of size <nb_literals>*2 which represents literals [-3, -2, -1, 1, 2, 3]
        """
        if len(weights) > 2 * self.node._manager.var_count():
            raise Exception("Array of weights is longer than the number of variables in the manager.")
        cdef long long nb_lits = len(weights) // 2  # The array can be shorter than the number of variables
        cdef sddapi_c.SddLiteral lit
        cdef long long i
        for i in range(nb_lits):
            sddapi_c.wmc_set_literal_weight(i - nb_lits, weights[i], self._wmcmanager)
        for i in range(nb_lits, 2*nb_lits):
            sddapi_c.wmc_set_literal_weight(i - nb_lits + 1, weights[i], self._wmcmanager)

    def literal_weight(self, literal):
        """Returns the weight of a literal."""
        cdef sddapi_c.SddLiteral literal_c = self._extract_literal(literal)
        return sddapi_c.wmc_literal_weight(literal_c, self._wmcmanager)

    def literal_derivative(self, literal):
        """Returns the partial derivative of the weighted model count with respect to the weight of literal.

        The result returned by this function is meaningful only after having called wmc propagate.
        """
        cdef sddapi_c.SddLiteral literal_c = self._extract_literal(literal)
        return sddapi_c.wmc_literal_derivative(literal_c, self._wmcmanager)

    def literal_pr(self, literal):
        """Returns the probability of literal.

        The result returned by this function is meaningful only after having called wmc propagate.
        """
        cdef sddapi_c.SddLiteral literal_c = self._extract_literal(literal)
        return sddapi_c.wmc_literal_pr(literal_c, self._wmcmanager)


    ## Auxiliary

    def _extract_literal(self, literal):
        cdef sddapi_c.SddLiteral literal_c
        if isinstance(literal, SddNode):
            if literal.is_literal():
                literal_c = literal.literal
            else:
                raise TypeError("Formula/node needs to be a literal")
        else:
            literal_c = literal
        return literal_c


cdef class CompilerOptions:
    cdef compiler_c.SddCompilerOptions _options
    cdef public object cnf_filename
    cdef public object dnf_filename
    cdef public object vtree_filename
    cdef public object sdd_filename
    cdef public object output_vtree_filename
    cdef public object output_vtree_dot_filename
    cdef public object output_sdd_filename
    cdef public object output_sdd_dot_filename
    cdef public int minimize_cardinality
    cdef public object initial_vtree_type
    cdef public int vtree_search_mode
    cdef public int post_search
    cdef public int verbose

    def __init__(self, cnf_filename = None, dnf_filename = None, vtree_filename = None, sdd_filename = None,
                  output_vtree_filename = None, output_vtree_dot_filename = None, output_sdd_filename = None,
                  output_sdd_dot_filename = None, initial_vtree_type = "balanced".encode(),
                  minimize_cardinality = 0, vtree_search_mode = -1, post_search = 0, verbose = 0):
        pass

    def __cinit__(self, cnf_filename = None, dnf_filename = None, vtree_filename = None, sdd_filename = None,
                  output_vtree_filename = None, output_vtree_dot_filename = None, output_sdd_filename = None,
                  output_sdd_dot_filename = None, initial_vtree_type = "balanced".encode(),
                  minimize_cardinality = 0, vtree_search_mode = -1, post_search = 0, verbose = 0):
        self.cnf_filename = cnf_filename
        self.dnf_filename = dnf_filename
        self.vtree_filename = vtree_filename
        self.sdd_filename = sdd_filename
        self.output_vtree_filename = output_vtree_filename
        self.output_vtree_dot_filename = output_vtree_dot_filename
        self.output_sdd_filename = output_sdd_filename
        self.output_sdd_dot_filename = output_sdd_dot_filename
        self.initial_vtree_type = initial_vtree_type
        self.minimize_cardinality = minimize_cardinality
        self.vtree_search_mode = vtree_search_mode
        self.post_search = post_search
        self.verbose = verbose

    def copy_options_to_c(self):
        if self.cnf_filename is None:
            self._options.cnf_filename = NULL
        else:
            self._options.cnf_filename = self.cnf_filename
        if self.dnf_filename is None:
            self._options.dnf_filename = NULL
        else:
            self._options.dnf_filename = self.dnf_filename
        if self.vtree_filename is None:
            self._options.vtree_filename = NULL
        else:
            self._options.vtree_filename = self.vtree_filename
        if self.sdd_filename is None:
            self._options.sdd_filename = NULL
        else:
            self._options.sdd_filename = self.sdd_filename
        if self.output_vtree_filename is None:
            self._options.output_vtree_filename = NULL
        else:
            self._options.output_vtree_filename = self.output_vtree_filename
        if self.output_vtree_dot_filename is None:
            self._options.output_vtree_dot_filename = NULL
        else:
            self._options.output_vtree_dot_filename = self.output_vtree_dot_filename
        if self.output_sdd_filename is None:
            self._options.output_sdd_filename = NULL
        else:
            self._options.output_sdd_filename = self.output_sdd_filename
        if self.output_sdd_dot_filename is None:
            self._options.output_sdd_dot_filename = NULL
        else:
            self._options.output_sdd_dot_filename = self.output_sdd_dot_filename
        self._options.minimize_cardinality  = self.minimize_cardinality
        self._options.vtree_search_mode  = self.vtree_search_mode
        self._options.post_search  = self.post_search
        self._options.verbose  = self.verbose

    def __str__(self):
        r = "CompilerOptions:\n"
        r += "  cnf_filename: " + str(self.cnf_filename) + "\n"
        r += "  dnf_filename: " + str(self.dnf_filename) + "\n"
        r += "  vtree_filename: " + str(self.vtree_filename) + "\n"
        r += "  sdd_filename: " + str(self.sdd_filename) + "\n"
        r += "  output_vtree_filename: " + str(self.output_vtree_filename) + "\n"
        r += "  output_vtree_dot_filename: " + str(self.output_vtree_dot_filename) + "\n"
        r += "  output_sdd_filename: " + str(self.output_sdd_filename) + "\n"
        r += "  output_sdd_dot_filename: " + str(self.output_sdd_dot_filename) + "\n"
        r += "  initial_vtree_type: " + str(self.initial_vtree_type) + "\n"
        r += "  minimize_cardinality: " + str(self.minimize_cardinality) + "\n"
        r += "  vtree_search_mode: " + str(self.vtree_search_mode) + "\n"
        r += "  post_search: " + str(self.post_search) + "\n"
        r += "  verbose: " + str(self.verbose) + "\n"
        return r
