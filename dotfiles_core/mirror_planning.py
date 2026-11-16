"""Mirror ownership and candidate planning over the existing file transaction API."""
from pathlib import Path
import re
import sys
import tempfile

from dotfiles_core.apply_planning import Planner
from dotfiles_core.contracts import Contract
from dotfiles_core.install_config import ROOT
from dotfiles_core.mirror_rules import MirrorError, config_text, environment, read_config, render
from dotfiles_core.native_apply import NativeFilesystem, native_filesystem
from dotfiles_core.errors import ProtocolError

MANAGED = '# Managed by dotfiles mirrors'
STATE = '# dotfiles mirror state v1'


def read_text(path: str | Path) -> str:
    # Payloads are not declarations: preserve unrelated bytes and CRLF exactly.
    return Path(path).read_bytes().decode('utf-8', errors='surrogateescape')


def config_file(path: str | Path) -> dict[str, str]:
    return read_config(Path(path).read_bytes().decode('utf-8'))


def ownership_text(path: str | Path) -> str | None:
    # The old ownership grep treats an unreadable file as unrecognized, while
    # a selected renderer's actual read remains a hard failure.
    try:
        return read_text(path)
    except OSError as error:
        print(str(error), file=sys.stderr)
        return None


def has_marker(path: str | Path, marker: str) -> bool:
    text = ownership_text(path)
    return text is not None and marker in text.split('\n')


def cargo_owned(text: str) -> bool:
    return ('[source.rsproxy-sparse]' in text.split('\n')
            and any(re.match(r'^replace-with[ \t\r\v\f]*=[ \t\r\v\f]*"rsproxy-sparse"', line)
                    for line in text.split('\n')))


def npm_owned(text: str, mode: str, current: dict, previous: dict, legacy: dict) -> bool:
    lines = text.split('\n')
    if not any(re.match(r'^[ \t\r\v\f]*registry[ \t\r\v\f]*=', line) for line in lines):
        return True
    old = next((line.split('=')[1].strip(' \t') for line in lines
                if '=' in line and re.fullmatch(r'[ \t]*registry[ \t]*', line.split('=')[0])), '')
    return mode != 'initialize' and old in (current['npm'], previous.get('npm', ''), legacy['npm'])


def pacman_text(text: str, mode: str, key: str, branch: str, current: dict, previous: dict, legacy: dict) -> str:
    value, old, historical = current[key] + branch, previous.get(key, '') + branch, legacy[key] + branch
    if mode == 'initialize' and (historical in text or value in text):
        return text
    header = f'Server = {value}/$repo/' + ('os/' if key == 'arch' else '') + '$arch\n'
    prefixes = tuple('Server = ' + endpoint + '/' for endpoint in (old, historical, value))
    lines = text.split('\n')
    if lines[-1] == '':
        lines.pop()
    return header + ''.join(line + '\n' for line in lines if not line.startswith(prefixes))


