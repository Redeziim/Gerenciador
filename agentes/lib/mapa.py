#!/usr/bin/env python3
"""Índice de notas e símbolos do projeto, somente com a biblioteca padrão."""
import datetime
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

EXT = {'.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.py', '.sh'}
JS_EXT = {'.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx'}
LIMIT = 300 * 1024


def git(root, *args, check=True):
    p = subprocess.run(['git', '-C', str(root), *args], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, check=False)
    if check and p.returncode:
        raise RuntimeError(p.stderr.decode(errors='replace').strip())
    return p


def paths(root, specs=()):
    args = ['ls-files', '-z', '--']
    args.extend(specs)
    return {os.fsdecode(x) for x in git(root, *args).stdout.split(b'\0') if x}


def code_files(root):
    return {p for p in paths(root) if PurePosixPath(p).suffix in EXT}


def vault(root):
    return root / '.claude' / 'mapa'


def notes(root):
    d = vault(root) / 'modulos'
    result = []
    if not d.is_dir():
        return result
    for file in sorted(d.glob('*.md')):
        raw = file.read_text(encoding='utf-8')
        lines = raw.splitlines(keepends=True)
        values, patterns = {}, []
        end = 0
        if lines and lines[0].strip() == '---':
            in_files = False
            for i, line in enumerate(lines[1:], 1):
                s = line.rstrip('\r\n')
                if s == '---':
                    end = i + 1
                    break
                if in_files and s.startswith('  - '):
                    patterns.append(s[4:].strip())
                elif ':' in s and not s.startswith(' '):
                    k, v = s.split(':', 1)
                    values[k] = v.strip()
                    in_files = k == 'arquivos'
        specs = [':(glob)' + p for p in patterns]
        covered = paths(root, specs) if specs else set()
        result.append({'name': file.stem, 'file': file, 'raw': raw,
                       'body': ''.join(lines[end:]), 'summary': values.get('resumo', ''),
                       'updated': values.get('atualizado', ''), 'patterns': patterns,
                       'covered': covered})
    return result


def changed(root, note):
    if not note['updated']:
        return sorted(note['covered'])
    specs = [':(glob)' + p for p in note['patterns']]
    if not specs:
        return []
    p = git(root, 'diff', '--name-only', '-z', note['updated'], 'HEAD', '--', *specs,
            check=False)
    if p.returncode:
        return sorted(note['covered'])
    return sorted(os.fsdecode(x) for x in p.stdout.split(b'\0') if x)


def head(root):
    return git(root, 'rev-parse', '--short', 'HEAD').stdout.decode().strip()


def head_full(root):
    return git(root, 'rev-parse', 'HEAD').stdout.decode().strip()


def unnoted(files, ns):
    covered = set().union(*(n['covered'] for n in ns)) if ns else set()
    return sorted(files - covered)


def resolve(root, source, spec, files):
    if not spec.startswith('.'):
        return None
    base = PurePosixPath(source).parent
    candidate = os.path.normpath(str(base / spec)).replace('\\', '/')
    if candidate.startswith('../') or candidate == '..':
        return None
    for suffix in ('', '.js', '.jsx', '.mjs', '.ts', '.tsx', '/index.js', '/index.jsx'):
        p = candidate + suffix
        if p in files:
            return p
    return None


def py_resolve(source, dots, mod, files):
    parts = list(PurePosixPath(source).parent.parts)
    up = len(dots) - 1
    if up > len(parts):
        return None
    parts = parts[:len(parts) - up]
    target = '/'.join(parts + (mod.split('.') if mod else []))
    for p in (target + '.py', target + '/__init__.py'):
        if p in files:
            return p
    return None


