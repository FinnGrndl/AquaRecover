#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-aqua_recover}"
ORG="${AQUA_ORG:-${ORG:-io.github.finngrndl}}"
APP_ID="${AQUA_APP_ID:-$ORG.aquarecover}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter, then rerun this script." >&2
  exit 1
fi
for tool in rsync perl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required. macOS includes it by default, except Python may require Command Line Tools." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

flutter create --project-name "$PROJECT_NAME" --org "$ORG" --platforms=android,ios,macos,windows "$TMP_DIR/$PROJECT_NAME"
rsync -a "$TMP_DIR/$PROJECT_NAME/android/" "$ROOT/android/"
rsync -a "$TMP_DIR/$PROJECT_NAME/ios/" "$ROOT/ios/"
rsync -a "$TMP_DIR/$PROJECT_NAME/macos/" "$ROOT/macos/"
rsync -a "$TMP_DIR/$PROJECT_NAME/windows/" "$ROOT/windows/"

if [ -f "$ROOT/android/app/build.gradle.kts" ]; then
  AQUA_APP_ID="$APP_ID" perl -0pi -e '
    s/minSdk = flutter\.minSdkVersion/minSdk = 24/g;
    s/namespace = "[^"]+"/namespace = "$ENV{AQUA_APP_ID}"/g;
    s/applicationId = "[^"]+"/applicationId = "$ENV{AQUA_APP_ID}"/g;
  ' "$ROOT/android/app/build.gradle.kts"