class Mirrors:
    def __init__(self, context: dict, filesystem: NativeFilesystem):
        self.context, self.fs = context, filesystem
        self.mode = context['mode']
        if self.mode not in ('apply', 'initialize'):
            raise MirrorError('Invalid mirror mode')
        self.current = config_file(context['file'])
        self.legacy = config_file(ROOT / 'mirrors/legacy.conf')
        self.previous = {}
        self.config = context['config']
        self.scratch = Path(context['scratch'])
        self.planner = Planner(filesystem, context['session'])
        schema = Contract.load('apply-plan')
        self.planner.rows = schema.read(schema.from_rows(context.get('base_plan', ''), validate_plan=True))
        self.planner.directories = {row['target']: True for row in self.planner.rows if row['action'] == 'mkdir'}
        state = self.config + '/dotfiles/mirror-state.conf'
        if self.fs.entry(state).kind == 'file' and has_marker(state, STATE):
            self.previous = config_file(state)

    def file(self, path: str) -> bool:
        return self.fs.value('file', path, boolean=True)

    def exists(self, path: str) -> bool:
        return self.fs.value('exists', path, boolean=True)

    def candidate(self, name: str, text: str) -> str:
        path = self.scratch / name
        path.write_bytes(text.encode('utf-8', errors='surrogateescape'))
        return str(path)

    def rendered(self, kind: str, text: str) -> str:
        return render(kind, self.mode, text, self.current, self.previous, self.legacy)

    def skip(self, target: str, root: str, reason: str) -> None:
        self.planner.add('mirrors', 'skip', target, root, reason)

    def add(self, source: str, target: str, root: str, mode: str, owned: bool = True, privilege: str = 'none') -> None:
        paths = self.planner.paths
        parent = paths.parent(target)
        virtual = self.planner.virtual(parent)
        if virtual:
            owned, mode = True, 'apply'
        else:
            probe = parent
            while probe != root:
                if self.fs.entry(probe).kind in ('link', 'file', 'other'):
                    self.skip(target, root, 'unmanaged-parent')
                    return
                if probe == '/':
                    break
                probe = paths.parent(probe)
        if (not virtual and self.fs.entry(target).kind not in ('file', 'absent')) or not owned:
            self.skip(target, root, 'unmanaged')
            return
        if mode == 'initialize' and self.exists(target):
            self.skip(target, root, 'initialized')
            return
        permissions = self.fs.value('permissions', target) if not virtual and self.file(target) else '644'
        if not re.fullmatch('[0-7]{1,4}', permissions):
            raise ProtocolError('Invalid native file permissions')
        Path(source).chmod(int(permissions, 8))
        self.planner.file('mirrors', 'copy', source, target, root, privilege)

    def environment(self) -> None:
        root = self.fs.anchor(self.config)
        values = environment(self.current, ROOT / 'mirrors/schema/environment.tsv')
        for kind, relative in (('fish', 'fish/conf.d/15-mirrors.fish'), ('sh', 'dotfiles/mirrors.sh')):
            target = self.config + '/' + relative
            lines = [MANAGED]
            for variable, value in values:
                lines.append(f"set -gx {variable} '{value}'" if kind == 'fish' else f"export {variable}='{value}'")
            candidate = self.candidate('environment.' + kind, '\n'.join(lines) + '\n')
            owned = not self.file(target) or has_marker(target, MANAGED)
            self.add(candidate, target, root, self.mode, owned)

    def cargo(self) -> None:
        target = self.fs.value('resolve-root', self.context['cargo_home']) + '/config.toml'
        root = self.fs.anchor(self.planner.paths.parent(target))
        owned = True
        if self.exists(target):
            original = ownership_text(target) if self.file(target) else None
            owned = original is not None and cargo_owned(original)
            text = self.rendered('cargo', read_text(target)) if owned else ''
        else:
            value = self.current['cargo_index']
            text = (MANAGED + '\n[source.crates-io]\nreplace-with = "rsproxy-sparse"\n\n'
                    f'[source.rsproxy-sparse]\nregistry = "{value}"\n\n[registries.rsproxy]\nindex = "{value}"\n\n'
                    '[net]\ngit-fetch-with-cli = true\n')
        self.add(self.candidate('cargo.toml', text), target, root, self.mode, owned)

    def npm(self) -> None:
        path = self.context['npm_config']
        target = self.fs.value('resolve-root', str(Path(path).parent)) + '/' + Path(path).name
        root = self.fs.anchor(self.planner.paths.parent(target))
        text, owned = '', True
        if self.file(target):
            text = read_text(target)
            owned = npm_owned(text, self.mode, self.current, self.previous, self.legacy)
        elif self.fs.entry(target).kind != 'absent':
            owned = False
        self.add(self.candidate('npmrc', self.rendered('npm', text)), target, root, 'apply', owned)

    def go(self) -> None:
        target = self.fs.value('go-env')
        if target == 'off' or not target.startswith('/'):
            return
        root = self.fs.anchor(self.planner.paths.parent(target))
        text = read_text(target) if self.file(target) else ''
        self.add(self.candidate('go.env', self.rendered('go', text)), target, root, 'apply')

    def system(self) -> None:
        system_root = self.context['system_root']
        result = self.fs.query('mirror-sources', system_root)
        if set(result) != {'paths'} or not isinstance(result['paths'], list) or any(not isinstance(path, str) for path in result['paths']):
            raise ProtocolError('Invalid native mirror source list')
        for source in result['paths']:
            kind = 'apt' if '/apt/' in source else 'dnf' if '/yum.repos.d/' in source else 'pacman'
            if kind != self.context['manager']:
                continue
            text = read_text(source)
            if kind == 'pacman':
                branch = self.fs.value('manjaro-branch')
                if branch and not re.fullmatch('/[a-zA-Z0-9-]+', branch):
                    raise MirrorError('Invalid Manjaro branch')
                text = pacman_text(text, self.mode, 'manjaro' if branch else 'arch', branch,
                                   self.current, self.previous, self.legacy)
            else:
                text = self.rendered(kind, text)
            with tempfile.NamedTemporaryFile(prefix='system.', dir=self.scratch, delete=False) as candidate:
                candidate.write(text.encode('utf-8', errors='surrogateescape'))
                path = candidate.name
            self.add(path, source, self.fs.anchor(system_root), 'apply', privilege='sudo' if system_root == '/' else 'none')

    def state(self) -> None:
        target = self.config + '/dotfiles/mirror-state.conf'
        candidate = self.candidate('state.conf', STATE + '\n' + config_text(self.current))
        owned = not self.exists(target) or (self.file(target) and has_marker(target, STATE))
        self.add(candidate, target, self.fs.anchor(self.config), self.mode, owned)

    def plan(self) -> list[dict[str, str]]:
        for operation in (self.environment, self.cargo, self.npm, self.go, self.system, self.state):
            operation()
        return self.planner.rows


OPERATIONS = frozenset(('mirror-plan-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation == 'mirror-plan-native':
        rows = Mirrors(context, native_filesystem('unix', context['native_shell'])).plan()
        schema = Contract.load('apply-plan')
        return rows, [schema.row(row) for row in rows]
    raise MirrorError('Unknown mirror operation')
