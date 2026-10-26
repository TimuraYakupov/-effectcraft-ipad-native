#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project using only Python's standard library."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(key, isa, **fields):
    identifier = uid(key)
    objects[identifier] = dict(isa=isa, **fields)
    return identifier

def format_value(value, level=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (level + 1) + json.dumps(k) + ' = ' + format_value(v, level + 1) + ';\n' for k,v in value.items()) + '\t' * level + '}'
    if isinstance(value, list):
        return '(' + ', '.join(format_value(v, level) for v in value) + ')'
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)

sources = sorted((ROOT / 'RuPocket').glob('*.swift'))
tests = sorted((ROOT / 'RuPocketTests').glob('*.swift'))
resources = sorted((ROOT / 'RuPocket' / 'Web').glob('*')) + [ROOT / 'RuPocket' / 'Assets.xcassets', ROOT / 'RuPocket' / 'PrivacyInfo.xcprivacy']
refs = []
source_builds, test_builds, resource_builds = [], [], []
for path in sources + tests + resources:
    relative = path.relative_to(ROOT).as_posix()
    filetype = {'.swift':'sourcecode.swift', '.js':'sourcecode.javascript', '.css':'text.css', '.xcassets':'folder.assetcatalog', '.xcprivacy':'text.xml'}[path.suffix]
    ref = add(relative, 'PBXFileReference', lastKnownFileType=filetype, path=relative, sourceTree='SOURCE_ROOT')
    refs.append(ref)
    build = add(relative + ':build', 'PBXBuildFile', fileRef=ref)
    (source_builds if path in sources else test_builds if path in tests else resource_builds).append(build)

app_product = add('app:product', 'PBXFileReference', explicitFileType='wrapper.application', path='RuPocket.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
test_product = add('tests:product', 'PBXFileReference', explicitFileType='wrapper.cfbundle', path='RuPocketTests.xctest', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
products = add('products', 'PBXGroup', children=[app_product, test_product], name='Products', sourceTree='<group>')
main_group = add('group', 'PBXGroup', children=refs+[products], sourceTree='<group>')
app_sources = add('app:sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
app_resources = add('app:resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=resource_builds, runOnlyForDeploymentPostprocessing=0)
app_frameworks = add('app:frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
test_sources = add('tests:sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=test_builds, runOnlyForDeploymentPostprocessing=0)
test_frameworks = add('tests:frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)

def configs(name, settings):
    configs = []
    for kind in ['Debug', 'Release']:
        values = dict(settings)
        if name == 'project':
            values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if kind == 'Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if kind == 'Debug' else 'dwarf-with-dsym', ENABLE_TESTABILITY='YES' if kind == 'Debug' else 'NO', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if kind == 'Debug' else '')
        configs.append(add(name+':'+kind, 'XCBuildConfiguration', buildSettings=values, name=kind))
    return add(name+':configs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

project_configs = configs('project', dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='5.0', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES', GCC_C_LANGUAGE_STANDARD='gnu17', SWIFT_STRICT_CONCURRENCY='minimal', ONLY_ACTIVE_ARCH='NO'))
app_configs = configs('app', dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='org.timuryakupov.RuPocket', INFOPLIST_FILE='RuPocket/Info.plist', GENERATE_INFOPLIST_FILE='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', TARGETED_DEVICE_FAMILY='1', CODE_SIGN_STYLE='Automatic', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks'], MARKETING_VERSION='0.1.0', CURRENT_PROJECT_VERSION='1'))
test_configs = configs('tests', dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='org.timuryakupov.RuPocketTests', GENERATE_INFOPLIST_FILE='YES', TARGETED_DEVICE_FAMILY='1', CODE_SIGN_STYLE='Automatic', TEST_HOST='$(BUILT_PRODUCTS_DIR)/RuPocket.app/RuPocket', BUNDLE_LOADER='$(TEST_HOST)', LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']))
proxy = add('proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType=1, remoteGlobalIDString=uid('app'), remoteInfo='RuPocket')
dependency = add('dependency', 'PBXTargetDependency', target=uid('app'), targetProxy=proxy)
app = add('app', 'PBXNativeTarget', buildConfigurationList=app_configs, buildPhases=[app_sources, app_frameworks, app_resources], buildRules=[], dependencies=[], name='RuPocket', productName='RuPocket', productReference=app_product, productType='com.apple.product-type.application')
test_target = add('tests', 'PBXNativeTarget', buildConfigurationList=test_configs, buildPhases=[test_sources, test_frameworks], buildRules=[], dependencies=[dependency], name='RuPocketTests', productName='RuPocketTests', productReference=test_product, productType='com.apple.product-type.bundle.unit-test')
project = add('project', 'PBXProject', attributes=dict(LastUpgradeCheck='1600', TargetAttributes={app:dict(CreatedOnToolsVersion='16.0'), test_target:dict(CreatedOnToolsVersion='16.0', TestTargetID=app)}), buildConfigurationList=project_configs, compatibilityVersion='Xcode 14.0', developmentRegion='ru', hasScannedForEncodings=0, knownRegions=['ru','en','Base'], mainGroup=main_group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app,test_target])
output = ROOT / 'RuPocket.xcodeproj'
output.mkdir(exist_ok=True)
(output / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + format_value(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + '\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="RuPocket.app" BlueprintName="RuPocket" ReferencedContainer="container:RuPocket.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="RuPocketTests.xctest" BlueprintName="RuPocketTests" ReferencedContainer="container:RuPocket.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="RuPocket.app" BlueprintName="RuPocket" ReferencedContainer="container:RuPocket.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
scheme_dir = output / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'RuPocket.xcscheme').write_text(scheme)
print('Generated RuPocket.xcodeproj')
