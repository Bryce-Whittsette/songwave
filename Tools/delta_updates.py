"""Build signed, verified Sparkle patches; never touch an installed app."""
from pathlib import Path
import hashlib
import plistlib
import re
import stat
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
RELEASES = 'https://github.com/Bryce-Whittsette/songwave/releases/download/'


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(1_048_576):
            digest.update(block)
    return digest.hexdigest()


def manifest(bundle):
    """Compare content, links and normal permissions, not ignored timestamps."""
    result = {}
    for path in sorted(Path(bundle).rglob('*')):
        relative = str(path.relative_to(bundle))
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            result[relative] = ('link', path.readlink().as_posix())
        elif stat.S_ISDIR(mode):
            result[relative] = ('directory', stat.S_IMODE(mode))
        elif stat.S_ISREG(mode):
            digest = sha256_file(path)
            result[relative] = ('file', stat.S_IMODE(mode), digest)
        else:
            raise ValueError('Unsupported bundle entry: ' + relative)
    return result


def build_patch(binary_delta, old_app, new_app, patch, patched_app):
    patched_app.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(binary_delta), 'create', '--version', '4',
                    str(old_app), str(new_app), str(patch)], check=True)
    subprocess.run([str(binary_delta), 'apply', str(old_app), str(patched_app), str(patch)], check=True)
    if manifest(patched_app) != manifest(new_app):
        raise ValueError('The reconstructed delta app does not match the full update.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(patched_app)], check=True)


def prepare_deltas(root, folder, info, rss, tools, account):
    """Use up to three signed published bases, each verified before unpacking."""
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    archive = folder / 'SongWave-macOS.zip'
    entries = []
    for item in rss.findall('channel/item')[:3]:
        old_version = item.findtext(f'{{{NS}}}shortVersionString', '')
        old_build = item.findtext(f'{{{NS}}}version', '')
        enclosure = item.find('enclosure')
        if not re.fullmatch(r'\d+\.\d+\.\d+', old_version) or not old_build.isdigit():
            raise ValueError('Invalid signed delta base version.')
        if enclosure is None or enclosure.get('url') != f'{RELEASES}v{old_version}/SongWave-macOS.zip':
            raise ValueError('Unexpected delta base URL.')
        entries.append((old_version, old_build, enclosure))
    with tempfile.TemporaryDirectory(prefix='songwave-deltas-') as scratch:
        scratch = Path(scratch)
        subprocess.run(['ditto', '-x', '-k', str(archive), str(scratch / 'target')], check=True)
        target = scratch / 'target/SongWave.app'
        for old_version, old_build, enclosure in entries:
            old_zip = scratch / f'{old_build}.zip'
            expected_size = int(enclosure.get('length', '0'))
            if not 0 < expected_size <= 268_435_456:
                raise ValueError('Invalid delta base archive size.')
            with urllib.request.urlopen(enclosure.get('url'), timeout=60) as response, old_zip.open('wb') as output:
                count = 0
                while block := response.read(1_048_576):
                    count += len(block)
                    if count > expected_size:
                        raise ValueError('Delta base exceeds its signed length.')
                    output.write(block)
            subprocess.run(['xcrun', 'swift', str(root / 'Tools/verify-update.swift'), '--base',
                            str(root / 'updates/appcast.xml'), str(old_zip), f'v{old_version}'], check=True)
            old_dir = scratch / f'base-{old_build}'
            subprocess.run(['ditto', '-x', '-k', str(old_zip), str(old_dir)], check=True)
            old_app = old_dir / 'SongWave.app'
            old_info = plistlib.loads((old_app / 'Contents/Info.plist').read_bytes())
            if old_info.get('CFBundleVersion') != old_build:
                raise ValueError('Delta base build mismatch.')
            patch = folder / f'SongWave-{old_build}-{build}.delta'
            build_patch(tools / 'BinaryDelta', old_app, target, patch,
                        scratch / f'patched-{old_build}/SongWave.app')
            if patch.stat().st_size >= archive.stat().st_size:
                patch.unlink()
                continue
            signature = subprocess.check_output([str(tools / 'sign_update'), '--account', account,
                                                  '-p', str(patch)], text=True).strip()
            attributes = {'url': f'{RELEASES}v{version}/{patch.name}',
                          f'{{{NS}}}deltaFrom': old_build,
                          f'{{{NS}}}edSignature': signature,
                          'length': str(patch.stat().st_size), 'type': 'application/octet-stream',
                          f'{{{NS}}}deltaFromSparkleExecutableSize': str(
                              (old_app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle').stat().st_size)}
            yield attributes
            print(f'Verified patch from {old_version}: {patch.stat().st_size:,} bytes '
                  f'({100 * patch.stat().st_size / archive.stat().st_size:.1f}% of full download).')


def write_checksums(folder):
    names = sorted(p.name for p in folder.iterdir() if p.suffix in ('.zip', '.dmg', '.delta'))
    lines = []
    for name in names:
        lines.append(sha256_file(folder / name) + '  ' + name)
    (folder / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
