"""Apply operation selection over explicit native filesystem observations.

The planner never mutates a deployment target. Native transactions retain the
before/source signatures, backup operations, journal and guarded recovery.
"""
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
import ntpath
import posixpath
from typing import Protocol

from dotfiles_core.apply_rules import ApplyItem, ApplyConfigError, excluded


@dataclass(frozen=True)
class Entry:
    kind: str
    readable: bool = False
    writable: bool = False
    searchable: bool = False


class Filesystem(Protocol):
    def entry(self, path: str) -> Entry: ...
    def state(self, path: str) -> str: ...
    def tree(self, path: str) -> list[str]: ...
    def anchor(self, path: str) -> str: ...
    def identity(self, path: str) -> str: ...
    def equal(self, source: str, target: str, method: str) -> bool: ...


@dataclass(frozen=True)
class Paths:
    windows: bool = False
    case_insensitive: bool = False

    @property
    def module(self):
        return ntpath if self.windows else posixpath

    def key(self, value: str) -> str:
        value = self.module.normpath(value)
        return value.lower() if self.case_insensitive else value

    def join(self, root: str, *parts: str) -> str:
        return self.module.normpath(self.module.join(root, *parts))

    def parent(self, path: str) -> str:
        parent = self.module.dirname(path)
        if not parent or parent == path:
            raise ApplyConfigError(f'Cannot ascend beyond deployment root: {path}')
        return parent

    def within(self, path: str, root: str) -> bool:
        path, root = self.key(path), self.key(root)
        separator = '\\' if self.windows else '/'
        return path == root or path.startswith(root.rstrip(separator) + separator)

    def overlaps(self, left: str, right: str) -> bool:
        return self.within(left, right) or self.within(right, left)


def safe(path: str) -> str:
    if any(character in path for character in ('|', '\t', '\r', '\n', '\0')):
        raise ApplyConfigError(f'Unsupported path character: {path!r}')
    return path