fi
if [ -f "$ROOT/android/app/build.gradle" ]; then
  AQUA_APP_ID="$APP_ID" perl -0pi -e '
    s/minSdkVersion flutter\.minSdkVersion/minSdkVersion 24/g;
    s/minSdkVersion = flutter\.minSdkVersion/minSdkVersion = 24/g;
    s/namespace\s+["\x27][^"\x27]+["\x27]/namespace "$ENV{AQUA_APP_ID}"/g;
    s/applicationId\s+["\x27][^"\x27]+["\x27]/applicationId "$ENV{AQUA_APP_ID}"/g;
  ' "$ROOT/android/app/build.gradle"
fi
IOS_PROJECT="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
if [ -f "$IOS_PROJECT" ]; then
  AQUA_APP_ID="$APP_ID" perl -0pi -e '
    s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 14.0;/g;
    s/PRODUCT_BUNDLE_IDENTIFIER = [^;]+\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{AQUA_APP_ID}.RunnerTests;/g;
    s/PRODUCT_BUNDLE_IDENTIFIER = (?![^;]*RunnerTests)[^;]+;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{AQUA_APP_ID};/g;
    s/^\s*DEVELOPMENT_TEAM = [^;]+;\n//mg;
  ' "$IOS_PROJECT"
fi

ANDROID_PACKAGE="$APP_ID"
ANDROID_PACKAGE_PATH="${ANDROID_PACKAGE//./\/}"
ANDROID_DEST="$ROOT/android/app/src/main/kotlin/$ANDROID_PACKAGE_PATH"
mkdir -p "$ANDROID_DEST"
sed "s/^package .*/package $ANDROID_PACKAGE/" "$ROOT/platform_overrides/android/app/src/main/kotlin/io/github/finngrndl/aquarecover/MainActivity.kt" > "$ANDROID_DEST/MainActivity.kt"
GENERATED_ANDROID_PACKAGE_PATH="${ORG//./\/}/$PROJECT_NAME"
GENERATED_ANDROID_MAIN="$ROOT/android/app/src/main/kotlin/$GENERATED_ANDROID_PACKAGE_PATH/MainActivity.kt"
if [ "$GENERATED_ANDROID_MAIN" != "$ANDROID_DEST/MainActivity.kt" ]; then
  rm -f "$GENERATED_ANDROID_MAIN"
fi
DEFAULT_ANDROID_MAIN="$ROOT/android/app/src/main/kotlin/io/github/finngrndl/aquarecover/MainActivity.kt"
if [ "$DEFAULT_ANDROID_MAIN" != "$ANDROID_DEST/MainActivity.kt" ]; then
  rm -f "$DEFAULT_ANDROID_MAIN"
fi

ANDROID_MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"
if [ -f "$ANDROID_MANIFEST" ]; then
  python3 - "$ANDROID_MANIFEST" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(
    r'android:label="[^"]+"',
    'android:label="AquaRecover"',
    text,
    count=1,
)
perms = [
    '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />',
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
]
missing = [p for p in perms if p not in text]
if missing:
    text = text.replace('    <application', '\n'.join(missing) + '\n    <application', 1)
path.write_text(text)
PY
fi

rsync -a "$ROOT/platform_overrides/ios/" "$ROOT/ios/"
rsync -a "$ROOT/platform_overrides/macos/" "$ROOT/macos/"

MAC_APP_INFO="$ROOT/macos/Runner/Configs/AppInfo.xcconfig"
if [ -f "$MAC_APP_INFO" ]; then
  AQUA_APP_ID="$APP_ID" perl -0pi -e '
    s/PRODUCT_NAME = .*/PRODUCT_NAME = AquaRecover/g;
    s/PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $ENV{AQUA_APP_ID}/g;
    s/PRODUCT_COPYRIGHT = .*/PRODUCT_COPYRIGHT = Copyright © 2026 AquaRecover contributors. MIT licensed./g;
  ' "$MAC_APP_INFO"
fi

MAC_PROJECT="$ROOT/macos/Runner.xcodeproj/project.pbxproj"
MAC_SCHEME="$ROOT/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"
for file in "$MAC_PROJECT" "$MAC_SCHEME"; do
  if [ -f "$file" ]; then
    AQUA_PROJECT_NAME="$PROJECT_NAME" AQUA_APP_ID="$APP_ID" perl -0pi -e '
      s/\Q$ENV{AQUA_PROJECT_NAME}\E\.app/AquaRecover.app/g;
      s#(BUNDLE_EXECUTABLE_FOLDER_PATH\)/)\Q$ENV{AQUA_PROJECT_NAME}\E"#$1AquaRecover"#g;
      s/PRODUCT_BUNDLE_IDENTIFIER = [^;]+\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{AQUA_APP_ID}.RunnerTests;/g;
    ' "$file"
  fi
done

WINDOWS_CMAKE="$ROOT/windows/CMakeLists.txt"
WINDOWS_MAIN="$ROOT/windows/runner/main.cpp"
WINDOWS_RESOURCES="$ROOT/windows/runner/Runner.rc"
if [ -f "$WINDOWS_CMAKE" ]; then
  perl -0pi -e 's/set\(BINARY_NAME "[^"]+"\)/set(BINARY_NAME "AquaRecover")/' "$WINDOWS_CMAKE"
fi
if [ -f "$WINDOWS_MAIN" ]; then
  perl -0pi -e 's/window\.Create\(L"[^"]+"/window.Create(L"AquaRecover"/' "$WINDOWS_MAIN"
fi
if [ -f "$WINDOWS_RESOURCES" ]; then
  perl -0pi -e '
    s/VALUE "CompanyName", "[^"]+"/VALUE "CompanyName", "AquaRecover contributors"/g;
    s/VALUE "FileDescription", "[^"]+"/VALUE "FileDescription", "AquaRecover underwater color restoration"/g;
    s/VALUE "InternalName", "[^"]+"/VALUE "InternalName", "AquaRecover"/g;
    s/VALUE "LegalCopyright", "[^"]+"/VALUE "LegalCopyright", "Copyright (C) 2026 AquaRecover contributors. MIT licensed."/g;
    s/VALUE "OriginalFilename", "[^"]+"/VALUE "OriginalFilename", "AquaRecover.exe"/g;
    s/VALUE "ProductName", "[^"]+"/VALUE "ProductName", "AquaRecover"/g;
  ' "$WINDOWS_RESOURCES"
fi

python3 - "$ROOT/ios/Runner.xcodeproj/project.pbxproj:RawBridge.swift:AppDelegate.swift" "$ROOT/ios/Runner.xcodeproj/project.pbxproj:IosVideoProcessor.swift:RawBridge.swift" "$ROOT/macos/Runner.xcodeproj/project.pbxproj:RawBridge.swift:MainFlutterWindow.swift" <<'PY'
from pathlib import Path
import hashlib
import re
import sys

def unique_id(text, seed):
    for i in range(100):
        candidate = hashlib.sha1(f'{seed}:{i}'.encode()).hexdigest()[:24].upper()
        if candidate not in text:
            return candidate
    raise RuntimeError(f'Could not allocate a unique Xcode object id for {seed}')

def insert_before(text, marker, addition, label):
    if marker not in text:
        raise RuntimeError(f'Could not find {label} in Xcode project.')
    return text.replace(marker, addition + marker, 1)

