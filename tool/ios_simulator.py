#!/usr/bin/env python3
"""Boot an available iPhone simulator and record its UDID for Actions."""
import json
import os
import subprocess

result = subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True)
devices = json.loads(result)['devices']
candidates = [d for runtime, entries in devices.items() if 'iOS' in runtime for d in entries if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not candidates:
    raise SystemExit('No available iPhone simulator runtime is installed')
device = sorted(candidates, key=lambda d: (d['state'] != 'Booted', d['name']))[0]
if device['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True, timeout=300)
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f"IOS_SIMULATOR_UDID={device['udid']}\n")
print(f"iPhone simulator ready: {device['name']} ({device['udid']})")