def symbols_and_imports(root, path, files):
    full = root / path
    data = full.read_bytes()
    lines = data.count(b'\n') + (1 if data and not data.endswith(b'\n') else 0)
    if len(data) > LIMIT:
        return lines, [], []
    src = data.decode('utf-8', errors='replace')
    symbols = []
    imports = set()
    ext = PurePosixPath(path).suffix
    for number, line in enumerate(src.splitlines(), 1):
        if ext in JS_EXT:
            m = re.match(r'^(?:export\s+(?:default\s+)?)?(?:(?:async\s+)?function\s*\*?\s*|class\s+|(?:const|let|var)\s+)([\w$]+)', line)
            if m:
                symbols.append((number, m.group(1)))
            elif re.match(r'^export\s+default\b', line):
                symbols.append((number, 'default'))
            elif re.match(r'^export\s*\{', line):
                names = re.search(r'\{([^}]+)\}', line)
                if names:
                    for item in names.group(1).split(','):
                        name = item.strip().split(' as ')[-1].strip()
                        if name:
                            symbols.append((number, name))
            for match in re.finditer(r'''(?:\b(?:import|export)\b[^;\n]*?\bfrom\s*|\bimport\s*\(|\bimport\s*)["'](\.[^"']+)["']''', line):
                resolved = resolve(root, path, match.group(1), files)
                if resolved:
                    imports.add(resolved)
        elif ext == '.py':
            m = re.match(r'^(?:async\s+)?(?:def|class)\s+(\w+)', line)
            if m:
                symbols.append((number, m.group(1)))
            m = re.match(r'^from\s+(\.+)([\w.]*)\s+import\s+(.+)', line)
            if m:
                resolved = py_resolve(path, m.group(1), m.group(2), files)
                if resolved:
                    imports.add(resolved)
                if not m.group(2):
                    for name in re.findall(r'\b\w+\b', m.group(3)):
                        resolved = py_resolve(path, m.group(1), name, files)
                        if resolved:
                            imports.add(resolved)
        elif ext == '.sh':
            m = re.match(r'^(?:function\s+([\w-]+)\b|([\w-]+)\s*\(\)\s*\{)', line)
            if m:
                symbols.append((number, m.group(1) or m.group(2)))
            m = re.match(r'^\s*(?:source|\.)\s+["\']?([^"\'\s]+)', line)
            if m and not re.search(r'[$*?{}]', m.group(1)):
                p = os.path.normpath(str(PurePosixPath(path).parent / m.group(1)))
                if p in files:
                    imports.add(p)
    return lines, symbols, sorted(imports)


def render_auto(name, group, info, used_by):
    out = [f'# Símbolos — {name}\n', f'Voltar: [[{name}]]\n']
    for p in sorted(group):
        count, symbols, imports = info[p]
        out.append(f'\n## {p} ({count} linhas)\n')
        if symbols:
            out.extend(f'- L{line}: `{symbol}`\n' for line, symbol in symbols[:40])
            if len(symbols) > 40:
                out.append(f'- +{len(symbols) - 40}\n')
        if imports:
            out.append('Imports locais: ' + ', '.join(f'`{x}`' for x in imports) + '\n')
        if used_by[p]:
            out.append('Usado por: ' + ', '.join(f'`{x}`' for x in sorted(used_by[p])) + '\n')
    return ''.join(out)


def generate(root, ns=None):
    ns = notes(root) if ns is None else ns
    files = code_files(root)
    missing = unnoted(files, ns)
    base = vault(root)
    base.mkdir(parents=True, exist_ok=True)
    title = f'# Mapa do código\n\nCommit: {head(root)} · Gerado: {datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}\n\n'
    if ns:
        for n in ns:
            delta = changed(root, n)
            title += f'- [[{n["name"]}]] — {n["summary"]}'
            if delta:
                title += f' (desatualizada: {len(delta)} arquivos mudaram)'
            title += '\n'
    else:
        title += 'Não há notas de módulos.\n'
    title += f'\n## Arquivos sem nota\n\n{len(missing)} arquivos de código. [[simbolos-sem-modulo]]\n'
    title += ''.join(f'- `{p}`\n' for p in missing[:30])
    title += '\n`auto/simbolos-<modulo>.md` tem os símbolos por arquivo.\n'
    (base / 'indice.md').write_text(title, encoding='utf-8')
    info = {p: symbols_and_imports(root, p, files) for p in files}
    used_by = {p: set() for p in files}
    for p, (_, _, imports) in info.items():
        for imported in imports:
            used_by[imported].add(p)
    auto = base / 'auto'
    auto.mkdir(exist_ok=True)
    expected = {'simbolos-sem-modulo.md'}
    for n in ns:
        filename = f'simbolos-{n["name"]}.md'
        expected.add(filename)
        (auto / filename).write_text(render_auto(n['name'], n['covered'] & files, info, used_by), encoding='utf-8')
    (auto / 'simbolos-sem-modulo.md').write_text(render_auto('sem-modulo', missing, info, used_by), encoding='utf-8')
    for old in auto.iterdir():
        if old.is_file() and old.name not in expected:
            old.unlink()
    (base / '.estado').write_text(head_full(root) + '\n', encoding='utf-8')


def stale_auto(root):
    f = vault(root) / '.estado'
    return not f.is_file() or f.read_text().strip() != head_full(root)


