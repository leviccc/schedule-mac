#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/日程.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/InitialSchedule.json "$APP/Contents/Resources/InitialSchedule.json"
swiftc -O -D LOCAL_PREVIEW -parse-as-library Shared/Models.swift App/OCR.swift App/CampusDeskApp.swift -o "$APP/Contents/MacOS/CampusDesk" -module-cache-path /tmp/campus-module-cache
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='CampusDesk',CFBundleIdentifier='local.schedule.sample.preview.ready',CFBundleName='日程',CFBundleDisplayName='日程',CFBundlePackageType='APPL',CFBundleShortVersionString='0.3',CFBundleVersion='3',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True),f)
PY
codesign --force --sign - "$APP"
printf '已生成：%s\n' "$APP"
