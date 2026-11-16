"""Snapshot entry orchestration; callers hold the native deployment lease."""
from pathlib import Path
import json
import os
import platform as host_platform
import shutil
import tempfile
import uuid

from dotfiles_core.errors import CoreError, AdapterError
from dotfiles_core.install_config import ROOT
from dotfiles_core.snapshot import Platform, SnapshotError, capture, verify_archive, targets
from dotfiles_viewer.api import SnapshotSession as ViewerSession, catalog_root, deployment_lease
from dotfiles_viewer.host import host, host_roots
from dotfiles_core.software import read_catalog, profile_selection, write_catalog
from dotfiles_core.apply_planning import Paths
from dotfiles_core.apply_execution import NativeExecution
from dotfiles_core.native_preflight import NativePreflight
from dotfiles_core.native_installation import native_installation
from dotfiles_core.workflow_preflight import Inputs, prepare, validate_plan_outputs
from dotfiles_core.workflow_packages import NativePreparation, run as packages_run, boolean
from dotfiles_core.workflow_session import Session, Stage, StageExecution, run as session_run


def native_values(platform, shell):
    if platform.branch == 'windows':
        return dict(ProgramFiles=os.environ.get('ProgramFiles', ''),
                    VsInstallerRoot=str(Path(os.environ.get('ProgramFiles(x86)', '')) / 'Microsoft Visual Studio/Installer'),
                    git_config_paths=[], git_settings=[])
    brew = shutil.which('brew')
    prefix = '/opt/homebrew' if platform.architecture == 'arm64' else '/usr/local'
    if brew and platform.branch == 'macos':
        prefix = NativePreflight('unix', shell, Paths()).string('brew-prefix', [brew])
        if not Path(prefix).is_absolute():
            raise SnapshotError('Homebrew returned a non-absolute prefix')
    distro = host_platform.freedesktop_os_release() if platform.branch.startswith('linux.') else {}
    return dict(brew_cmd=brew or prefix + '/bin/brew', brew_prefix=prefix,
                distro_id=distro.get('ID', ''), distro_codename=distro.get('UBUNTU_CODENAME', distro.get('VERSION_CODENAME', '')),
                inside_wsl=platform.environment == 'wsl', user=os.environ.get('USER', ''),
                mirror_config=str(ROOT / 'mirrors/current.conf'))


class SnapshotSession:
    def __init__(self, native, runner, directory, platform, style, dry, snapshot, scratch, roots, session, install):
        self.native, self.runner, self.directory = native, runner, directory
        self.platform, self.style, self.dry = platform, style, dry
        self.snapshot, self.scratch, self.roots, self.session, self.install = snapshot, scratch, roots, session, install
        self.viewer = None
        self.detach = False

    def publish(self, path, text, mode='replace'):
        self.native.publish(str(path), text, mode)

    def execute(self, action, report, metadata, log):
        try:
            self.publish(log, f'Snapshot stage: {action}\nNative command output is streamed to the invoking terminal.\n')
            if action == 'packages':
                def refresh():
                    return self.runner.plan(str(self.directory), self.platform.branch, False,
                        self.platform.environment == 'wsl', self.install, 'normal')
                def install(items):
                    result = self.runner.execute(items, dry=self.dry, resume=False, results=str(report), style=self.style)
                    if result.exit_code:
                        raise AdapterError('Snapshot software installation failed', result.exit_code)
                packages_run(self.style, self.platform.branch, self.dry, refresh, install,
                             NativePreparation(self.runner.adapter.operations['install-command'][0]))
                return StageExecution(0)
            result = self.viewer.apply(dry=self.dry, detach=self.detach)
            self.publish(report, json.dumps(result, ensure_ascii=False))
            return StageExecution(0)
        except (CoreError, OSError, ValueError) as exc:
            message = str(exc)
            print('error: ' + message, flush=True)
            self.publish(log, f'Snapshot stage: {action}\nerror: {message}\n')
            return StageExecution(getattr(exc, 'exit_code', 1), message)


