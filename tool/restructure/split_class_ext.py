#!/usr/bin/env python3
"""Moves groups of a class's methods, verbatim, into extensions in part files.

    python tool/restructure/split_class_ext.py <lib/.../file.dart> <ClassName> <plan.json>
    python tool/restructure/split_class_ext.py --list <lib/.../file.dart> <ClassName>

<plan.json>: {"<part name>": {"extension": "<ExtName>", "members": ["name", ...]}, ...}
Each part becomes <dir>/<file>/<part name>.dart:

    part of '../<file>.dart';

    extension <ExtName> on <ClassName> {
      <the listed members, text unchanged>
    }

Why extensions: callers keep calling `obj.method()` unchanged (an extension in a
part of the library is in scope wherever the library is imported), method bodies
keep every unqualified reference (`this` is the same object), private members
stay reachable (same library), and fields, constructors and statics stay on the
class. Only instance methods, getters and setters with a body may move; never
@override members, operators, abstract or external members, or a member that
uses `super`. (Extension members cannot be overridden: run this only on classes
nothing extends or implements.)

The proof: the multiset of member texts of the original class equals the class's
remaining members plus every extension's members. Line endings are kept.
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dart_chunks import chunks, _skip_braces, _strip_leading_trivia  # noqa: E402


def find_class_body(src, name):
    cs, _ = chunks(src)
    pos = 0
    for c in cs:
        if c.kind == 'decl' and c.name == name:
            start = src.index(c.text, pos)
            head = re.search(r'\bclass\s+' + re.escape(name) + r'\b', c.text)
            assert head, f'{name} is not a class'
            brace = c.text.index('{', head.end())
            open_at = start + brace
            close_after = _skip_braces(src, open_at)
            return open_at + 1, close_after - 1  # body between the braces
        pos += len(c.text)
    raise SystemExit(f'class {name} not found')


_MODS = r'(?:(?:static|final|const|late|external|abstract|covariant|factory)\s+)*'


def member_info(text, class_name):
    head = _strip_leading_trivia(text)
    annotations = text[:len(text) - len(head)]
    override = '@override' in annotations
    is_static = bool(re.match(r'static\b', head))
    if re.match(r'(?:const\s+|factory\s+)?' + re.escape(class_name) + r'\b\s*[.(]', head) or re.match(r'factory\b', head):
        return 'ctor', class_name, is_static, override
    m = re.match(_MODS + r'[\w<>?,\s\[\].]*?\bget\s+(\w+)', head)
    if m and re.match(r'[^({;=]*\bget\s+' + m.group(1), head):
        return 'getter', m.group(1), is_static, override
    m = re.match(_MODS + r'(?:[\w<>?,\s\[\].]*?\s)?set\s+(\w+)\s*\(', head)
    if m:
        return 'setter', m.group(1), is_static, override
    if re.search(r'\boperator\b', head.split('(')[0]):
        return 'operator', 'operator', is_static, override
    name, is_method = _sig_name(head)
    return ('method' if is_method else 'field'), name, is_static, override


_KEYWORDS = {'Function', 'static', 'final', 'const', 'late', 'external', 'abstract', 'covariant', 'factory', 'async', 'sync', 'required'}


def _sig_name(head):
    """(name, is_method) from a member head, depth-aware so record and generic types cannot fool it."""
    depth = 0
    last = None
    i = 0
    n = len(head)
    while i < n:
        c = head[i]
        if c.isalpha() or c == '_' or c == '$':
            j = i
            while j < n and (head[j].isalnum() or head[j] in '_$'):
                j += 1
            if depth == 0:
                last = head[i:j]
            i = j
            continue
        if c in '<([':
            if c == '(' and depth == 0 and last and last not in _KEYWORDS:
                return last, True
            depth += 1
            last = None if depth > 0 and c != '<' else last
        elif c in '>)]':
            if c == '>' and i > 0 and head[i - 1] == '=':
                pass
            else:
                depth -= 1
        elif depth == 0 and (c == ';' or (c == '=' and not head.startswith('=>', i) and not head.startswith('==', i)) or c == ','):
            return (last or head[:30]), False
        elif depth == 0 and c == '{':
            return (last or head[:30]), False
        i += 1
    return (last or head[:30]), False


def movable(text, kind, is_static, override):
    if kind not in ('method', 'getter', 'setter') or is_static or override:
        return False
    head = _strip_leading_trivia(text)
    if re.match(r'(external|abstract)\b', head):
        return False
    if 'super.' in text:
        return False
    body = head.split('=>', 1)[0] if '=>' in head else head
    return '{' in head or '=>' in head  # has a body


def qualify_statics(text, statics, cls):
    """Prefixes bare references to the class's static members with `Cls.`, in code only.

    Inside an extension a static member of the extended class must be written
    `Cls.name`; strings and comments are left alone (interpolations included).
    """
    from dart_chunks import _skip_string, _skip_block_comment, _is_string_start
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(text[i:j])
            i = j
            continue
        if text.startswith('/*', i):
            j = _skip_block_comment(text, i)
            out.append(text[i:j])
            i = j
            continue
        if _is_string_start(text, i):
            j = _skip_string(text, i)
            seg = text[i:j]
            seg = re.sub(r'\$\{([^{}]*)\}', lambda m: '${' + qualify_statics(m.group(1), statics, cls) + '}', seg)
            seg = re.sub(r'\$([A-Za-z_]\w*)', lambda m: ('${' + cls + '.' + m.group(1) + '}') if m.group(1) in statics else m.group(0), seg)
            out.append(seg)
            i = j
            continue
        c = text[i]
        if c.isalpha() or c in '_$':
            j = i
            while j < n and (text[j].isalnum() or text[j] in '_$'):
                j += 1
            word = text[i:j]
            prev = ''.join(out).rstrip()
            if word in statics and not prev.endswith('.'):
                out.append(f'{cls}.{word}')
            else:
                out.append(word)
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def unqualify(text, statics, cls):
    for s in sorted(statics, key=len, reverse=True):
        text = text.replace('${' + cls + '.' + s + '}', '$' + s).replace(cls + '.' + s, s)
    return text


def norm(t):
    lines = [l.rstrip() for l in t.replace('\r\n', '\n').strip('\n').split('\n')]
    while lines and not lines[0].strip():
        lines.pop(0)
    indent = min((len(l) - len(l.lstrip()) for l in lines if l.strip()), default=0)
    return '\n'.join(l[indent:] for l in lines).strip()


def overridden_members(cls):
    """Names that a class extending/implementing [cls] defines, in lib/ and test/."""
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    rx = re.compile(r'\bclass\s+(\w+)(?:<[^>{]*>)?\s+(?:extends|implements|with)\s+[^{]*\b' + re.escape(cls) + r'\b[^{]*\{')
    names = set()
    for top in ('lib', 'test'):
        for d, _, fs in os.walk(os.path.join(root, top)):
            for f in fs:
                if not f.endswith('.dart'):
                    continue
                src = open(os.path.join(d, f), encoding='utf-8', errors='replace', newline='').read()
                if cls not in src:
                    continue
                for m in rx.finditer(src):
                    sub = m.group(1)
                    try:
                        for c in members_of(src, sub)[3]:
                            names.add(member_info(c.text, sub)[1])
                    except (SystemExit, ValueError, AssertionError):
                        pass
    return names


def members_of(src, class_name):
    b0, b1 = find_class_body(src, class_name)
    body = src[b0:b1]
    ms, tail = chunks(body)
    return b0, b1, body, ms, tail


def main():
    if sys.argv[1] == '--list':
        path, cls = sys.argv[2], sys.argv[3]
        src = open(path, encoding='utf-8', newline='').read()
        _, _, _, ms, _ = members_of(src, cls)
        for m in ms:
            kind, name, st, ov = member_info(m.text, cls)
            mv = movable(m.text, kind, st, ov)
            print(f'{kind:8s} {"static " if st else ""}{"@override " if ov else ""}{name:40s} {m.text.count(chr(10)):4d} {"movable" if mv else ""}')
        return

    path, cls, plan_path = sys.argv[1], sys.argv[2], sys.argv[3]
    plan = json.load(open(plan_path, encoding='utf-8'))
    src = open(path, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    b0, b1, body, ms, tail = members_of(src, cls)

    info = [(m, *member_info(m.text, cls)) for m in ms]
    # An extension member cannot be overridden: a subclass anywhere (lib or a
    # test's fake) that redefines a planned member would silently stop being
    # called. Refuse such a plan.
    overridden = overridden_members(cls)
    clash = sorted(n for spec in plan.values() for n in spec['members'] if n in overridden)
    assert not clash, f'overridden by a subclass, keep them on the class: {clash}'
    owner = {}
    for part, spec in plan.items():
        for n in spec['members']:
            assert n not in owner, f'{n} listed twice'
            owner[n] = part
    found = collections.Counter()
    moved = collections.OrderedDict((p, []) for p in plan)
    kept = []
    for m, kind, name, st, ov in info:
        if name in owner and kind in ('method', 'getter', 'setter') and not st:
            assert movable(m.text, kind, st, ov), f'{name} cannot move (kind {kind}, override {ov}, or uses super/abstract)'
            moved[owner[name]].append(m)
            found[name] += 1
        else:
            kept.append(m)
    missing = [n for n in owner if found[n] == 0]
    assert not missing, f'not found or not movable: {missing}'

    new_body = ''.join(m.text for m in kept) + tail
    new_src = src[:b0] + new_body + src[b1:]

    base = os.path.splitext(os.path.basename(path))[0]
    folder = os.path.join(os.path.dirname(path), base)
    os.makedirs(folder, exist_ok=True)
    # part directives after the last existing directive
    lib_chunks, lib_tail = chunks(new_src)
    last = max(i for i, c in enumerate(lib_chunks) if c.kind == 'directive')
    part_lines = ''.join(f"{nl}part '{base}/{p}.dart';" for p in plan)
    new_src = ''.join(c.text for c in lib_chunks[:last + 1]) + part_lines + ''.join(c.text for c in lib_chunks[last + 1:]) + lib_tail

    statics = {name for (m, kind, name, st, ov) in info if st}
    for p, items in moved.items():
        ext = plan[p]['extension']
        doc = plan[p].get('doc')
        members_text = (nl + nl).join(qualify_statics(m.text.strip('\r\n'), statics, cls) for m in items)
        doc_text = ''.join(f'/// {line}{nl}' for line in doc.split('\n')) if doc else ''
        text = f"part of '../{base}.dart';{nl}{nl}{doc_text}extension {ext} on {cls} {{{nl}{members_text}{nl}}}{nl}"
        out = os.path.join(folder, f'{p}.dart')
        assert not os.path.exists(out), f'exists: {out}'
        open(out, 'w', encoding='utf-8', newline='').write(text)
    open(path, 'w', encoding='utf-8', newline='').write(new_src)

    # proof
    # Both sides drop `Cls.` before static names: the original may already be
    # qualified somewhere, and the move qualifies the bare ones.
    before = collections.Counter(norm(unqualify(m.text, statics, cls)) for m in ms)
    after = collections.Counter(norm(unqualify(m.text, statics, cls)) for m in members_of(new_src, cls)[3])
    for p in plan:
        t = open(os.path.join(folder, f'{p}.dart'), encoding='utf-8', newline='').read()
        ext = plan[p]['extension']
        head = re.search(r'extension\s+' + re.escape(ext) + r'\s+on\s+' + re.escape(cls) + r'\s*\{', t)
        e0 = head.end()
        e1 = _skip_braces(t, head.end() - 1) - 1
        for m in chunks(t[e0:e1])[0]:
            after[norm(unqualify(m.text, statics, cls))] += 1
    if before != after:
        print('MISMATCH', len(before - after), 'missing,', len(after - before), 'extra')
        for t in list(before - after)[:3]:
            print('missing:', t[:160])
        sys.exit(1)
    sizes = {p: sum(m.text.count('\n') for m in items) for p, items in moved.items()}
    print(f'{path} {cls}: {len(ms)} members, proof ok; moved {sizes}; class body now {new_body.count(chr(10))} lines')


if __name__ == '__main__':
    main()
