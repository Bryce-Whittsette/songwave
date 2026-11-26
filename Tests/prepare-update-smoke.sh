#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?Usage: bash Tests/prepare-update-smoke.sh /new/test-folder}"
port="${2:-28945}"
[[ "$port" =~ ^[0-9]+$ ]] && ((port > 1024 && port < 65536)) || exit 1
[[ ! -e "$output" ]] || { printf 'Choose a new test folder.\n' >&2; exit 1; }
mkdir -p "$output/server" "$output/client" "$output/results"
output="$(cd "$output" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/songwave-update-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
tar -xJf "$(bash "$project/Tools/fetch-sparkle.sh")" -C "$scratch"
cp -X "$project/Tests/UpdateSmokeHost.swift" "$scratch/"
xcrun swiftc -parse-as-library -swift-version 5 -O -F "$scratch" -framework Sparkle \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  "$scratch/UpdateSmokeHost.swift" -o "$scratch/SmokeHost"
# Test-only key; the production Keychain key is never read or exported here.
cat > "$scratch/key.swift" <<'SWIFT'
import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
public_key="$(xcrun swift "$scratch/key.swift" "$scratch/key")"
chmod 600 "$scratch/key"
python3 - "$output" "$port" "$public_key" <<'PY'
from pathlib import Path
import plistlib, sys, uuid
root=Path(sys.argv[1]); identity='studio.songwave.update-smoke.'+uuid.uuid4().hex
for version, parent in [('1','client'),('2','candidate')]:
    app=root/parent/'SongWave Update Test.app'; (app/'Contents/MacOS').mkdir(parents=True)
    info={'CFBundleExecutable':'SmokeHost','CFBundleIdentifier':identity,'CFBundleName':'SongWave Update Test',
          'CFBundlePackageType':'APPL','CFBundleVersion':version,'CFBundleShortVersionString':'0.0.'+version,
          'NSPrincipalClass':'NSApplication','LSMinimumSystemVersion':'14.2','TestResultFolder':str(root/'results'),
          'SUFeedURL':'http://127.0.0.1:'+sys.argv[2]+'/appcast.xml','SUPublicEDKey':sys.argv[3],
          'SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'SUAutomaticallyUpdate':False,
          'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0,
          'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSExceptionDomains':{'127.0.0.1':{'NSExceptionAllowsInsecureHTTPLoads':True}}}}
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
for parent in client candidate; do
  app="$output/$parent/SongWave Update Test.app"
  cp -X "$scratch/SmokeHost" "$app/Contents/MacOS/SmokeHost"
  mkdir -p "$app/Contents/Frameworks"
  ditto --norsrc --noextattr "$scratch/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
  # Reuse production inside-out signing; this fixture has no YouTube helper.
  mkdir -p "$app/Contents/Helpers"
  cp -X "$scratch/SmokeHost" "$app/Contents/Helpers/SongWaveYouTubeHost"
  bash "$project/Tools/sign-app.sh" "$app"
done
ditto -c -k --norsrc --noextattr --keepParent "$output/candidate/SongWave Update Test.app" "$output/server/update.zip"
signature="$("$scratch/bin/sign_update" --ed-key-file "$scratch/key" -p "$output/server/update.zip")"
python3 - "$output" "$port" "$signature" <<'PY'
from pathlib import Path
import sys, xml.etree.ElementTree as E
root=Path(sys.argv[1]); ns='http://www.andymatuschak.org/xml-namespaces/sparkle'; E.register_namespace('sparkle',ns)
rss=E.Element('rss',version='2.0'); channel=E.SubElement(rss,'channel'); E.SubElement(channel,'title').text='Disposable updater test'
item=E.SubElement(channel,'item'); E.SubElement(item,'title').text='Test build 2'
E.SubElement(item,'{'+ns+'}version').text='2'; E.SubElement(item,'{'+ns+'}shortVersionString').text='0.0.2'
E.SubElement(item,'{'+ns+'}minimumSystemVersion').text='14.2'; E.SubElement(item,'description').text='Updates a disposable test app only.'
E.SubElement(item,'enclosure',{'url':'http://127.0.0.1:'+sys.argv[2]+'/update.zip','{'+ns+'}edSignature':sys.argv[3],'length':str((root/'server/update.zip').stat().st_size),'type':'application/octet-stream'})
E.ElementTree(rss).write(root/'server/appcast.xml',encoding='utf-8',xml_declaration=True)
PY
"$scratch/bin/sign_update" --ed-key-file "$scratch/key" "$output/server/appcast.xml"
cp -X "$output/server/appcast.xml" "$output/valid-appcast.xml"
cp -X "$output/server/update.zip" "$output/valid-update.zip"
printf 'Fixture ready. Serve %s/server on 127.0.0.1:%s and open %s/client/SongWave Update Test.app.\n' "$output" "$port" "$output"
