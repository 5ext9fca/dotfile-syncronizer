import unittest

from dotfiles_core.install_config import ROOT
from dotfiles_core.mirror_rules import MirrorError, read_config, config_text, render, replace_endpoint, environment


class MirrorRuleTests(unittest.TestCase):
    def setUp(self):
        self.current = read_config((ROOT / 'mirrors/current.conf').read_text())
        self.legacy = read_config((ROOT / 'mirrors/legacy.conf').read_text())

    def test_config_roundtrip_invalid_input_and_environment(self):
        text = config_text(self.current)
        self.assertEqual(read_config(text), self.current)
        for invalid in (text + 'npm=https://duplicate.test\n', text.replace('npm=', 'unknown='),
                        text.replace('npm=', 'npm=with space'), text.replace('go_sumdb=', 'go_sumdb=bad/')):
            with self.assertRaises(MirrorError):
                read_config(invalid)
        values = dict(environment(self.current, ROOT / 'mirrors/schema/environment.tsv'))
        self.assertEqual(values['PIP_INDEX_URL'], self.current['pypi'])

    def test_endpoint_boundary_and_unknown_configuration(self):
        self.assertEqual(replace_endpoint('old/one old-other old "old"', 'old', 'new'),
                         'new/one old-other new "new"')
        current = dict(self.current, ubuntu='https://ubuntu.test', ubuntu_ports='https://ports.test')
        text = 'deb http://archive.ubuntu.com/ubuntu noble main\ndeb https://private.test/repo stable main\n'
        self.assertEqual(render('apt', 'apply', text, current, {}, self.legacy),
                         'deb https://ubuntu.test noble main\ndeb https://private.test/repo stable main\n')
        text = 'GOPROXY=https://private.test\nOTHER=kept\n'
        self.assertEqual(render('go', 'apply', text, self.current, {}, self.legacy),
                         text + 'GOSUMDB=' + self.current['go_sumdb'] + '\n')

    def test_managed_keys_and_final_newline(self):
        current = dict(self.current, npm='https://npm.test', cargo_index='sparse+https://cargo.test/')
        self.assertEqual(render('npm', 'apply', 'save-exact=true', current, {}, self.legacy),
                         'save-exact=true\nregistry=https://npm.test\n')
        text = '[source.rsproxy-sparse]\nregistry = "old"\n[build]\njobs = 7\n'
        self.assertEqual(render('cargo', 'initialize', text, current, {}, self.legacy),
                         '[source.rsproxy-sparse]\nregistry = "sparse+https://cargo.test/"\n[build]\njobs = 7\n')
        self.assertEqual(render('cargo', 'apply', '', current, {}, self.legacy), '')

    def test_fedora_templates_and_initialize_go_values(self):
        current = dict(self.current, fedora='https://fedora.test/linux')
        text = ('metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever\n'
                '#baseurl=http://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Everything/$basearch/os/\n'
                'enabled=1\n')
        expected = ('#metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever\n'
                    'baseurl=https://fedora.test/linux/releases/$releasever/Everything/$basearch/os/\n'
                    'enabled=1\n')
        self.assertEqual(render('dnf', 'initialize', text, current, {}, self.legacy), expected)
        text = 'GOPROXY=' + self.legacy['go_proxy'] + '\nGOSUMDB=custom.sum.test\n'
        self.assertEqual(render('go', 'initialize', text, current, {}, self.legacy), text)