def add_swift_source(spec):
    project_path_raw, swift_file, anchor_file = spec.rsplit(':', 2)
    project_path = Path(project_path_raw)
    if not project_path.exists():
        return
    text = project_path.read_text()
    if f'/* {swift_file} in Sources */' in text:
        return

    file_ref = unique_id(text, f'{project_path}:{swift_file}:file')
    build_ref = unique_id(text + file_ref, f'{project_path}:{swift_file}:build')
    build_line = f'\t\t{build_ref} /* {swift_file} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {swift_file} */; }};\n'
    file_line = f'\t\t{file_ref} /* {swift_file} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {swift_file}; sourceTree = "<group>"; }};\n'

    text = insert_before(text, '/* End PBXBuildFile section */', build_line, 'PBXBuildFile section')
    text = insert_before(text, '/* End PBXFileReference section */', file_line, 'PBXFileReference section')

    child_pattern = re.compile(rf'(\n\t\t\t\t[0-9A-F]{{24}} /\* {re.escape(anchor_file)} \*/,\n)')
    text, child_count = child_pattern.subn(rf'\1\t\t\t\t{file_ref} /* {swift_file} */,\n', text, count=1)
    if child_count == 0:
        raise RuntimeError(f'Could not add {swift_file} to the Runner group.')

    source_pattern = re.compile(rf'(\n\t\t\t\t[0-9A-F]{{24}} /\* {re.escape(anchor_file)} in Sources \*/,\n)')
    text, source_count = source_pattern.subn(rf'\1\t\t\t\t{build_ref} /* {swift_file} in Sources */,\n', text, count=1)
    if source_count == 0:
        raise RuntimeError(f'Could not add {swift_file} to the Sources build phase.')

    project_path.write_text(text)

def add_runner_resource(
    project_path,
    resource_file,
    group_anchor,
    phase_anchor,
    resource_path=None,
):
    if not project_path.exists():
        return
    text = project_path.read_text()
    if f'/* {resource_file} in Resources */' in text:
        return

    file_ref = unique_id(text, f'{project_path}:{resource_file}:file')
    build_ref = unique_id(text + file_ref, f'{project_path}:{resource_file}:build')
    build_line = f'\t\t{build_ref} /* {resource_file} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {resource_file} */; }};\n'
    path = resource_path or resource_file
    file_line = f'\t\t{file_ref} /* {resource_file} */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = {path}; sourceTree = "<group>"; }};\n'

    text = insert_before(text, '/* End PBXBuildFile section */', build_line, 'PBXBuildFile section')
    text = insert_before(text, '/* End PBXFileReference section */', file_line, 'PBXFileReference section')

    child_pattern = re.compile(rf'(\n\t\t\t\t[0-9A-F]{{24}} /\* {re.escape(group_anchor)} \*/,\n)')
    text, child_count = child_pattern.subn(rf'\1\t\t\t\t{file_ref} /* {resource_file} */,\n', text, count=1)
    if child_count == 0:
        raise RuntimeError(f'Could not add {resource_file} to the Runner group.')

    resource_pattern = re.compile(rf'(\n\t\t\t\t[0-9A-F]{{24}} /\* {re.escape(phase_anchor)} in Resources \*/,\n)')
    text, resource_count = resource_pattern.subn(rf'\1\t\t\t\t{build_ref} /* {resource_file} in Resources */,\n', text, count=1)
    if resource_count == 0:
        raise RuntimeError(f'Could not add {resource_file} to the Resources build phase.')

    project_path.write_text(text)

for spec in sys.argv[1:]:
    add_swift_source(spec)

ios_project = Path(sys.argv[1].rsplit(':', 2)[0])
add_runner_resource(
    ios_project,
    'PrivacyInfo.xcprivacy',
    'Info.plist',
    'Assets.xcassets',
)
mac_project = Path(sys.argv[3].rsplit(':', 2)[0])
add_runner_resource(
    mac_project,
    'PrivacyInfo.xcprivacy',
    'Info.plist',
    'Assets.xcassets',
    'Runner/PrivacyInfo.xcprivacy',
)
PY

python3 - "$ROOT/ios/Runner.xcodeproj/project.pbxproj" "$ROOT/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme" <<'PY'
from pathlib import Path
import sys

project_path = Path(sys.argv[1])
scheme_path = Path(sys.argv[2])