def restore_snapshot(path, current, shell, roots, backup, dry=False, configuration_only=False, detach=False):
    style = 'windows' if current.branch == 'windows' else 'unix'
    native = NativeExecution(style, shell)
    with deployment_lease(dry=dry) as lease, ViewerSession(path, platform=current, roots=roots, backup=backup, protected=[ROOT]) as viewer:
        scratch = viewer.scratch
        snapshot = viewer.snapshot
        if snapshot.platform != current:
            raise SnapshotError(f'Snapshot platform mismatch: {snapshot.platform.document()} != {current.document()}')
        # Validate aliases and protected paths before installation or any persistent report.
        destinations = targets(snapshot.software, roots)
        input_path = Path(path).resolve()
        for target in destinations.values():
            if input_path == target or input_path.is_relative_to(target):
                raise SnapshotError('Input snapshot overlaps configuration destination')
        directory = scratch / 'software/items'
        write_catalog(snapshot.software, directory)
        profiles = scratch / 'workflow/profiles'
        profiles.mkdir(parents=True)
        (profiles / 'snapshot.conf').write_text('schema_version=3\nsoftware=' + ' '.join(snapshot.selection) + '\n', encoding='utf-8')
        identity = 'snapshot-' + uuid.uuid4().hex
        paths = Paths(windows=os.name == 'nt', case_insensitive=True)
        inputs = Inputs(str(scratch), current.branch, style, 'snapshot', identity,
                        roots.get('config_home', roots.get('local_app_data', '')), str(backup), dry, False, False,
                        native=native_values(current, shell) if not configuration_only else {}, roots=roots)
        preflight = NativePreflight(style, shell, paths)
        if configuration_only:
            # No installation probes or package-manager prerequisites for apply.
            from dotfiles_core.workflow_preflight import assert_output
            session = Path(preflight.resolve_root(str(backup))) / ('workflow-' + identity)
            assert_output(str(session), [str(ROOT), *map(str, destinations.values())], preflight, paths, style)
            install = 'none'
            runner = None
        else:
            prepared = prepare(inputs, preflight, paths)
            session = Path(prepared.session)
            install = prepared.profile['install']
            runner = native_installation(style, shell, preflight.install_context)
        from dotfiles_core.workflow_preflight import assert_output
        assert_output(str(session), [str(ROOT), str(input_path), *map(str, destinations.values())], preflight, paths, style)
        viewer.preview()
        if not dry and not detach and any(row['detach_required'] for row in viewer.preview()['items']):
            raise SnapshotError('Confirm --detach-hardlink before installing or applying a snapshot')
        stages = (Stage('packages', not configuration_only and install != 'none', 'configuration-only' if configuration_only else '', 'packages'),
                  Stage('configuration', True, '', 'configuration'))
        context = scratch / 'context'
        context.mkdir()
        settings = Session(identity, session, 'snapshot', current.branch, style, dry, False, stages, context_directory=context)
        operations = SnapshotSession(native, runner, directory, current, style, dry, snapshot, scratch, roots, session, install)
        operations.viewer = viewer
        operations.detach = detach
        # Explicit nesting is used when the API caller, rather than a native wrapper, owns the lease.
        original_apply = viewer.apply
        viewer.apply = lambda **kwargs: original_apply(lease=lease, **kwargs)
        result = session_run(settings, operations)
        if result.exit_code:
            raise AdapterError('Snapshot restore failed; inspect the session and rerun with the snapshot after resolving the cause', result.exit_code)
        return result


OPERATIONS = frozenset(('snapshot-native',))


def request(operation, context):
    if operation not in OPERATIONS:
        raise SnapshotError('Unknown snapshot operation')
    action = context['action']
    dry = boolean(context.get('dry', False))
    if action == 'inspect':
        snapshot = verify_archive(context['snapshot'])
        return snapshot.document(), [json.dumps(snapshot.document(), ensure_ascii=False, indent=2)]
    elif action == 'create':
        profile = context.get('profile', '')
        names = context.get('software', [])
        if isinstance(names, str):
            names = names.split()
        if bool(profile) == bool(names):
            raise SnapshotError('Specify exactly one of profile or software')
        if profile:
            import re
            if not re.fullmatch('[a-z][a-z0-9-]*', profile):
                raise SnapshotError('Invalid profile name')
            names = profile_selection(catalog_root() / 'workflow/profiles' / (profile + '.conf'))
        snapshot = capture(read_catalog(), host(), names, host_roots(), context['output'], dry)
    elif action == 'restore':
        restore_snapshot(context['snapshot'], host(), context['native_shell'], host_roots(),
                         os.environ.get('DOTFILES_BACKUP_DIR', str(Path.home() / '.dotfiles-backups')), dry,
                         boolean(context.get('configuration_only', False)), boolean(context.get('detach_hardlink', False)))
        return None, []
    else:
        raise SnapshotError('Unknown snapshot action')
    summary = dict(platform=snapshot.platform.document(), software=list(snapshot.software),
                   files=sum(e['kind'] == 'file' for e in snapshot.entries), directories=sum(e['kind'] == 'directory' for e in snapshot.entries),
                   created_at=snapshot.created_at, schema_version=snapshot.schema_version,
                   result='preview' if dry else 'verified' if action == 'inspect' else 'created')
    return summary, [json.dumps(summary, ensure_ascii=False, indent=2)]
