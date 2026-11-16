import unittest

from dotfiles_core.install_planning import prepare, select, components, PlanningError, discover, preparation


class InstallPlanningTests(unittest.TestCase):
    def test_preparation_only_for_pending_native_recipes(self):
        def item(method, action='install', state=''):
            return dict(method=method, action=action, state=state)
        for items in ([], [item('apt', 'skip')], [item('cargo')], [item('apt-or-snap', state='snap:tool')]):
            self.assertEqual(preparation('linux.apt', items), ([], []))
        for method in ('apt', 'apt-repository', 'apt-or-snap'):
            self.assertEqual(preparation('linux.apt', [item(method)])[0], ['apt-update'])
        self.assertEqual(preparation('linux.pacman', [item('rustup'), item('pacman')])[0],
                         ['pacman-rust-conflict', 'pacman-upgrade'])
        self.assertEqual(preparation('linux.pacman', [item('pacman', 'skip')]), ([], []))
        for platform in ('macos', 'linux.dnf'):
            actions, messages = preparation(platform, [])
            self.assertEqual(actions, [])
            self.assertEqual(len(messages), 1)

    def test_discovery_conjunction_order_and_probe_errors(self):
        calls = []
        def match(kind, root, relative):
            calls.append(relative)
            return '' if relative == 'absent' else '/中文/' + relative
        specification = 'manual:file:home:present;manual:directory:home:absent;manager:file:home:tool|one;last:file:home:later'
        observation = discover(specification, match)
        self.assertEqual(observation.state, 'discovered:manager')
        self.assertEqual(observation.evidence(), '["/中文/tool\\u007cone"]')
        self.assertEqual(calls, ['present', 'absent', 'tool|one'])
        calls.clear()
        self.assertEqual(discover(specification, match, inspect_all=True), observation)
        self.assertEqual(calls, ['present', 'absent', 'tool|one', 'later'])
        def broken(kind, root, relative):
            if relative == 'later':
                raise OSError('inaccessible')
            return '/path/' + relative
        self.assertEqual(discover(specification, broken).method, 'manual')
        with self.assertRaises(OSError):
            discover(specification, broken, inspect_all=True)
        self.assertEqual(discover('', match).evidence(), '')
        calls.clear()
        observation = discover('manual:file:home:first;manager:file:home:second;manual:directory:home:third', match, inspect_all=True)
        self.assertEqual(calls, ['first', 'second', 'third'])
        self.assertEqual(observation.paths, ('/中文/first', '/中文/third'))

    def test_source_environment_and_provider_selection(self):
        declarations = [dict(id='runtime', source_url='upstream', mirror_url='mirror', environments='native wsl', wsl_provider='host'),
                        dict(id='native', environments='native'), dict(id='guest', environments='wsl')]
        native = prepare(declarations, True, False)
        self.assertEqual(native[0]['source_url'], 'mirror')
        self.assertEqual(native[0]['source_origin'], 'mirror')
        self.assertEqual(native[2]['reason'], 'environment-not-selected:native')
        guest = prepare(declarations, False, True)
        self.assertEqual(guest[0]['source_url'], 'upstream')
        self.assertEqual(guest[0]['state'], 'provider:host')
        self.assertEqual(guest[0]['decision_reason'], 'provided-by-host:host')
        self.assertEqual(guest[1]['action'], 'skip')
        self.assertNotIn('action', declarations[0])

    def test_observe_roots_before_install_dependencies(self):
        items = prepare([dict(id='common'), dict(id='builder'), dict(id='unused'),
                         dict(id='app', depends_on='common builder', install_depends_on='builder')], False, False)
        observed = []
        def observer(item, mode):
            observed.append((item['id'], mode))
            return {**item, 'action': 'skip'}
        selected = select(items, 'app', 'resume', observer)
        self.assertEqual([item['id'] for item in selected], ['common', 'app'])
        self.assertEqual(observed, [('app', 'resume'), ('common', 'resume')])
        observed.clear()
        def missing(item, mode):
            observed.append(item['id'])
            return item
        selected = select(items, 'app', 'normal', missing)
        self.assertEqual(observed, ['app', 'common', 'builder'])
        self.assertEqual([item['id'] for item in selected], ['common', 'builder', 'app'])
        self.assertEqual([item['id'] for item in select(items, 'app')], ['common', 'builder', 'app'])

    def test_excluded_items_and_observation_failure(self):
        items = prepare([dict(id='native', environments='native')], False, True)
        def forbidden(item, mode):
            self.fail('excluded item was observed')
        self.assertEqual(select(items, 'all', 'normal', forbidden), items)
        with self.assertRaises(PlanningError):
            components('config:native', items)
        with self.assertRaises(PlanningError):
            select(items, 'missing')
        items = prepare([dict(id='app')], False, False)
        with self.assertRaisesRegex(OSError, 'probe failure'):
            def broken(item, mode):
                raise OSError('probe failure')
            select(items, 'all', 'resume', broken)
        self.assertEqual(components('config:app', items, ['config']), ['config'])
        with self.assertRaises(PlanningError):
            components('config:app', items, [])
