#!/usr/bin/env python3
"""Splits Dart source into top-level chunks (directives and declarations).

A chunk runs from the end of the previous top-level item to the end of this one,
so leading blank lines, comments, doc comments and annotations travel with the
declaration they precede. Concatenating every chunk (plus the trailing text)
gives back the file byte for byte.

The scanner understands everything that can hide a brace or a semicolon:
// and nested /* */ comments; '', "", ''' and \"\"\" strings, raw strings, and
${...} interpolation (which may itself contain strings and braces).

    python tool/restructure/dart_chunks.py <file.dart>     # list the chunks
"""
import re
import sys


class Chunk:
    def __init__(self, text, kind, name):
        self.text = text
        self.kind = kind  # 'directive' | 'decl'
        self.name = name

    def __repr__(self):
        return f'Chunk({self.kind}, {self.name!r}, {len(self.text)} chars)'


def _skip_string(src, i):
    """src[i] is at the opening quote (or the r of a raw string). Returns the index after the string."""
    raw = False
    if src[i] == 'r':
        raw = True
        i += 1
    q = src[i]
    triple = src.startswith(q * 3, i)
    if triple:
        i += 3
        end = q * 3
    else:
        i += 1
        end = q
    n = len(src)
    while i < n:
        if not raw and src[i] == '\\':
            i += 2
            continue
        if src.startswith(end, i):
            return i + len(end)
        if not triple and src[i] == '\n':
            raise ValueError(f'unterminated string at {i}')
        if not raw and src[i] == '$' and i + 1 < n and src[i + 1] == '{':
            i = _skip_braces(src, i + 1)
            continue
        i += 1
    raise ValueError('unterminated string')


def _skip_block_comment(src, i):
    depth = 0
    n = len(src)
    while i < n:
        if src.startswith('/*', i):
            depth += 1
            i += 2
        elif src.startswith('*/', i):
            depth -= 1
            i += 2
            if depth == 0:
                return i
        else:
            i += 1
    raise ValueError('unterminated block comment')


def _is_string_start(src, i):
    c = src[i]
    if c in '\'"':
        return True
    if c == 'r' and i + 1 < len(src) and src[i + 1] in '\'"':
        prev = src[i - 1] if i > 0 else ' '
        return not (prev.isalnum() or prev == '_' or prev == '$')
    return False


def _skip_braces(src, i):
    """src[i] == '{'. Returns the index after the matching '}'."""
    assert src[i] == '{'
    depth = 0
    n = len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            i = _skip_block_comment(src, i)
            continue
        if _is_string_start(src, i):
            i = _skip_string(src, i)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced braces')


_DIRECTIVE = re.compile(r'(import|export|part|library)\b')
_NAME_PATTERNS = [
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)'),
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:base\s+)?mixin\s+(\w+)'),
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*enum\s+(\w+)'),
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*extension\s+type\s+(\w+)'),
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*extension\s+(\w+)'),
    re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*typedef\s+(\w+)'),
]


def _strip_leading_trivia(code):
    """Drops leading whitespace/comments/annotation lines to find the declaration head."""
    i = 0
    n = len(code)
    while i < n:
        if code[i].isspace():
            i += 1
        elif code.startswith('//', i):
            j = code.find('\n', i)
            i = n if j < 0 else j
        elif code.startswith('/*', i):
            i = _skip_block_comment(code, i)
        elif code[i] == '@':
            m = re.match(r'@[\w.]+', code[i:])
            i += m.end()
            if i < n and code[i] == '(':
                depth = 0
                while i < n:
                    if code[i] == '(':
                        depth += 1
                    elif code[i] == ')':
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    i += 1
        else:
            break
    return code[i:]


def decl_name(text):
    head = _strip_leading_trivia(text)
    for p in _NAME_PATTERNS:
        m = p.match(head)
        if m:
            return m.group(1)
    # function or variable: the identifier before the first '(' or '=' / ';'
    m = re.match(r'([\w<>,?\s\[\].]*?)\b(\w+)\s*(?:<[^>]*>)?\s*[(=;]', head)
    if m:
        return m.group(2)
    return head[:40]


def chunks(src):
    out = []
    i = 0
    start = 0
    n = len(src)
    while True:
        # skip trivia to the next token
        j = i
        while j < n:
            if src[j].isspace():
                j += 1
            elif src.startswith('//', j):
                k = src.find('\n', j)
                j = n if k < 0 else k
            elif src.startswith('/*', j):
                j = _skip_block_comment(src, j)
            else:
                break
        if j >= n:
            break
        is_directive = bool(_DIRECTIVE.match(src, j)) and not re.match(r'(import|export|part|library)\s*[(=.<]', src[j:j + 12])
        # scan to the end of this item: ';' or a top-level '{...}' that closes the item
        k = j
        paren = 0
        while k < n:
            c = src[k]
            if src.startswith('//', k):
                e = src.find('\n', k)
                k = n if e < 0 else e
                continue
            if src.startswith('/*', k):
                k = _skip_block_comment(src, k)
                continue
            if _is_string_start(src, k):
                k = _skip_string(src, k)
                continue
            if c in '([':
                paren += 1
            elif c in ')]':
                paren -= 1
            elif c == '{':
                k = _skip_braces(src, k)
                if paren == 0:
                    # a body ends the item unless more of the same item follows
                    # (e.g. `x = {...};`, `=> {...}.toList();`)
                    m = re.match(r'\s*([;.,?)\]]|\.\.)', src[k:])
                    if m and m.group(1) != ')' and m.group(1) != ']':
                        continue
                    break
                continue
            elif c == ';' and paren == 0:
                k += 1
                break
            k += 1
        text = src[start:k]
        kind = 'directive' if is_directive else 'decl'
        out.append(Chunk(text, kind, None if is_directive else decl_name(text)))
        start = k
        i = k
    tail = src[start:]
    return out, tail


def main():
    src = open(sys.argv[1], encoding='utf-8', newline='').read()
    cs, tail = chunks(src)
    assert ''.join(c.text for c in cs) + tail == src, 'chunks do not rebuild the file'
    for c in cs:
        first = c.text.strip().splitlines()[0][:90] if c.text.strip() else ''
        lines = c.text.count('\n')
        print(f'{c.kind:9s} {lines:5d}  {c.name or "":40s} {first}')
    print('chunks:', len(cs), 'rebuild: ok')


if __name__ == '__main__':
    main()
