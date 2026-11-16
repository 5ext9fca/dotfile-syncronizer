"""Source/environment selection and demand-driven installation dependencies.

Observation is explicit and supplied by the native adapter. Historical success
is never an observation, and installation-only dependencies are expanded only
when the current item's action requires them.
"""
from collections import deque
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import json

from dotfiles_core.contracts import Contract
from dotfiles_core.errors import CoreError

Item = dict[str, str]
Observer = Callable[[Item, str], Item]


class PlanningError(CoreError):
    pass


def excluded(item: Mapping[str, str]) -> bool:
    return item.get('reason', '').startswith(('provided-by-host:', 'environment-not-selected:'))


def prepare(items: Sequence[Mapping[str, str]], mirrors: bool, wsl: bool) -> list[Item]:
    """Make an offline plan without invoking any host or application probe."""
    result = []
    version = str(Contract.load('install-plan').version)
    environment = 'wsl' if wsl else 'native'
    for declaration in items:
        item = dict(declaration)
        item.update(schema_version=version, action='install', reason='requested', source_origin='config',
                    state='', detected_method='', detected_paths='', decision_reason='offline-preferred-method')
        if mirrors and item.get('mirror_url'):
            item.update(source_url=item['mirror_url'], source_origin='mirror')
        if wsl and item.get('wsl_provider'):
            item.update(action='skip', reason='provided-by-host:' + item['wsl_provider'], state='provider:' + item['wsl_provider'])
        elif item.get('environments') and environment not in item['environments'].split():
            item.update(action='skip', reason='environment-not-selected:' + environment)
        if excluded(item):
            item['decision_reason'] = item['reason']
        result.append(item)
    return result


def select(items: Sequence[Mapping[str, str]], roots: str, mode: str = 'offline',
           observe: Observer | None = None) -> list[Item]:
    if mode not in ('offline', 'normal', 'resume'):
        raise PlanningError('Invalid installation selection mode')
    if mode != 'offline' and observe is None:
        raise PlanningError('Installation selection requires an observer')
    indexed = {item['id']: item for item in items}
    pending = deque(indexed if roots == 'all' else [] if roots == 'none' else roots.split())
    selected = {}
    while pending:
        identity = pending.popleft()
        if identity in selected:
            continue
        if identity not in indexed:
            raise PlanningError(f'Unknown profile install item {identity}')
        item = dict(indexed[identity])
        if mode != 'offline' and not excluded(item):
            item = observe(item, mode)
            if item.get('id') != identity:
                raise PlanningError('Installation observation identity mismatch')
        selected[identity] = item
        install_only = item.get('install_depends_on', '').split()
        for dependency in item.get('depends_on', '').split():
            if item.get('action') == 'skip' and dependency in install_only:
                continue
            pending.append(dependency)
    # Emit only after all required observations succeeded, in validated order.
    return [selected[item['id']] for item in items if item['id'] in selected]


def components(associations: str, items: Sequence[Mapping[str, str]],
               available: Sequence[str] | None = None) -> list[str]:
    indexed = {item['id']: item for item in items}
    result = []
    for pair in ([] if associations == 'none' else associations.split()):
        component, separator, identity = pair.partition(':')
        if not separator:
            if available is not None and component not in available:
                raise PlanningError(f'Unknown apply component {component}')
            result.append(component)
            continue
        if identity not in indexed:
            raise PlanningError(f'Component {component} requires unknown install item {identity}')
        if excluded(indexed[identity]):
            raise PlanningError(f'Component {component} requires excluded install item {identity}')
        if available is not None and component not in available:
            raise PlanningError(f'Unknown apply component {component}')
        result.append(component)
    return result


