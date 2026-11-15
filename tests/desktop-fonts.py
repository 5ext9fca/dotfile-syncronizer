#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('fonts', Path(__file__).resolve().parents[1] / 'apply/renderers/desktop-fonts.py')
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class RendererTests(unittest.TestCase):
    def setUp(self):
        fonts.kde_default = lambda group, key: 'Inherited,8.5,-1,5,50,0,0,0,0,0'
        fonts.gtk_default = lambda version: 'Inherited 11.5'

    def test_preserve_and_repeat(self):
        original = '# comment\n[General]\nfont=Old,13,-1,5,50,0,0,0,0,0\nXftAntialias=true\n[Other]\nuntouched=value\n'
        actual = fonts.render('kdeglobals', original)
        self.assertIn('font=PingFang SC,13,-1,5,50,0,0,0,0,0', actual)
        self.assertIn('fixed=JetBrainsMono Nerd Font,8.5,', actual)
        self.assertIn('# comment\n', actual)
        self.assertIn('XftAntialias=true\n', actual)
        self.assertIn('[Other]\nuntouched=value\n', actual)
        self.assertEqual(fonts.render('kdeglobals', actual), actual)

    def test_gtk(self):
        for version in (3, 4):
            kind = f'gtk-{version}.0/settings.ini'
            actual = fonts.render(kind, '[Settings]\ngtk-font-name=Old Sans Bold 12px\ngtk-xft-dpi=147456\n')
            self.assertIn('gtk-font-name=PingFang SC Bold 12px\n', actual)
            self.assertIn('gtk-xft-dpi=147456\n', actual)
            self.assertEqual(fonts.render(kind, actual), actual)
            self.assertIn('gtk-font-name=PingFang SC 11.5', fonts.render(kind, ''))

    def test_unsafe(self):
        for text in ('[General]\nfont=bad\n', '[General]\nfont[$i]=whatever\n',
                     '[General][$i]\nfont=whatever\n', '[General]\n[General]\n',
                     '[Settings]\ngtk-font-name=one 10\ngtk-font-name=two 12\n',
                     '[Settings]\ngtk-font-name=missing-size\n', 'not INI'):
            kind = 'gtk-3.0/settings.ini' if '[Settings]' in text else 'kdeglobals'
            with self.assertRaises(ValueError):
                fonts.render(kind, text)


if __name__ == '__main__':
    unittest.main()
