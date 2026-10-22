"""Stable/nightly metadata. No signing secrets or dependency downloads."""
import os
from pathlib import Path
import re
import subprocess
import time
from ci_release import metadata, positive_number, semantic_version

EPOCH = 1_577_836_800  # 2020-01-01; shared by both workflows, not per-workflow counters.


def calculate(pubspec, channel, tags, run_number, *, now=None, ref='refs/heads/main', supplied='', requested='', attempt='1'):
    baseline = metadata(pubspec)
    base = baseline['version']
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', base):
        raise ValueError('pubspec must contain the next stable MAJOR.MINOR.PATCH version')
    if channel not in ('stable', 'nightly'):
        raise ValueError('Unknown release channel')
    if ref != 'refs/heads/main' and not (channel == 'stable' and ref == f'refs/tags/v{base}'):
        raise ValueError('Dispatch from main; stable tags must match pubspec')
    if requested and requested.removeprefix('v') != base:
        raise ValueError('Update pubspec.yaml on main before releasing a different version')
    if channel == 'nightly':
        if f'v{base}' in tags:
            major, minor, patch = map(int, base.split('.'))
            base = f'{major}.{minor}.{patch + 1}'
        version = f'{base}-nightly.{positive_number(run_number)}'
        if positive_number(attempt) > 1:
            version += f'.r{attempt}'
    else:
        version = base
    semantic_version(version)
    # Main/nightly share a signed package: independent run counters cause
    # INSTALL_FAILED_VERSION_DOWNGRADE. Serialize flows and use one UTC clock.
    default = max(int(baseline['build_number']), int(time.time() if now is None else now) - EPOCH + 100_000)
    code = positive_number(supplied) if supplied else positive_number(default)
    if code < default:
        raise ValueError('Explicit versionCode must be at least the current time-based default')
    stable = [tag for tag in tags if re.fullmatch(r'v\d+\.\d+\.\d+', tag)
              and tuple(map(int, tag[1:].split('.'))) < tuple(map(int, base.split('.')))]
    previous = max(stable, key=lambda t: tuple(map(int, t[1:].split('.'))), default='')
    return {'version': version, 'build_number': str(code), 'tag': f'v{version}',
            'prerelease': str(channel == 'nightly').lower(), 'previous': previous}


def main():
    channel = os.environ['RELEASE_CHANNEL']
    tags = subprocess.check_output(['git', 'tag', '--merged', 'HEAD'], text=True).splitlines()
    result = calculate(Path('pubspec.yaml').read_text(), channel, tags, os.environ['GITHUB_RUN_NUMBER'],
        ref=os.environ['GITHUB_REF'], supplied=os.environ.get('RELEASE_BUILD_NUMBER', ''),
        requested=os.environ.get('RELEASE_VERSION', ''), attempt=os.environ['GITHUB_RUN_ATTEMPT'])
    flavor = os.environ.get('RELEASE_FLAVOR', 'full')
    result['flavors'] = metadata(Path('pubspec.yaml').read_text(), flavor=flavor)['flavors']
    result['sha'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if channel == 'stable':
        tagged = subprocess.run(['git', 'rev-parse', '--verify', f"refs/tags/{result['tag']}^{{commit}}"], capture_output=True, text=True)
        if tagged.returncode == 0 and tagged.stdout.strip() != result['sha']:
            raise ValueError('This stable version already tags another commit. Bump pubspec on main first.')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in result.items(): output.write(f'{key}={value}\n')
    print(f"{result['tag']} · versionCode {result['build_number']} · {result['sha'][:8]}")


if __name__ == '__main__':
    main()
