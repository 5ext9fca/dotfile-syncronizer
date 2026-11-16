"""Compatibility imports; declarations are owned by dotfile-viewer."""
from dotfile_viewer.software import *
from dotfile_viewer.api import catalog_root
from dotfile_viewer.software import read_catalog as _read_catalog

def read_catalog(directory=None):
    if directory is None or Path(directory).resolve() == Path(__file__).resolve().parents[1] / "software/items":
        directory = catalog_root() / "software/items"
    return _read_catalog(directory)
