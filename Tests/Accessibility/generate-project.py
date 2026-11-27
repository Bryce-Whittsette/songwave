#!/usr/bin/env python3
"""Generate a disposable project around production views and fake I/O edges."""
from pathlib import Path
import hashlib, shutil, sys
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
source = out / 'Sources'; source.mkdir(exist_ok=True)
files = ['Studio', 'Source', 'ListeningSetup', 'GlassControls', 'Signal', 'Equalizer', 'RhythmDSP', 'VocalFocus',
         'HapticPattern', 'SignalDisplay', 'VisualActivity', 'MotionAccessibility', 'ListeningHealth', 'AudioAccessHealth',
         'ListeningSupport', 'PlaybackAccess', 'PlayerWindowVisibility']
for name in files: shutil.copyfile(root/'Sources'/f'{name}.swift', source/f'{name}.swift')
# Reuse the exact production Console without the application's @main scene,
# updater or menu-bar lifecycle. Audio/hardware edges remain fake.
console = (root/'Sources/SongWave.swift').read_text()
(source/'Console.swift').write_text('import AppKit\nimport SwiftUI\n\n' + console[console.index('struct Console: View'):])
for path in [root/'Tests/Support/StudioTestEdges.swift', root/'Tests/Accessibility/FixtureApp.swift']:
    shutil.copyfile(path, source/path.name)
shutil.copyfile(root/'Tests/Accessibility/AccessibilityUITests.swift', out/'AccessibilityUITests.swift')
def key(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(name, text):
    ident=key(name); objects.append(f'{ident} = {{ {text} }};'); return ident
refs=[]; builds=[]
for path in sorted(source.glob('*.swift')):
    ref=obj('ref'+path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Sources/{path.name}"; sourceTree = "<group>";')
    refs.append(ref); builds.append(obj('build'+path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
tref=obj('testref','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AccessibilityUITests.swift; sourceTree = "<group>";')
tbuild=obj('testbuild',f'isa = PBXBuildFile; fileRef = {tref};')
app=obj('appref','isa = PBXFileReference; explicitFileType = wrapper.application; path = SongWaveAccessibilityFixture.app; sourceTree = BUILT_PRODUCTS_DIR;')
test=obj('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AccessibilityUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; name = Products; children = ({app},{test}); sourceTree = "<group>";')
group=obj('group',f'isa = PBXGroup; children = ({",".join(refs+[tref,products])}); sourceTree = "<group>";')
aphase=obj('appsource',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
tphase=obj('testsource',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({tbuild}); runOnlyForDeploymentPostprocessing = 0;')
common='ALWAYS_SEARCH_USER_PATHS = NO; ONLY_ACTIVE_ARCH = YES; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 26.0; SWIFT_VERSION = 5.0; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; SWIFT_STRICT_CONCURRENCY = minimal; GENERATE_INFOPLIST_FILE = YES; ENABLE_HARDENED_RUNTIME = NO;'
projectcfg=obj('projectcfg',f'isa = XCBuildConfiguration; name = Debug; buildSettings = {{ {common} }};')
acfg=obj('appcfg',f'isa = XCBuildConfiguration; name = Debug; buildSettings = {{ {common} PRODUCT_NAME = SongWaveAccessibilityFixture; PRODUCT_BUNDLE_IDENTIFIER = studio.songwave.accessibility.fixture; }};')
tcfg=obj('testcfg',f'isa = XCBuildConfiguration; name = Debug; buildSettings = {{ {common} PRODUCT_NAME = AccessibilityUITests; PRODUCT_BUNDLE_IDENTIFIER = studio.songwave.accessibility.tests; TEST_TARGET_NAME = SongWaveAccessibilityFixture; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/../Frameworks","@loader_path/../Frameworks"); }};')
def configs(name, cfg): return obj(name,f'isa = XCConfigurationList; buildConfigurations = ({cfg}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
apcfg=configs('appconfigs',acfg); tpcfg=configs('testconfigs',tcfg); pcfg=configs('projectconfigs',projectcfg)
appTarget=obj('appTarget',f'isa = PBXNativeTarget; name = SongWaveAccessibilityFixture; productName = SongWaveAccessibilityFixture; productType = "com.apple.product-type.application"; productReference = {app}; buildConfigurationList = {apcfg}; buildPhases = ({aphase}); dependencies = (); buildRules = ();')
proxy=obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {key("project")}; proxyType = 1; remoteGlobalIDString = {appTarget}; remoteInfo = SongWaveAccessibilityFixture;')
dep=obj('dep',f'isa = PBXTargetDependency; target = {appTarget}; targetProxy = {proxy};')
target=obj('testtarget',f'isa = PBXNativeTarget; name = AccessibilityUITests; productName = AccessibilityUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = {test}; buildConfigurationList = {tpcfg}; buildPhases = ({tphase}); dependencies = ({dep}); buildRules = ();')
project=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; TargetAttributes = {{ {target} = {{ TestTargetID = {appTarget}; }}; }}; }}; buildConfigurationList = {pcfg}; compatibilityVersion = "Xcode 14.0"; mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({appTarget},{target});')
bundle=out/'Accessibility.xcodeproj'; (bundle/'xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True)
(bundle/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
def buildable(ident,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Accessibility.xcodeproj"/>'
(bundle/'xcshareddata/xcschemes/Accessibility.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{buildable(appTarget,'SongWaveAccessibilityFixture.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable(target,'AccessibilityUITests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(appTarget,'SongWaveAccessibilityFixture.app')}</BuildableProductRunnable></LaunchAction></Scheme>''')
print(bundle)
