#!/usr/bin/env python3
"""Exercise Sparkle's real patcher on disposable signed bundles, never launched."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tools'))
from delta_updates import build_patch, manifest, write_checksums

with tempfile.TemporaryDirectory(prefix='songwave-delta-regression-') as temporary:
    temporary = Path(temporary)
    archive = subprocess.check_output(['bash', str(ROOT / 'Tools/fetch-sparkle.sh')], text=True).strip()
    subprocess.run(['tar', '-xJf', archive, '-C', str(temporary)], check=True)
    policy_host = temporary / 'PolicyHost.app'
    (policy_host / 'Contents/MacOS').mkdir(parents=True)
    policy = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    policy['CFBundleIdentifier'] = 'studio.songwave.updater-test.' + uuid.uuid4().hex
    policy['CFBundleExecutable'] = 'Fixture'
    (policy_host / 'Contents/Info.plist').write_bytes(plistlib.dumps(policy))
    shutil.copyfile('/usr/bin/true', policy_host / 'Contents/MacOS/Fixture')
    policy_check = temporary / 'policy-check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                    '-F', str(temporary), '-framework', 'Sparkle', '-Xlinker', '-rpath',
                    '-Xlinker', str(temporary), str(ROOT / 'Tests/UpdatePolicyCheck.swift'),
                    '-o', str(policy_check)], check=True)
    subprocess.run([str(policy_check), str(policy_host)], check=True)
    tool = temporary / 'bin/BinaryDelta'
    apps = []
    # Incompressible and unchanged payload stands in for the bundled vocal model.
    payload = b''.join(hashlib.sha256(str(i).encode()).digest() for i in range(32768))
    for version in ['1', '2']:
        app = temporary / version / 'DeltaFixture.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/Resources').mkdir()
        shutil.copyfile('/usr/bin/true', app / 'Contents/MacOS/Fixture')
        (app / 'Contents/MacOS/Fixture').chmod(0o755)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'studio.songwave.delta-fixture', 'CFBundleExecutable': 'Fixture',
            'CFBundleName': 'DeltaFixture', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': version}))
        (app / 'Contents/Resources/unchanged.bin').write_bytes(payload)
        (app / 'Contents/Resources/version.txt').write_text(version)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
        apps.append(app)
    patch = temporary / '1-2.delta'
    build_patch(tool, apps[0], apps[1], patch, temporary / 'patched/DeltaFixture.app')
    assert patch.stat().st_size < len(payload) // 4
    assert manifest(apps[0]) != manifest(apps[1])
    bad = temporary / 'bad.delta'
    data = bytearray(patch.read_bytes()); data[0] ^= 255; bad.write_bytes(data)
    (temporary / 'bad-output').mkdir()
    rejected = subprocess.run([str(tool), 'apply', str(apps[0]), str(temporary / 'bad-output/App.app'), str(bad)], capture_output=True)
    assert rejected.returncode != 0, 'A corrupted patch was accepted'
    (apps[0] / 'Contents/Resources/version.txt').write_text('wrong base')
    (temporary / 'wrong-output').mkdir()
    rejected = subprocess.run([str(tool), 'apply', str(apps[0]), str(temporary / 'wrong-output/App.app'), str(patch)], capture_output=True)
    assert rejected.returncode != 0, 'A different source bundle was accepted'
    write_checksums(temporary)
    assert patch.name in (temporary / 'SHA256SUMS').read_text()
    print('Real signed-bundle delta reconstruction, unchanged payload, wrong-base rejection, corrupt-patch rejection and checksums passed.')
