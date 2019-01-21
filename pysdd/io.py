# -*- coding: UTF-8 -*-
"""
pysdd.io
~~~~~~~~

:author: Wannes Meert, Arthur Choi
:copyright: Copyright 2017-2018 KU Leuven and Regents of the University of California.
:license: Apache License, Version 2.0, see LICENSE for details.
"""
from .sdd import SddNode

MYPY = False
if MYPY:
    from typing import List, Optional, Dict, Set


def sdd_to_dot(node, litnamemap=None, show_id=False):
    """Generate Graphviz DOT string for SDD with given root."""
    if node is None:
        raise ValueError("No root node given")
    s = [
        "digraph sdd {"
    ]
    visited = set()
    s += _sddnode_to_dot_int(node, visited, litnamemap, show_id)
    s += [
        "}"
    ]
    return "\n".join(s)


def _format_sddnode_label(node, name=None, litnamemap=None, show_id=False):
    # type: (SddNode, Optional[str], Optional[Dict[int, str]], bool) -> str
    if name is not None:
        pass
    elif node.is_true():
        name = "⟙"
    elif node.is_false():
        name = "⟘"
    else:
        name = node.literal
    if litnamemap is not None:
        name = litnamemap.get(name, name)
    return f"{name}"


def _format_sddnode_xlabel(node):
    if node.vtree() is not None:
        vtree_pos = node.vtree().position()
    else:
        vtree_pos = "n"
    return f"Id:{node.id}\\nVp:{vtree_pos}"


def _sddnode_to_dot_int(node, visited, litnamemap=None, show_id=False):
    # type: (SddNode, Set[SddNode], Optional[Dict[int, str]], bool) -> List[str]
    if node in visited:
        return []
    visited.add(node)
    if node.is_false() or node.is_true() or node.is_literal():
        label = _format_sddnode_label(node, None, litnamemap, show_id)
        extra_options = ""
        if show_id:
            extra_options += (",xlabel=\"" + _format_sddnode_xlabel(node) + "\"")
        return [f"{node.id} [shape=rectangle,label=\"{label}\"{extra_options}];"]
    elif node.is_decision():
        label = _format_sddnode_label(node, '+', litnamemap, show_id)
        extra_options = ""
        if show_id:
            extra_options += (",xlabel=\"" + _format_sddnode_xlabel(node) + "\"")
        s = [f"{node.id} [shape=circle,label=\"{label}\"{extra_options}];"]
        for idx, (prime, sub) in enumerate(node.elements()):
            ps_id = "ps_{}_{}".format(node.id, idx)
            s += [
                "{} [shape=circle, label=\"×\"];".format(ps_id),
                "{} -> {} [arrowhead=none];".format(node.id, ps_id),
                "{} -> {};".format(ps_id, prime.id),
                "{} -> {};".format(ps_id, sub.id),
            ]
            s += _sddnode_to_dot_int(prime, visited, litnamemap, show_id)
            s += _sddnode_to_dot_int(sub, visited, litnamemap, show_id)
        return s


def vtree_to_dot(vtree, litnamemap=None, show_id=False):
    """Generate Graphviz DOT string for given Vtree."""
    s = [
        "digraph vtree {"
    ]
    if show_id:
        s += [f"start [shape=plaintext,style=invis];",
              f"start -> {vtree.position()} [penwidth=0,arrowhead=none,headlabel=\"{vtree.position()}\"];"]
    s += _vtree_to_dot_int(vtree, litnamemap, show_id)
    s += [
        "}"
    ]
    return "\n".join(s)


def _vtree_to_dot_int(vtree, litnamemap=None, show_id=False):
    s = []
    left = vtree.left()
    right = vtree.right()
    if left is None and right is None:
        name = vtree.var()
        if litnamemap is not None:
            name = litnamemap.get(name, name)
        s += [f"{vtree.position()} [label=\"{name}\",shape=\"box\"];"]
    else:
        if show_id:
            s += ["{} [label=\"{}\",shape=\"point\"];".format(vtree.position(), vtree.position())]
        else:
            s += [f"{vtree.position()} [shape=\"point\"];"]
    if left is not None:
        extra_options = ""
        if show_id:
            extra_options = f",headclip=true,headlabel=\"{left.position()}\""
        s += [f"{vtree.position()} -> {left.position()} [arrowhead=none{extra_options}];"]
        s += _vtree_to_dot_int(left, litnamemap, show_id)
    if right is not None:
        extra_options = ""
        if show_id:
            extra_options = f",headclip=true,headlabel=\"     {right.position()}\""
        s += [f"{vtree.position()} -> {right.position()} [arrowhead=none{extra_options}];"]
        s += _vtree_to_dot_int(right, litnamemap, show_id)
    return s
