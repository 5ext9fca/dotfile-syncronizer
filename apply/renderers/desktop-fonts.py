#!/usr/bin/env python3
"""Preserve INI text; replace only the family in managed font settings.

KConfig handles effective KDE values (including system/kdedefaults layers).
Only absent KDE values use Plasma's built-in font sizes, 10pt / small 8pt:
https://invent.kde.org/plasma/plasma-integration/-/blob/master/qt6/src/platformtheme/kfontsettingsdata.cpp
GTK defaults are queried from the running toolkit, never guessed.
"""
import ctypes
import ctypes.util
from pathlib import Path
import re
import shutil
import subprocess
import sys


def kde_default(group, key):
    reader = shutil.which('kreadconfig6') or shutil.which('kreadconfig5')
    if not reader:
        raise ValueError('kreadconfig6/5 is required to resolve effective KDE fonts')
    value = subprocess.check_output(
        [reader, '--file', 'kdeglobals', '--group', group, '--key', key],
        text=True, timeout=10).strip()
    if value:
        return value
    size = 8 if key == 'smallestReadableFont' else 10
    return f'Noto Sans,{size},-1,5,50,0,0,0,0,0'


def gtk_default(version):
    library = ctypes.util.find_library('gtk-3' if version == 3 else 'gtk-4')
    if not library:
        raise ValueError(f'GTK {version} is needed to read the effective default font')
    gtk = ctypes.CDLL(library)
    gtk.gtk_init_check.restype = ctypes.c_int
    gtk.gtk_init_check.argtypes = [] if version == 4 else [ctypes.c_void_p, ctypes.c_void_p]
    ready = gtk.gtk_init_check() if version == 4 else gtk.gtk_init_check(None, None)
    if not ready:
        raise ValueError(f'cannot read GTK {version} defaults without a desktop display')
    gtk.gtk_settings_get_default.restype = ctypes.c_void_p
    settings = gtk.gtk_settings_get_default()
    if not settings:
        raise ValueError('no GTK settings available')
    gobject = ctypes.CDLL(ctypes.util.find_library('gobject-2.0'))
    value = ctypes.c_void_p()
    gobject.g_object_get.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_void_p]
    gobject.g_object_get(settings, b'gtk-font-name', ctypes.byref(value), None)
    if not value.value:
        raise ValueError('no effective GTK font')
    result = ctypes.string_at(value).decode('utf-8')
    glib = ctypes.CDLL(ctypes.util.find_library('glib-2.0'))
    glib.g_free.argtypes = [ctypes.c_void_p]
    glib.g_free(value)
    return result


def replace_family(value, family, kde):
    if kde:
        fields = value.split(',')
        # Qt serializes 10..20 fields, depending on its version. Keep the tail.
        if len(fields) < 10 or len(fields) > 20 or not fields[0]:
            raise ValueError(f'unsupported QFont value: {value!r}')
        if not re.fullmatch(r'-?\d+(?:\.\d+)?', fields[1]) or float(fields[1]) == 0:
            raise ValueError('invalid KDE font size')
        if any(not re.fullmatch(r'-?\d+(?:\.\d+)?', part) for part in fields[2:10]):
            raise ValueError('invalid QFont numeric attributes')
        fields[0] = family
        return ','.join(fields)
    # Pango font descriptions end in a size, optionally with a px suffix.
    match = re.fullmatch(r'.+?\s+(\d+(?:\.\d+)?(?:px)?)\s*', value)
    if not match or float(match[1][:-2] if match[1].endswith('px') else match[1]) <= 0:
        raise ValueError(f'cannot safely read GTK font size: {value!r}')
    description = value[:match.start(1)].strip().rstrip(',').strip()
    styles = []
    while description and description.split()[-1].lower() in {
        'normal', 'regular', 'bold', 'italic', 'oblique', 'light', 'ultralight',
        'semibold', 'demibold', 'heavy', 'ultrabold', 'condensed', 'expanded',
        'ultracondensed', 'semicondensed', 'semiexpanded', 'ultraexpanded',
    }:
        description, style = description.rsplit(' ', 1) if ' ' in description else ('', description)
        styles.insert(0, style)
    suffix = ' '.join(styles + [match[1]])
    return f'{family} {suffix}'


def render(kind, text):
    kde = kind == 'kdeglobals'
    if kde:
        keys = [('General', k) for k in ('font', 'fixed', 'menuFont', 'toolBarFont', 'smallestReadableFont', 'taskbarFont')]
        keys.append(('WM', 'activeFont'))
    else:
        keys = [('Settings', 'gtk-font-name')]
    managed = set(keys)
    lines = text.splitlines(keepends=True)
    if '\x00' in text or '\r' in text.replace('\r\n', ''):
        raise ValueError('unsupported INI control character')
    newline = '\r\n' if '\r\n' in text else '\n'
    section = None
    positions, sections = {}, {}
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(('#', ';')):
            continue
        if stripped.startswith('['):
            if not re.fullmatch(r'(?:\[[^\[\]\r\n]+\])+', stripped):
                raise ValueError('malformed INI section')
            section = stripped[1:-1]
            if any(section.startswith(group + '][') for group, _ in managed):
                raise ValueError('unsupported managed KConfig group flags')
            if section in sections:
                raise ValueError(f'duplicate INI section: {section}')
            sections[section] = i
            continue
        if '=' not in line or section is None:
            raise ValueError('cannot safely parse INI line')
        rawkey, value = line.rstrip('\r\n').split('=', 1)
        key = rawkey.strip()
        # Do not override immutable/localized/escaped KConfig settings.
        base = key.split('[', 1)[0]
        if (section, base) in managed and key != base:
            raise ValueError(f'unsupported managed KConfig key: {key}')
        if (section, key) in managed:
            if (section, key) in positions:
                raise ValueError(f'duplicate managed key: {key}')
            positions[section, key] = (i, rawkey, value)
    additions = {}
    for group, key in keys:
        family = 'JetBrainsMono Nerd Font' if key == 'fixed' else 'PingFang SC'
        previous = positions.get((group, key))
        value = previous[2] if previous else (kde_default(group, key) if kde else gtk_default(3 if '3.0' in kind else 4))
        replacement = replace_family(value, family, kde)
        print(f'desktop-fonts: [{group}] {key}: {value} -> {replacement}', file=sys.stderr)
        if previous:
            i, rawkey, _ = previous
            ending = newline if lines[i].endswith('\n') else ''
            lines[i] = f'{rawkey}={replacement}{ending}'
        else:
            additions.setdefault(group, []).append(f'{key}={replacement}{newline}')
    # Insert missing keys at the end of their original section, preserving comments.
    for group, newlines in additions.items():
        if group not in sections:
            if lines and not lines[-1].endswith('\n'):
                lines[-1] += newline
            lines.extend([f'{newline}[{group}]{newline}', *newlines])
            continue
        start = next(i for i, line in enumerate(lines) if line.strip() == f'[{group}]')
        end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
        if end and not lines[end - 1].endswith('\n'):
            lines[end - 1] += newline
        lines[end:end] = newlines
    return ''.join(lines)


def main():
    kind, source, output = sys.argv[1:]
    path = Path(source)
    text = path.read_bytes().decode('utf-8') if path.exists() else ''
    Path(output).write_bytes(render(kind, text).encode('utf-8'))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'error: desktop-fonts: {error}', file=sys.stderr)
        sys.exit(1)
