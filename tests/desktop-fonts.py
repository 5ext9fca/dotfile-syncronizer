#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
import sys
import tempfile
import subprocess

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('fonts', Path(__file__).resolve().parents[1] / 'apply/renderers/desktop-fonts.py')
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class RendererTests(unittest.TestCase):
    def test_declared_families(self):
        source = Path(__file__).resolve().parents[1] / 'configs/fontconfig/60-dotfiles-fonts.conf'
        regular, mono, required = fonts.read_families(source)
        self.assertEqual(regular, 'Noto Sans CJK SC')
        self.assertEqual(mono, 'JetBrainsMono Nerd Font')
        self.assertEqual(set(required), {'Noto Sans CJK SC', 'JetBrainsMono Nerd Font'})
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / 'fonts.conf'
            candidate.write_text(source.read_text().replace('Noto Sans CJK SC', 'Custom UI').replace('JetBrainsMono Nerd Font', 'Custom Mono'))
            regular, mono, required = fonts.read_families(candidate)
            self.assertEqual((regular, mono), ('Custom UI', 'Custom Mono'))
            self.assertEqual(set(required), {'Custom UI', 'Custom Mono'})
            rendered = fonts.render('kdeglobals', '', regular, mono)
            self.assertIn('font=Custom UI,', rendered)
            self.assertIn('fixed=Custom Mono,', rendered)

    def test_invalid_fontconfig(self):
        source = Path(__file__).resolve().parents[1] / 'configs/fontconfig/60-dotfiles-fonts.conf'
        text = source.read_text()
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / 'fonts.conf'
            for invalid in ('not XML', '<fontconfig/>', '<other/>',
                            text.replace('system-ui', 'other-ui'),
                            text.replace('Noto Sans CJK SC', 'Bad,Family'),
                            text.replace('Noto Sans CJK SC', 'Bad&#10;Family'),
                            text.replace('system-ui', 'sans-serif'),
                            '<!DOCTYPE fontconfig [<!ENTITY f "Test">]><fontconfig/>'):
                candidate.write_text(invalid)
                with self.assertRaises((ValueError, fonts.ET.ParseError)):
                    fonts.read_families(candidate)

    def test_cli(self):
        source = Path(__file__).resolve().parents[1] / 'configs/fontconfig/60-dotfiles-fonts.conf'
        renderer = str(Path(fonts.__file__))
        listed = subprocess.check_output([sys.executable, renderer, '--families', str(source)], text=True)
        self.assertEqual(listed.splitlines(), ['Noto Sans CJK SC', 'JetBrainsMono Nerd Font'])
        with tempfile.TemporaryDirectory() as directory:
            original = Path(directory) / 'settings.ini'
            output = Path(directory) / 'candidate.ini'
            original.write_text('[Settings]\ngtk-font-name=Old Bold 12\nother=kept\n')
            subprocess.run([sys.executable, renderer, 'gtk-3.0/settings.ini', str(original), str(output), str(source)], check=True)
            self.assertEqual(output.read_text(), '[Settings]\ngtk-font-name=Noto Sans CJK SC Bold 12\nother=kept\n')
            self.assertIn('Old Bold 12', original.read_text())

    def setUp(self):
        fonts.kde_default = lambda group, key: 'Inherited,8.5,-1,5,50,0,0,0,0,0'
        fonts.gtk_default = lambda version: 'Inherited 11.5'

    def test_preserve_and_repeat(self):
        original = '# comment\n[General]\nfont=Old,13,-1,5,50,0,0,0,0,0\nXftAntialias=true\n[Other]\nuntouched=value\n'
        actual = fonts.render('kdeglobals', original, 'Example UI', 'Example Mono')
        self.assertIn('font=Example UI,13,-1,5,50,0,0,0,0,0', actual)
        self.assertIn('fixed=Example Mono,8.5,', actual)
        self.assertIn('# comment\n', actual)
        self.assertIn('XftAntialias=true\n', actual)
        self.assertIn('[Other]\nuntouched=value\n', actual)
        self.assertEqual(fonts.render('kdeglobals', actual, 'Example UI', 'Example Mono'), actual)

    def test_gtk(self):
        for version in (3, 4):
            kind = f'gtk-{version}.0/settings.ini'
            actual = fonts.render(kind, '[Settings]\ngtk-font-name=Old Sans Bold 12px\ngtk-xft-dpi=147456\n', 'Example UI', 'Example Mono')
            self.assertIn('gtk-font-name=Example UI Bold 12px\n', actual)
            self.assertIn('gtk-xft-dpi=147456\n', actual)
            self.assertEqual(fonts.render(kind, actual, 'Example UI', 'Example Mono'), actual)
            self.assertIn('gtk-font-name=Example UI 11.5', fonts.render(kind, '', 'Example UI', 'Example Mono'))

    def test_unsafe(self):
        for text in ('[General]\nfont=bad\n', '[General]\nfont[$i]=whatever\n',
                     '[General][$i]\nfont=whatever\n', '[General]\n[General]\n',
                     '[Settings]\ngtk-font-name=one 10\ngtk-font-name=two 12\n',
                     '[Settings]\ngtk-font-name=missing-size\n', 'not INI'):
            kind = 'gtk-3.0/settings.ini' if '[Settings]' in text else 'kdeglobals'
            with self.assertRaises(ValueError):
                fonts.render(kind, text, 'Example UI', 'Example Mono')


if __name__ == '__main__':
    unittest.main()