if project_path.exists():
    path_prefix = (
        'if [ -d \\"$PROJECT_DIR/../scripts/xcode\\" ]; then\\n'
        '  export PATH=\\"$PROJECT_DIR/../scripts/xcode:$PATH\\"\\n'
        'fi\\n'
    )
    guard = (
        'if ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1 && [ -d \\"/Applications/Xcode.app/Contents/Developer\\" ]; then\\n'
        '  export DEVELOPER_DIR=\\"/Applications/Xcode.app/Contents/Developer\\"\\n'
        'fi\\n'
    )
    replacements = {
        'shellScript = "/bin/sh \\"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\\" build";':
            f'shellScript = "{path_prefix}{guard}/bin/sh \\"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\\" build";',
        'shellScript = "/bin/sh \\"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\\" embed_and_thin";':
            f'shellScript = "{path_prefix}{guard}/bin/sh \\"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\\" embed_and_thin";',
    }
    text = project_path.read_text()
    for before, after in replacements.items():
        text = text.replace(before, after)
    project_path.write_text(text)

if scheme_path.exists():
    path_prefix = (
        'if [ -d &quot;$PROJECT_DIR/../scripts/xcode&quot; ]; then&#10;'
        '  export PATH=&quot;$PROJECT_DIR/../scripts/xcode:$PATH&quot;&#10;'
        'fi&#10;'
    )
    guard = (
        'if ! xcrun --sdk iphonesimulator --show-sdk-path &gt;/dev/null 2&gt;&amp;1 &amp;&amp; [ -d &quot;/Applications/Xcode.app/Contents/Developer&quot; ]; then&#10;'
        '  export DEVELOPER_DIR=&quot;/Applications/Xcode.app/Contents/Developer&quot;&#10;'
        'fi&#10;'
    )
    text = scheme_path.read_text()
    text = text.replace(
        'scriptText = "/bin/sh &quot;$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh&quot; prepare&#10;">',
        f'scriptText = "{path_prefix}{guard}/bin/sh &quot;$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh&quot; prepare&#10;">',
    )
    scheme_path.write_text(text)
PY

INFO_PLIST="$ROOT/ios/Runner/Info.plist"
if [ -f "$INFO_PLIST" ]; then
  python3 - "$INFO_PLIST" <<'PY'
from pathlib import Path
import plistlib
import sys
path = Path(sys.argv[1])
with path.open('rb') as f:
    plist = plistlib.load(f)
changed = False
entries = {
    'CFBundleName': 'AquaRecover',
    'CFBundleDisplayName': 'AquaRecover',
    'NSPhotoLibraryUsageDescription': 'AquaRecover imports selected dive photos and videos for on-device restoration.',
    'NSPhotoLibraryAddUsageDescription': 'AquaRecover can save restored exports back to your photo library.',
    'PHPhotoLibraryPreventAutomaticLimitedAccessAlert': True,
    'LSSupportsOpeningDocumentsInPlace': True,
    'UIFileSharingEnabled': True,
    'BGTaskSchedulerPermittedIdentifiers': ['$(PRODUCT_BUNDLE_IDENTIFIER).video-export'],
    'UIBackgroundModes': ['processing'],
}
for key, value in entries.items():
    if plist.get(key) != value:
        plist[key] = value
        changed = True
if changed:
    with path.open('wb') as f:
        plistlib.dump(plist, f, sort_keys=False)
PY
fi

MAC_INFO_PLIST="$ROOT/macos/Runner/Info.plist"
if [ -f "$MAC_INFO_PLIST" ]; then
  python3 - "$MAC_INFO_PLIST" <<'PY'
from pathlib import Path
import plistlib
import sys
path = Path(sys.argv[1])
with path.open('rb') as f:
    plist = plistlib.load(f)
changed = False
entries = {
    'NSPhotoLibraryUsageDescription': 'AquaRecover imports selected dive photos and videos for on-device restoration.',
    'NSPhotoLibraryAddUsageDescription': 'AquaRecover can save restored exports back to your photo library.',
}
for key, value in entries.items():
    if key not in plist:
        plist[key] = value
        changed = True
if changed:
    with path.open('wb') as f:
        plistlib.dump(plist, f, sort_keys=False)
PY
fi

cd "$ROOT"
flutter pub get
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml

echo "Bootstrap complete. Try: flutter run -d macos or flutter run -d windows"
echo "For iPhone signing, open ios/Runner.xcworkspace and select your Apple team."
