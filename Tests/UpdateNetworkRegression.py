#!/usr/bin/env python3
"""Real Sparkle checks against a disposable loopback server; never installs."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import os
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(__file__).with_name('UpdateNetworkCheck.swift')

with tempfile.TemporaryDirectory(prefix='songwave-update-network-') as folder:
    root = Path(folder)
    archive = subprocess.check_output(['bash', str(ROOT/'Tools/fetch-sparkle.sh')], text=True).strip()
    subprocess.run(['tar', '-xJf', archive, '-C', str(root)], check=True)
    app = root/'NetworkFixture.app'
    contents = app/'Contents'
    (contents/'MacOS').mkdir(parents=True)
    (contents/'Frameworks').mkdir()
    subprocess.run(['ditto', '--norsrc', '--noextattr', str(root/'Sparkle.framework'),
                    str(contents/'Frameworks/Sparkle.framework')], check=True)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                    '-F', str(root), '-framework', 'Sparkle', '-Xlinker', '-rpath',
                    '-Xlinker', '@executable_path/../Frameworks', str(SOURCE),
                    '-o', str(contents/'MacOS/NetworkCheck')], check=True)
    # No production keys, preference domain, app bundle or public feed are used.
    key_script = root/'key.swift'
    key_script.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())
''')
    public_key = subprocess.check_output(['xcrun', 'swift', str(key_script), str(root/'key')], text=True).strip()
    (root/'key').chmod(0o600)
    # Bind without listening: reserve one URL and produce an actual ECONNREFUSED.
    reserved = socket.socket()
    reserved.bind(('127.0.0.1', 0))
    port = reserved.getsockname()[1]
    info = plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='studio.songwave.updater-test.'+uuid.uuid4().hex,
                CFBundleExecutable='NetworkCheck', CFBundleName='SongWave Network Test',
                CFBundleVersion='1', CFBundleShortVersionString='0.0.1', LSUIElement=True,
                SUFeedURL=f'http://127.0.0.1:{port}/appcast.xml', SUPublicEDKey=public_key,
                NSAppTransportSecurity={'NSAllowsLocalNetworking':True,
                    'NSExceptionDomains':{'127.0.0.1':{'NSExceptionAllowsInsecureHTTPLoads':True}}})
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    (contents/'Helpers').mkdir()
    shutil.copy2(contents/'MacOS/NetworkCheck', contents/'Helpers/SongWaveYouTubeHost')
    env = dict(os.environ, SONGWAVE_SIGNING_IDENTITY='-')
    subprocess.run(['bash', str(ROOT/'Tools/sign-app.sh'), str(app)], env=env, check=True, capture_output=True)
    payload = root/'update.zip'
    payload.write_bytes(b'Not downloaded: approval is deliberately withheld.')
    signature = subprocess.check_output([str(root/'bin/sign_update'), '--ed-key-file', str(root/'key'), '-p', str(payload)], text=True).strip()
    feed = root/'appcast.xml'
    feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Disposable network test</title><item>
<title>Test build 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
<enclosure url="http://127.0.0.1:{port}/update.zip" sparkle:edSignature="{signature}" length="{payload.stat().st_size}" type="application/octet-stream"/>
</item></channel></rss>''')
    subprocess.run([str(root/'bin/sign_update'), '--ed-key-file', str(root/'key'), str(feed)], check=True, capture_output=True)
    data = feed.read_bytes()
    requests = []
    release = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_GET(self):
            mode = (root/'phase').read_text()
            requests.append((mode, self.path))
            (root/'requested').write_text(mode)
            if mode == 'hang':
                release.wait(30)
                self.close_connection = True
                return
            if mode == 'disconnect':
                self.close_connection = True
                return
            if mode in ('http503', 'background503'):
                self.send_error(503)
                return
            if self.path != '/appcast.xml':
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/rss+xml')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data[:31] if mode == 'truncated' else data)
            self.close_connection = True

    before = hashlib.sha256((contents/'MacOS/NetworkCheck').read_bytes()).hexdigest()
    process = subprocess.Popen([str(contents/'MacOS/NetworkCheck')], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    server = None
    try:
        deadline = time.monotonic()+120
        previous = None
        while process.poll() is None:
            if time.monotonic() > deadline:
                raise TimeoutError('Updater network integration exceeded 120 seconds')
            phase = (root/'phase').read_text() if (root/'phase').exists() else None
            if phase is not None and phase != previous:
                if phase != 'refused' and server is None:
                    reserved.close()
                    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
                    threading.Thread(target=server.serve_forever, daemon=True).start()
                (root/'ready').write_text(phase)
                previous = phase
            time.sleep(.01)
        output, errors = process.communicate()
        print(output, end='')
        if process.returncode:
            raise RuntimeError(errors)
        assert not any(path != '/appcast.xml' for _, path in requests), 'Payload requested before approval'
        assert sum(mode.startswith('valid') for mode, _ in requests) == 6
        assert {'http503', 'disconnect', 'truncated', 'hang', 'background503'} <= {mode for mode, _ in requests}
        assert hashlib.sha256((contents/'MacOS/NetworkCheck').read_bytes()).hexdigest() == before
        assert plistlib.loads((contents/'Info.plist').read_bytes())['CFBundleVersion'] == '1'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    finally:
        if process.poll() is None:
            process.kill(); process.communicate()
        release.set()
        if server:
            server.shutdown(); server.server_close()
        reserved.close()
        # Also clean up after a failed assertion/timeout in the child process.
        subprocess.run(['/usr/bin/defaults', 'delete', info['CFBundleIdentifier']], capture_output=True)