@dataclass
class Planner:
    filesystem: Filesystem
    session: str
    style: str = 'unix'
    paths: Paths = field(default_factory=Paths)
    rows: list[dict[str, str]] = field(default_factory=list)
    directories: dict[str, bool] = field(default_factory=dict)

    def add(self, component: str, action: str, target: str, root: str, reason: str,
            *, source: str = '', backup: str = '', before: str = '', source_state: str = '',
            privilege: str = 'none') -> None:
        self.rows.append(dict(component=component, action=action, source=source, target=target,
                              backup=backup, before=before, source_state=source_state, root=root,
                              privilege=privilege, reason=reason, schema_version='1'))

    def virtual(self, path: str) -> bool:
        return any(virtual and self.paths.within(path, known) for known, virtual in self.directories.items())

    def backup(self, component: str, target: str) -> str:
        suffix = str(len(self.rows) + 1) if self.style == 'windows' else target.lstrip('/')
        return self.paths.join(self.session, 'files', component, suffix)

    def directory(self, component: str, path: str, root: str, privilege: str = 'none') -> None:
        key = self.paths.key(path)
        if key == self.paths.key(root) or key in self.directories:
            return
        if not self.paths.within(path, root):
            raise ApplyConfigError('Target directory is outside its anchor')
        parent = self.paths.parent(path)
        self.directory(component, parent, root, privilege)
        virtual = self.virtual(parent)
        if not virtual and self.filesystem.entry(path).kind == 'directory':
            self.directories[key] = False
            return
        before = 'absent' if virtual else self.filesystem.state(path)
        # Preserve the existing observation sequence when a path changed during
        # planning; execution still verifies the recorded signatures.
        if before != 'absent' and self.filesystem.entry(path).kind == 'directory':
            self.directories[key] = False
            return
        self.add(component, 'mkdir', path, root, 'directory', before=before,
                 backup=self.backup(component, path) if before != 'absent' else '', privilege=privilege)
        self.directories[key] = True

    def file(self, component: str, method: str, source: str, target: str, root: str,
             privilege: str = 'none') -> None:
        parent = self.paths.parent(target)
        self.directory(component, parent, root, privilege)
        if self.style == 'unix':
            entry = self.filesystem.entry(source)
            if entry.kind != 'file' or not entry.readable:
                raise ApplyConfigError(f'Unreadable or unsupported source: {source}')
            source_state = self.filesystem.state(source)
        before = 'absent' if self.virtual(parent) else self.filesystem.state(target)
        if self.style == 'unix':
            nearest = parent
            while self.virtual(nearest) or self.filesystem.entry(nearest).kind != 'directory':
                nearest = self.paths.parent(nearest)
            entry = self.filesystem.entry(nearest)
            if privilege != 'sudo' and not (entry.writable and entry.searchable):
                raise ApplyConfigError(f'Target parent is not writable: {nearest}')
            if method == 'hardlink' and self.filesystem.identity(source).split(':')[0] != self.filesystem.identity(nearest).split(':')[0]:
                raise ApplyConfigError(f'Hard link crosses filesystems: {source} -> {target}')
        action, reason, backup = method, 'new', ''
        if before != 'absent':
            reason, backup = 'replace', self.backup(component, target)
            comparable = self.style == 'windows' or self.filesystem.entry(target).kind == 'file'
            if comparable and self.filesystem.equal(source, target, method):
                action, reason, backup = 'skip', 'unchanged', ''
        if self.style == 'windows':
            source_state = self.filesystem.state(source)
        self.add(component, action, target, root, reason, source=source, backup=backup,
                 before=before, source_state=source_state, privilege=privilege)

    def components(self, items: Sequence[ApplyItem], repo: str, config: str, selection: Sequence[str] | None,
                   *, roots: dict[str, str] | None = None, supported: Callable[[str], bool] = lambda condition: not condition,
                   render: Callable[[ApplyItem, 'Planner'], None] | None = None) -> list[dict[str, str]]:
        if selection is not None and (not selection or list(selection) == ['none']):
            return self.rows
        roots = roots if roots is not None else {'config_home': config, 'local_app_data': config}
        known = {item.id for item in items}
        for name in selection or ():
            if name not in known:
                raise ApplyConfigError(f'Unknown component: {name}')
        targets = []
        for item in items:
            if selection is not None and item.id not in selection:
                continue
            selected_root = roots.get(item.target_root, '')
            if not selected_root or not self.paths.module.isabs(selected_root):
                raise ApplyConfigError(f'Missing or non-absolute target root: {item.target_root}')
            safe(selected_root)
            target = self.paths.join(selected_root, item.target)
            if item.condition and not supported(item.condition):
                self.add(item.id, 'skip', target, selected_root, 'requires-native-linux-kde')
                continue
            source = safe(self.paths.join(repo, item.source))
            safe(target)
            if self.paths.overlaps(target, repo) or self.paths.overlaps(target, self.session):
                raise ApplyConfigError('Source, target or backup paths overlap')
            if any(self.paths.overlaps(target, other) for other in targets):
                raise ApplyConfigError('Overlapping component destinations')
            targets.append(target)
            probe = source
            while self.paths.key(probe) != self.paths.key(repo):
                if self.filesystem.entry(probe).kind == 'link':
                    raise ApplyConfigError(f'Source symlink: {probe}')
                probe = self.paths.parent(probe)
            if self.style == 'windows' and self.filesystem.entry(repo).kind == 'link':
                raise ApplyConfigError('Source parent is a reparse point')
            root = self.filesystem.anchor(selected_root)
            kind = self.filesystem.entry(source).kind
            if kind == 'directory':
                entries = self.filesystem.tree(source)
                self.directory(item.id, target, root)
                key = (lambda value: value.encode('utf-16-be', errors='surrogatepass')) if self.style == 'windows' else None
                for entry in sorted(entries, key=key):
                    safe(entry)
                    relative = self.paths.module.relpath(entry, source)
                    if self.style == 'windows':
                        relative = relative.replace('\\', '/')
                    child_target = self.paths.join(target, relative)
                    # PowerShell's exact equality was case-insensitive; its
                    # descendant prefix comparison remains ordinal.
                    omitted = excluded(relative, item.exclude) or (self.style == 'windows' and
                        any(relative.lower() == value.lower() for value in item.exclude.split(';') if value))
                    if omitted:
                        self.add(item.id, 'skip', child_target, root, 'excluded', source=entry)
                        continue
                    child_kind = self.filesystem.entry(entry).kind
                    if child_kind == 'directory':
                        self.directory(item.id, child_target, root)
                    elif child_kind == 'file':
                        self.file(item.id, item.method, entry, child_target, root)
                    else:
                        raise ApplyConfigError(f'Unsupported source: {entry}')
            elif kind == 'file':
                if item.exclude:
                    raise ApplyConfigError('File components cannot use exclusions')
                self.file(item.id, item.method, source, target, root)
            else:
                raise ApplyConfigError(f'Missing or unsupported source: {source}')
            if item.renderer:
                if render is None:
                    raise ApplyConfigError('Renderer requires caller-owned scratch')
                render(item, self)
        return self.rows