def preparation(platform: str, items: Sequence[Mapping[str, str]]) -> tuple[list[str], list[str]]:
    """Choose preparation from pending recipes, without querying the host."""
    pending = {item['method'] for item in items if item['action'] != 'skip'
               and not (item['method'] == 'apt-or-snap' and item.get('state', '').startswith('snap:'))}
    actions, messages = [], []
    if platform == 'linux.apt' and pending.intersection(('apt', 'apt-repository', 'apt-or-snap')):
        actions.append('apt-update')
        messages.append('Preparation: sudo apt-get update')
    elif platform == 'linux.pacman':
        if 'rustup' in pending:
            actions.append('pacman-rust-conflict')
            messages.append('Preparation: remove conflicting rust-analyzer if installed.')
        if 'pacman' in pending:
            actions.append('pacman-upgrade')
            messages.append('Preparation: sudo pacman -Syu --noconfirm (required for pending native installation).')
    elif platform == 'linux.dnf':
        messages.append('Preparation: DNF refreshes metadata only for pending installation.')
    elif platform == 'macos':
        messages.append('Preparation: only missing Xcode/Homebrew prerequisites; Xcode GUI initialization may defer execution.')
    return actions, messages


@dataclass(frozen=True)
class Observation:
    method: str = ''
    paths: tuple[str, ...] = ()

    @property
    def state(self) -> str:
        return 'discovered:' + self.method if self.method else ''

    def evidence(self) -> str:
        return json.dumps(self.paths, ensure_ascii=False, separators=(',', ':')).replace('|', r'\u007c') if self.method else ''


def discover(specification: str, match: Callable[[str, str, str], str], *, inspect_all: bool = False) -> Observation:
    """Group alternative methods while preserving each adapter's probe extent.

    Unix historically stops after the first completely matching method. Windows
    observes all declared paths before choosing the first match, so later probe
    errors must still propagate there. Native adapters retain path resolution,
    accessibility checks and filesystem observation.
    """
    groups = {}
    ordered_queries = []
    for specification_part in specification.split(';') if specification else []:
        fields = specification_part.split(':', 3)
        if len(fields) != 4:
            raise PlanningError('Malformed discovery plan')
        method, kind, root, relative = fields
        groups.setdefault(method, []).append((kind, root, relative))
        ordered_queries.append((method, kind, root, relative))
    if inspect_all:
        matched = {method: [] for method in groups}
        missing = set()
        for method, kind, root, relative in ordered_queries:
            path = match(kind, root, relative)
            if path:
                matched[method].append(path)
            else:
                missing.add(method)
        for method in groups:
            if method not in missing:
                return Observation(method, tuple(matched[method]))
        return Observation()
    first = Observation()
    for method, queries in groups.items():
        paths = []
        matches = True
        for kind, root, relative in queries:
            path = match(kind, root, relative)
            if path:
                paths.append(path)
            else:
                matches = False
        if matches and not first.method:
            first = Observation(method, tuple(paths))
            return first
    return first


OPERATIONS = frozenset(('install-prepare', 'install-components', 'install-preparation'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    from pathlib import Path
    from dotfiles_core.install_config import read_items, ROOT
    from dotfiles_core.execution_rules import execution_policy
    schema = Contract.load('install-plan')
    if operation == 'install-preparation':
        items = context['items']
        if isinstance(items, str):
            items = schema.read(schema.from_rows(items, validate_plan=True))
        actions, messages = preparation(context['platform'], items)
        return {'actions': actions, 'messages': messages}, messages if str(context['preview']) == '1' else actions
    if operation == 'install-prepare':
        execution_policy('*', 'install')
        items = read_items(Path(context['directory']), context['platform'], Path(context.get('schema', ROOT / 'install/schema')))
        prepared = prepare(items, str(context['mirrors']) == '1', str(context['wsl']) == '1')
        return prepared, [schema.row(item) for item in prepared]
    if operation == 'install-components':
        items = context['items']
        if isinstance(items, str):
            items = schema.read(schema.from_rows(items))
        result = components(context['associations'], items, context.get('available'))
        return result, result
    raise PlanningError('Unknown installation planning operation')
