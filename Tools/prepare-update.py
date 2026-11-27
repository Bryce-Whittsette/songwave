#!/usr/bin/env python3
"""Create a signed Sparkle feed using the maintainer's local Keychain key."""
from pathlib import Path
import argparse
import base64
import datetime
import email.utils
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from delta_updates import prepare_deltas, write_checksums

ROOT = Path(__file__).resolve().parent.parent
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)

def command(*args):
    return subprocess.check_output(args, text=True).strip()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('release_folder', type=Path)
    parser.add_argument('--full-only', action='store_true', help='Publish only the complete archive, without incremental patches.')
    args = parser.parse_args()
    command('xcrun', 'swift', str(ROOT / 'Tools/verify-update.swift'), '--self-test')
    folder = args.release_folder.resolve()
    archive = folder / 'SongWave-macOS.zip'
    with zipfile.ZipFile(archive) as package:
        info = plistlib.loads(package.read('SongWave.app/Contents/Info.plist'))
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('Use a numeric version and increasing positive build number.')
    expected = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'studio.songwave.trackpad' or info['SUPublicEDKey'] != expected['SUPublicEDKey']:
        raise ValueError('This is not a SongWave archive with the expected update key.')
    notes = ROOT / f'docs/releases/{version}.md'
    if not notes.is_file():
        raise ValueError(f'Write release notes first: {notes}')
    sparkle_archive = command('bash', str(ROOT / 'Tools/fetch-sparkle.sh'))
    with tempfile.TemporaryDirectory(prefix='songwave-update-') as scratch:
        subprocess.run(['tar', '-xJf', sparkle_archive, '-C', scratch], check=True)
        tools = Path(scratch) / 'bin'
        public = command(str(tools / 'generate_keys'), '--account', 'studio.songwave.trackpad', '-p')
        if public != expected['SUPublicEDKey']:
            raise ValueError('The SongWave update key is missing from this Mac’s login Keychain.')
        signature = command(str(tools / 'sign_update'), '--account', 'studio.songwave.trackpad', '-p', str(archive))
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError('Invalid update signature.')
        rss = ET.parse(ROOT / 'updates/appcast.xml').getroot()
        channel = rss.find('channel')
        if channel is None:
            raise ValueError('No update channel.')
        previous = channel.findall('item')
        if previous and int(previous[0].findtext(f'{{{NS}}}version', '0')) >= int(build):
            raise ValueError('The new build number must be greater than the published feed.')
        item = ET.Element('item')
        ET.SubElement(item, 'title').text = f'SongWave {version}'
        ET.SubElement(item, f'{{{NS}}}version').text = build
        ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
        ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
        ET.SubElement(item, f'{{{NS}}}hardwareRequirements').text = 'arm64'
        ET.SubElement(item, f'{{{NS}}}minimumUpdateVersion').text = '13'
        ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
        ET.SubElement(item, 'link').text = f'https://github.com/Bryce-Whittsette/songwave/releases/tag/v{version}'
        # Use a short user-facing section in the update dialog; full developer notes remain on GitHub.
        content = notes.read_text()
        section = re.search(r'^## What changed\s*\n(.*?)(?=^## |^<details>|\Z)', content, re.M | re.S)
        summary = (section.group(1).strip() if section else f'See the release notes for SongWave {version}.')
        ET.SubElement(item, 'description', {f'{{{NS}}}format': 'markdown'}).text = summary
        ET.SubElement(item, 'enclosure', {
            'url': f'https://github.com/Bryce-Whittsette/songwave/releases/download/v{version}/SongWave-macOS.zip',
            f'{{{NS}}}edSignature': signature, 'length': str(archive.stat().st_size), 'type': 'application/octet-stream'})
        for stale in folder.glob(f'SongWave-*-{build}.delta'): stale.unlink()
        if list(folder.glob('*.delta')): raise ValueError('Use a fresh folder; unrelated delta files are present.')
        if not args.full_only:
            for attributes in prepare_deltas(ROOT, folder, info, rss, tools, 'studio.songwave.trackpad'):
                deltas = item.find(f'{{{NS}}}deltas')
                if deltas is None: deltas = ET.SubElement(item, f'{{{NS}}}deltas')
                ET.SubElement(deltas, 'enclosure', attributes)
        write_checksums(folder)
        channel.insert(4, item)
        for older in previous[9:]: channel.remove(older)
        output = folder / 'appcast.xml'
        ET.ElementTree(rss).write(output, encoding='utf-8', xml_declaration=True)
        subprocess.run([str(tools / 'sign_update'), '--account', 'studio.songwave.trackpad', str(output)], check=True)
        subprocess.run(['xcrun', 'swift', str(ROOT / 'Tools/verify-update.swift'), str(output), str(archive), f'v{version}'], check=True)
        print(f'Ready: signed update archive and {output}. No private key was exported.')

if __name__ == '__main__':
    main()
