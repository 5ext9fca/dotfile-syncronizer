"""Shared observation coordination over native filesystem/package queries."""
from dataclasses import dataclass

from dotfiles_core.errors import ProtocolError
from dotfiles_core.execution_rules import install_decision
from dotfiles_core.install_planning import Item, Observation, discover, excluded
from dotfiles_core.protocol import Adapter


@dataclass
class NativeObservation:
    adapter: Adapter
    context: str | dict
    style: str
    policy_path: str = ''

    def query(self, operation: str, item: Item) -> dict:
        return self.adapter.invoke(operation, {'item': item, 'native_context': self.context,
                                              'mode': 'normal', 'policy_path': self.policy_path}).data

    def discover(self, specification: str) -> Observation:
        def match(kind: str, root: str, relative: str) -> str:
            result = self.adapter.invoke('discovery-path', {
                'kind': kind, 'root': root, 'relative': relative, 'native_context': self.context,
            })
            if set(result.data) != {'path'} or not isinstance(result.data['path'], str):
                raise ProtocolError('Malformed native discovery result')
            return result.data['path']
        return discover(specification, match, inspect_all=self.style == 'windows')

    def observe(self, item: Item, mode: str) -> Item:
        if self.style not in ('unix', 'windows'):
            raise ProtocolError('Unknown observation platform')
        if excluded(item):
            return dict(item)
        observation = Observation()
        if item.get('discovery'):
            observation = self.discover(item['discovery'])
            state = observation.state
        else:
            data = self.query('install-state', item)
            if set(data) != {'state'} or not isinstance(data['state'], str):
                raise ProtocolError('Malformed native installation state')
            state = data['state']
        if self.style == 'unix' and item['method'] == 'docker-ce' and state != 'present':
            if self.query('install-target-check', item):
                raise ProtocolError('Malformed native target check result')
        probe = item.get('probe_command', '') if self.style == 'unix' else ''
        decision = install_decision(state, mode, probe, False, bool(item.get('discovery')))
        if self.style == 'unix' and decision.Action != 'skip' and probe:
            data = self.query('install-command-probe', item)
            if set(data) != {'present'} or type(data['present']) is not bool:
                raise ProtocolError('Malformed native command probe result')
            decision = install_decision(state, mode, probe, data['present'], bool(item.get('discovery')))
        return {**item, 'action': decision.Action, 'reason': decision.Reason, 'state': decision.State,
                'decision_reason': decision.DecisionReason, 'detected_method': observation.method,
                'detected_paths': observation.evidence()}
