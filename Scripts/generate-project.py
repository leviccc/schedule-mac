#!/usr/bin/env python3
"""Generate a self-contained Xcode project without third-party tooling."""
from pathlib import Path
import hashlib, json, plistlib
root = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(keyname, isa, **kw):
    key = uid(keyname); objects[key] = dict(isa=isa, **kw); return key
files = {}
for path in ['Shared/Models.swift','App/OCR.swift','App/CampusDeskApp.swift','Widget/CampusWidget.swift']:
    files[path] = obj(path,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>')
seed = obj('seed-json','PBXFileReference',lastKnownFileType='text.json',path='Resources/InitialSchedule.json',sourceTree='<group>')
seedBuild = obj('seed-build','PBXBuildFile',fileRef=seed)
resources = obj('app-resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[seedBuild],runOnlyForDeploymentPostprocessing=0)
app = obj('product-app','PBXFileReference',explicitFileType='wrapper.application',path='CampusDesk.app',sourceTree='BUILT_PRODUCTS_DIR')
widget = obj('product-widget','PBXFileReference',explicitFileType='wrapper.app-extension',path='CampusWidget.appex',sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products','PBXGroup',children=[app,widget],name='Products',sourceTree='<group>')
main = obj('main','PBXGroup',children=list(files.values())+[seed,products],sourceTree='<group>')
base = dict(SWIFT_VERSION='5.0',MACOSX_DEPLOYMENT_TARGET='14.0',SDKROOT='macosx',CLANG_ENABLE_MODULES='YES',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='',CAMPUS_APP_GROUP='$(DEVELOPMENT_TEAM).group.local.schedule.sample')
def configs(name, extra):
    result=[]
    for mode in ['Debug','Release']:
        settings = dict(base, **extra)
        settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if mode=='Debug' else '',DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym')
        result.append(obj(name+mode,'XCBuildConfiguration',name=mode,buildSettings=settings))
    return obj(name+'configs','XCConfigurationList',buildConfigurations=result,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
def sources(name, paths):
    return obj(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[obj(name+p,'PBXBuildFile',fileRef=files[p]) for p in paths],runOnlyForDeploymentPostprocessing=0)
widgetTarget = obj('widget-target','PBXNativeTarget',name='CampusWidget',productName='CampusWidget',productReference=widget,productType='com.apple.product-type.app-extension',buildConfigurationList=configs('widget',dict(PRODUCT_NAME='CampusWidget',PRODUCT_BUNDLE_IDENTIFIER='local.schedule.sample.widget',INFOPLIST_FILE='Config/Widget-Info.plist',CODE_SIGN_ENTITLEMENTS='Config/CampusDesk.entitlements',APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks'])),buildPhases=[sources('widget',['Shared/Models.swift','Widget/CampusWidget.swift'])],buildRules=[],dependencies=[])
proxy = obj('proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=widgetTarget,remoteInfo='CampusWidget')
dep = obj('dependency','PBXTargetDependency',target=widgetTarget,targetProxy=proxy)
embedFile = obj('embedfile','PBXBuildFile',fileRef=widget,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed = obj('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embedFile],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
appTarget = obj('app-target','PBXNativeTarget',name='CampusDesk',productName='CampusDesk',productReference=app,productType='com.apple.product-type.application',buildConfigurationList=configs('app',dict(PRODUCT_NAME='CampusDesk',PRODUCT_BUNDLE_IDENTIFIER='local.schedule.sample',INFOPLIST_FILE='Config/App-Info.plist',CODE_SIGN_ENTITLEMENTS='Config/CampusDesk.entitlements',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'])),buildPhases=[sources('app',['Shared/Models.swift','App/OCR.swift','App/CampusDeskApp.swift']),resources,embed],buildRules=[],dependencies=[dep])
project = obj('project','PBXProject',attributes={'LastUpgradeCheck':'1600','TargetAttributes':{appTarget:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1},'com.apple.Sandbox':{'enabled':1}}},widgetTarget:{'SystemCapabilities':{'com.apple.ApplicationGroups.iOS':{'enabled':1},'com.apple.Sandbox':{'enabled':1}}}}},buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[appTarget,widgetTarget])
def encode(value, depth=0):
    if isinstance(value,dict): return '{\n' + ''.join('\t'*(depth+1)+json.dumps(str(k))+ ' = '+ encode(v,depth+1)+';\n' for k,v in value.items()) + '\t'*depth+'}'
    if isinstance(value,list): return '('+', '.join(encode(x,depth) for x in value)+')'
    return json.dumps(value,ensure_ascii=False)
projectdir=root/'CampusDesk.xcodeproj'; projectdir.mkdir(exist_ok=True)
(projectdir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
common=dict(CFBundleDevelopmentRegion='zh-Hans',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleInfoDictionaryVersion='6.0',CFBundleName='日程',CFBundleDisplayName='日程',CFBundleShortVersionString='0.4.0',CFBundleVersion='4',LSMinimumSystemVersion='$(MACOSX_DEPLOYMENT_TARGET)',CampusAppGroup='$(CAMPUS_APP_GROUP)')
for name,extra in [('App',dict(CFBundlePackageType='APPL',NSPrincipalClass='NSApplication',NSHighResolutionCapable=True)),('Widget',dict(CFBundlePackageType='XPC!',NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}))]:
    with (root/f'Config/{name}-Info.plist').open('wb') as f: plistlib.dump(dict(common,**extra),f)
with (root/'Config/CampusDesk.entitlements').open('wb') as f:
    plistlib.dump({'com.apple.security.app-sandbox':True,'com.apple.security.files.user-selected.read-only':True,'com.apple.security.application-groups':['$(CAMPUS_APP_GROUP)']},f)
schemes=projectdir/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'CampusDesk.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="CampusDesk.app" BlueprintName="CampusDesk" ReferencedContainer="container:CampusDesk.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="CampusDesk.app" BlueprintName="CampusDesk" ReferencedContainer="container:CampusDesk.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(projectdir)
