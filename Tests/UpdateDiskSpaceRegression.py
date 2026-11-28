#!/usr/bin/env python3
"""Opt-in real Sparkle disk-full test. Only fills a bounded disposable volume."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
import errno, os, plistlib, shutil, socket, subprocess, tempfile, threading, time

repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='songwave-disk-install-') as folder:
    root=Path(folder); mount=root/'volume'; image=root/'fixture.dmg'
    assert shutil.disk_usage(root).free > 512*1024*1024
    sock=socket.socket(); sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]; sock.close()
    fixture=root/'fixture'
    sdk=root/'sdk'; sdk.mkdir()
    archive=subprocess.check_output(['bash',str(repo/'Tools/fetch-sparkle.sh')],text=True).strip()
    subprocess.run(['tar','-xJf',archive,'-C',str(sdk)],check=True)
    executable=root/'DiskCheck'
    subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors',
                    '-F',str(sdk),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',
                    str(repo/'Tests/UpdateDiskSpaceCheck.swift'),'-o',str(executable)],check=True)
    subprocess.run(['bash',str(repo/'Tests/prepare-update-smoke.sh'),str(fixture),str(port)],env=dict(os.environ,SONGWAVE_SIGNING_IDENTITY='-'),check=True,capture_output=True)
    appname='SongWave Update Test.app'
    source=fixture/'client'/appname
    # A real SongWave update is much larger than the framework-only fixture.
    # Ensure the candidate needs more space than APFS's reported reserve.
    candidate=fixture/'candidate'/appname
    resources=candidate/'Contents/Resources'; resources.mkdir(exist_ok=True)
    (resources/'test-payload.bin').write_bytes(os.urandom(16*1024*1024))
    keyscript=root/'key.swift'
    keyscript.write_text('''import Foundation
import CryptoKit
let k=Curve25519.Signing.PrivateKey()
try k.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(k.publicKey.rawRepresentation.base64EncodedString())
''')
    key=root/'key'
    publickey=subprocess.check_output(['xcrun','swift',str(keyscript),str(key)],text=True).strip(); key.chmod(0o600)
    for app in (source,candidate):
        infofile=app/'Contents/Info.plist'; info=plistlib.loads(infofile.read_bytes()); info['SUPublicEDKey']=publickey
        infofile.write_bytes(plistlib.dumps(info))
        subprocess.run(['bash',str(repo/'Tools/sign-app.sh'),str(app)],env=dict(os.environ,SONGWAVE_SIGNING_IDENTITY='-'),check=True,capture_output=True)
    archive=fixture/'server/update.zip'; archive.unlink()
    subprocess.run(['ditto','-c','-k','--norsrc','--noextattr','--keepParent',str(candidate),str(archive)],check=True)
    signer=str(sdk/'bin/sign_update')
    signature=subprocess.check_output([signer,'--ed-key-file',str(key),'-p',str(archive)],text=True).strip()
    import xml.etree.ElementTree as E
    feed=fixture/'server/appcast.xml'; xml=E.parse(feed); enclosure=xml.find('channel/item/enclosure')
    enclosure.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature',signature)
    enclosure.set('length',str(archive.stat().st_size)); xml.write(feed,encoding='utf-8',xml_declaration=True)
    subprocess.run([signer,'--ed-key-file',str(key),str(feed)],check=True,capture_output=True)
    modern=int(subprocess.check_output(['sw_vers','-productVersion'],text=True).split('.')[0])>=27
    create=(['diskutil','image','create','blank','--size','192m','--fs','APFS','--volumeName','SongWaveSpaceTest',str(image)] if modern else
            ['hdiutil','create','-size','192m','-fs','APFS','-volname','SongWaveSpaceTest','-format','UDRW',str(image)])
    created=subprocess.run(create,capture_output=True,text=True,timeout=45)
    if created.returncode: print(created.stderr,flush=True)
    created.check_returncode()
    attached=False; process=None; server=None
    try:
        attach=(['diskutil','image','attach','--nobrowse','--mountPoint',str(mount),str(image)] if modern else
                ['hdiutil','attach','-nobrowse','-mountpoint',str(mount),str(image)])
        mounted=subprocess.run(attach,capture_output=True,text=True,timeout=30)
        if mounted.returncode: print(mounted.stderr,flush=True)
        mounted.check_returncode()
        attached=True
        assert mount.stat().st_dev != root.stat().st_dev and shutil.disk_usage(mount).total < 256*1024*1024
        target=mount/appname
        subprocess.run(['ditto','--norsrc','--noextattr',str(source),str(target)],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(target)],check=True)
        # Keep the updater alive outside its target, as Sparkle's CLI does, so
        # final replacement errors can be observed after target termination.
        driver=root/'Driver.app'; dc=driver/'Contents'
        (dc/'MacOS').mkdir(parents=True); (dc/'Helpers').mkdir()
        shutil.copy2(executable,dc/'MacOS/DiskCheck')
        shutil.copy2(dc/'MacOS/DiskCheck',dc/'Helpers/SongWaveYouTubeHost')
        subprocess.run(['ditto','--norsrc','--noextattr',str(source/'Contents/Frameworks'),str(dc/'Frameworks')],check=True)
        driverinfo=plistlib.loads((source/'Contents/Info.plist').read_bytes())
        driverinfo['CFBundleIdentifier'] += '.driver'; driverinfo['CFBundleExecutable']='DiskCheck'; driverinfo['TestTargetApp']=str(target)
        (dc/'Info.plist').write_bytes(plistlib.dumps(driverinfo))
        subprocess.run(['bash',str(repo/'Tools/sign-app.sh'),str(driver)],env=dict(os.environ,SONGWAVE_SIGNING_IDENTITY='-'),check=True,capture_output=True)
        filler=mount/'test-only-filler'
        written=0
        try:
            with filler.open('wb',buffering=0) as stream:
                block=b'\xa5'*(1024*1024)
                while written < 256*1024*1024:
                    written += stream.write(block)
            raise RuntimeError('Fill cap reached without ENOSPC')
        except OSError as error:
            if error.errno != errno.ENOSPC: raise
        # Retain enough filesystem metadata space for a clean error path.
        with filler.open('r+b') as stream: stream.truncate(max(0,filler.stat().st_size-65536))
        print('Disposable free bytes before install:',shutil.disk_usage(mount).free,flush=True)
        # APFS may report reserved space as free even after writes get ENOSPC.
        assert shutil.disk_usage(mount).free < 8*1024*1024
        class Handler(SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
        server=ThreadingHTTPServer(('127.0.0.1',port),partial(Handler,directory=str(fixture/'server')))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        log=(root/'child.log').open('w')
        process=subprocess.Popen([str(dc/'MacOS/DiskCheck')],stdout=log,stderr=log)
        deadline=time.monotonic()+120; restored=False; passed=False
        while time.monotonic()<deadline:
            state_path=fixture/'results/disk-state'
            state=state_path.read_text() if state_path.exists() else ''
            if state=='disk-full' and not restored:
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1'
                subprocess.run(['codesign','--verify','--deep','--strict',str(target)],check=True)
                filler.unlink(); restored=True
                (fixture/'results/space-restored').write_text('ready')
            if state=='retry-installed':
                assert restored
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='2'
                subprocess.run(['codesign','--verify','--deep','--strict',str(target)],check=True)
                print('Real Sparkle disk-full preservation and retry installation passed.',flush=True)
                passed=True; break
            if state.startswith(('unexpected','start-error','retry-timeout')):
                raise RuntimeError(state)
            if process.poll() not in (None,0): raise RuntimeError('Fixture child failed')
            time.sleep(.05)
        if not passed: raise RuntimeError('Fixture installation timed out')
    finally:
        if process and process.poll() is None: process.kill(); process.wait()
        if server: server.shutdown(); server.server_close()
        childlog=root/'child.log'
        if childlog.exists():
            print('\n'.join(line for line in childlog.read_text().splitlines()
                            if not line.startswith('sandbox_extension_issue_file_to_process')),flush=True)
        identifier=plistlib.loads((source/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
        subprocess.run(['/usr/bin/defaults','delete',identifier],capture_output=True)
        subprocess.run(['/usr/bin/defaults','delete',identifier+'.driver'],capture_output=True)
        if attached:
            # Remove only the uniquely created filler before unmounting.
            (mount/'test-only-filler').unlink(missing_ok=True)
            subprocess.run(['diskutil','eject',str(mount)],check=True,capture_output=True,timeout=30)