def matched_notes(root, ns, queries):
    matching = set()
    for query in queries:
        if os.path.isabs(query):
            try:
                query = str(Path(query).relative_to(root))
            except ValueError:
                continue
        query = query.removeprefix('./').rstrip('/')
        if any(c in query for c in '*?['):
            matching.update(paths(root, [':(glob)' + query]))
        elif query in paths(root, [':(literal)' + query]):
            matching.add(query)
        else:
            matching.update(paths(root, [':(glob)' + query + '/**']))
    return [n for n in ns if n['covered'] & matching]


def pedido(root, args):
    explicit, reserves = [], []
    mode = None
    continuing = '--continuar' in args
    for a in args:
        if a in ('--reservar', '--nota'):
            mode = a
        elif mode == '--reservar':
            reserves.append(a)
            mode = None
        elif mode == '--nota':
            explicit.append(a)
            mode = None
    ns = notes(root)
    if not ns:
        for name in explicit:
            print(f'aviso: nota {name!r} não existe', file=sys.stderr)
        print(json.dumps({'texto': '', 'notas': []}, ensure_ascii=False))
        return
    if stale_auto(root):
        generate(root, ns)
    selected = [] if continuing else matched_notes(root, ns, reserves)
    by_name = {n['name']: n for n in ns}
    for name in explicit:
        if name in by_name:
            selected.append(by_name[name])
        else:
            print(f'aviso: nota {name!r} não existe', file=sys.stderr)
    ordered = list(dict((n['name'], n) for n in selected).values())
    if not ordered:
        print(json.dumps({'texto': '', 'notas': []}, ensure_ascii=False))
        return
    out = ['Mapa do código (notas dos módulos desta tarefa; use-as para ir direto aos arquivos, sem procurar):\n']
    size = 0
    for n in ordered:
        path = n['file']
        body = n['body']
        out.append(f'### {n["name"]} — {n["summary"]}\n')
        delta = changed(root, n)
        if delta:
            out.append('(desatualizada: estes arquivos mudaram depois da nota: ' + ', '.join(delta) + ' — confira antes de confiar)\n')
        body_bytes = len(body.encode('utf-8'))
        if size + body_bytes <= 12000:
            out.append(body if body.endswith('\n') else body + '\n')
            size += body_bytes
        else:
            out.append(f'{path} — leia se precisar\n')
        out.append(f'Índice de todos os módulos: {vault(root) / "indice.md"}\n')
        out.append(f'Símbolos por arquivo: {vault(root) / "auto" / ("simbolos-" + n["name"] + ".md")}\n')
    print(json.dumps({'texto': '\n'.join(out), 'notas': [n['name'] for n in ordered]}, ensure_ascii=False))


def main():
    root = Path(sys.argv[1]).resolve()
    cmd = sys.argv[2]
    args = sys.argv[3:]
    if cmd == 'gerar':
        generate(root)
    elif cmd == 'estado':
        ns = notes(root)
        for n in ns:
            delta = changed(root, n)
            if delta:
                print(f'{n["name"]}: desatualizada ({len(delta)} arquivos): ' + ', '.join(delta))
        print(f'Arquivos de código sem nota: {len(unnoted(code_files(root), ns))}')
        print('Auto atrás do HEAD: ' + ('sim' if stale_auto(root) else 'não'))
    elif cmd == 'avisar':
        ns = notes(root)
        if not ns:
            return
        if stale_auto(root):
            generate(root, ns)
        stale = [n['name'] for n in ns if changed(root, n)]
        if stale:
            qty = len(stale)
            print(f'mapa do código: {qty} {"nota desatualizada" if qty == 1 else "notas desatualizadas"} ({", ".join(stale)}); detalhes: mapa.sh <projeto> estado')
    elif cmd == 'notas':
        for n in matched_notes(root, notes(root), args):
            print(n['name'])
    elif cmd == 'conferida':
        for name in args:
            file = vault(root) / 'modulos' / (name + '.md')
            if not file.is_file():
                raise ValueError(f'nota {name!r} não existe')
            raw = file.read_text(encoding='utf-8')
            match = re.match(r'\A---\r?\n.*?\r?\n---\r?\n', raw, re.S)
            if not match:
                raise ValueError(f'nota {name!r} não tem frontmatter')
            front, body = raw[:match.end()], raw[match.end():]
            updated, count = re.subn(r'(?m)^atualizado:.*$', 'atualizado: ' + head(root), front, count=1)
            if count != 1:
                raise ValueError(f'nota {name!r} não tem atualizado:')
            file.write_text(updated + body, encoding='utf-8')
    elif cmd == 'pedido':
        pedido(root, args)
    else:
        raise ValueError(f'comando {cmd!r} desconhecido')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        print(f'erro: {exc}', file=sys.stderr)
        sys.exit(1)
