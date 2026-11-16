"""Installation declaration adapters; parsing belongs to Viewer."""
from pathlib import Path
from dotfiles_viewer.install_config import *
from dotfiles_viewer.install_config import read_items as _read_items
from dotfiles_viewer.api import catalog_root
ROOT = Path(__file__).resolve().parents[1]

def read_items(directory, platform, schema_directory=None):
    if Path(directory).resolve() == ROOT / "software/items":
        directory = catalog_root() / "software/items"
    if schema_directory and Path(schema_directory).resolve() == ROOT / 'install/schema':
        schema_directory = None
    return _read_items(Path(directory), platform, **({'schema_directory': schema_directory} if schema_directory else {}))

def raw_rows(items: list[dict[str, str]]) -> list[str]:
    excluded = {'action', 'reason', 'source_origin', 'state', 'schema_version'}
    fields = [f for f in (ROOT / 'contracts/schema/install-plan.fields').read_text().splitlines() if f not in excluded]
    return ['|'.join(item.get(field, '') for field in fields) for item in items]
