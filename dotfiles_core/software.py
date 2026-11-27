"""Compatibility imports; declarations are owned by dotfile-viewer."""
from dotfile_viewer.software import *
from dotfile_viewer.software import read_catalog as _read_catalog
from dotfiles_core.install_config import item_directory

def read_catalog(directory=None):
    return _read_catalog(item_directory(directory))
