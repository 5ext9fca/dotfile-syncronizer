"""Human explanations of current plans, separate from persisted wire formats."""
from pathlib import Path

from dotfiles_core.contracts import Contract
from dotfiles_core.install_config import read_items

OPERATIONS = frozenset(('install-explain', 'apply-explain'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    kind = 'install-plan' if operation == 'install-explain' else 'apply-plan'
    schema = Contract.load(kind)
    items = context.get('records')
    if items is None:
        items = schema.read(schema.from_rows(context['text']))
    lines = []
    if operation == 'install-explain':
        platform, selection = context['platform'], context.get('selection', 'all')
        lines.append(f'Installation selection: {selection}; platform={platform}')
        for index, item in enumerate(items, 1):
            chosen = 'profile' if selection == 'all' or item['id'] in selection.split() else 'dependency'
            lines.append(f"  {index}. {item['id']}: {item['action']} ({item['reason']}); selected-by={chosen}, order={item['order']}, method={item['method']}")
            lines.append(f"     Packages: {item.get('packages', '')}; depends-on: {item.get('depends_on') or 'none'}")
            if item.get('install_depends_on'):
                lines.append('     Installation-only edges (omitted on skip unless independently selected): ' + item['install_depends_on'])
            source = f"     Source: {item['source_kind']} ({item['source_origin']})"
            details = [(label, item.get(key, '')) for label, key in
                       [('url', 'source_url'), ('repository', 'source_repo'), ('release', 'source_release')]]
            source += ''.join(f'; {label}={value}' for label, value in details if value)
            if not any(value for _, value in details):
                source += '; package-manager defaults'
            lines.append(source)
            if item.get('discovery'):
                lines.append(f"     Discovery methods: {item.get('methods') or item['method']}; preferred install: {item.get('preferred_method') or item['method']}")
                lines.append('     Required paths by method (file-system only): ' + item['discovery'])
            if item.get('state'):
                lines.append('     Detected state: ' + item['state'])
        if context.get('directory'):
            directory = Path(context['directory'])
            available = {item['id'] for item in read_items(directory, platform)}
            selected = {item['id'] for item in items}
            for path in sorted(directory.glob('*.conf')):
                if path.stem not in selected:
                    reason = 'not-selected-by-profile' if path.stem in available else 'platform-not-configured'
                    lines.append(f'  {path.stem}: excluded ({reason})')
        lines.append('Presence checks describe installation only; this plan is a current-state preview.')
    else:
        lines.append('Configuration effects:')
        for item in items:
            lines.append(f"  {item['component']}: {item['action']} {item['target']} ({item['reason']})")
            if item.get('source') and item['reason'] != 'excluded':
                lines.append('     Source: ' + item['source'])
            if item.get('backup'):
                lines.append('     Existing target backup: ' + item['backup'])
            if item.get('privilege') == 'sudo':
                lines.append('     Requires elevated file access.')
        lines.append('Unchanged/excluded targets and unmanaged files are preserved.')
    return lines, lines
