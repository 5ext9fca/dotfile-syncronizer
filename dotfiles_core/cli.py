"""Internal core entry point. Public script CLIs remain platform-owned."""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys

from dotfiles_core.errors import CoreError, RuntimeRequirementError
from dotfiles_core.runtime import require_runtime


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    commands.add_parser('runtime-check')
    for name in ('native-input', 'native-result'):
        command = commands.add_parser(name)
        command.add_argument('--request', type=Path, required=True)
        command.add_argument('--platform', choices=('unix', 'windows'), required=True)
        command.add_argument('--payload', type=Path, required=True)
        if name == 'native-result':
            command.add_argument('--result', type=Path, required=True)
            command.add_argument('--code', type=int, required=True)
    command = commands.add_parser('core-request')
    command.add_argument('--request', type=Path, required=True)
    command.add_argument('--result', type=Path, required=True)
    command.add_argument('--arguments-file', type=Path)
    command = commands.add_parser('core-result')
    command.add_argument('--result', type=Path, required=True)
    command.add_argument('--expected-operation', required=True)
    command.add_argument('--code', type=int, required=True)
    command.add_argument('--verify-only', action='store_true')
    command = commands.add_parser('install-read')
    command.add_argument('--directory', type=Path, required=True)
    command.add_argument('--platform', required=True)
    command.add_argument('--schema', type=Path)
    command.add_argument('--json', action='store_true')
    for name in ('profile-read', 'profile-format', 'stage-plan', 'execution-policy', 'probe-result', 'install-decision', 'execution-result'):
        command = commands.add_parser(name)
        command.add_argument('--json', action='store_true')
        if name == 'profile-read':
            command.add_argument('--path', type=Path, required=True)
        elif name == 'profile-format':
            command.add_argument('--text', default='')
        elif name == 'stage-plan':
            command.add_argument('--platform', required=True)
            command.add_argument('--profile', default='')
            command.add_argument('--only', default='')
            command.add_argument('--from-stage', default='')
            command.add_argument('--mirrors', choices=('0', '1'), default='1')
            command.add_argument('--registry', type=Path)
        elif name == 'execution-policy':
            command.add_argument('--method', default='*')
            command.add_argument('--native-operation', default='install')
            command.add_argument('--path', type=Path)
        elif name in ('probe-result', 'install-decision'):
            command.add_argument('--state', default='')
            if name == 'install-decision':
                command.add_argument('--mode', required=True)
                command.add_argument('--probe-command', default='')
                command.add_argument('--command-present', choices=('0', '1'), default='0')
                command.add_argument('--discovery', choices=('0', '1'), default='0')
        elif name == 'execution-result':
            command.add_argument('--code', type=int, required=True)
            command.add_argument('--dry', choices=('0', '1'), default='0')
    return parser


def dispatch(args: argparse.Namespace) -> tuple[object, list[str]]:
    from dotfiles_core.install_config import ROOT
    match args.operation:
        case 'install-read':
            from dotfiles_core.install_config import raw_rows, read_items
            items = read_items(args.directory, args.platform, args.schema or ROOT / 'install/schema')
            return items, raw_rows(items)
        case 'profile-read' | 'profile-format':
            from dotfiles_core.workflow_rules import read_profile, settings, profile_text
            profile = read_profile(args.path) if args.operation == 'profile-read' else settings(args.text)
            lines = profile_text(profile)
            return (profile if args.operation == 'profile-read' else lines), lines
        case 'stage-plan':
            from dotfiles_core.workflow_rules import stage_plan, settings
            plan = stage_plan(args.platform, settings(args.profile), args.only, args.from_stage,
                              args.mirrors == '1', args.registry or ROOT / 'workflow/schema/stages.tsv')
            return [record.document() for record in plan], [record.text() for record in plan]
        case 'execution-policy':
            from dotfiles_core.execution_rules import execution_policy
            policy = execution_policy(args.method, args.native_operation, args.path or ROOT / 'install/schema/execution.tsv')
            return asdict(policy), [policy.text()]
        case 'probe-result':
            from dotfiles_core.execution_rules import probe_result
            result = probe_result(args.state)
            return result, [result['Action'] + '|' + result['Reason']]
        case 'install-decision':
            from dotfiles_core.execution_rules import install_decision
            decision = install_decision(args.state, args.mode, args.probe_command, args.command_present == '1', args.discovery == '1')
            return asdict(decision), [decision.text()]
        case 'execution-result':
            from dotfiles_core.execution_rules import execution_result
            result = execution_result(args.code, args.dry == '1')
            return result, [result['Status'] + '|' + result['Reason']]
    raise CoreError('Unsupported core operation')


def main() -> int:
    args = build_parser().parse_args()
    try:
        require_runtime()
        if args.operation == 'runtime-check':
            # Preserve the venv path, not its symlink target.
            print(sys.executable)
        elif args.operation == 'native-input':
            from dotfiles_core.native_protocol import arguments
            arguments(args.request, args.payload, args.platform)
        elif args.operation == 'native-result':
            from dotfiles_core.native_protocol import finish
            finish(args.request, args.result, args.code, args.payload, args.platform)
        elif args.operation == 'core-request':
            from dotfiles_core.requests import run, prepare
            if args.arguments_file:
                prepare(args.arguments_file, args.request)
            return run(args.request, args.result)
        elif args.operation == 'core-result':
            from dotfiles_core.requests import read_result
            lines = read_result(args.result, args.expected_operation, args.code)
            if not args.verify_only:
                for line in lines:
                    sys.stdout.buffer.write((line + '\n').encode('utf-8'))
        else:
            document, lines = dispatch(args)
            if args.json:
                print(json.dumps(document, ensure_ascii=False))
            else:
                for line in lines:
                    print(line)
        return 0
    except (CoreError, OSError, UnicodeError) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 2 if isinstance(exc, RuntimeRequirementError) else getattr(exc, 'exit_code', 1)
