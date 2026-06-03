#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-aqua_recover}"
ORG="${AQUA_ORG:-${ORG:-com.example}}"

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

flutter create --project-name "$PROJECT_NAME" --org "$ORG" --platforms=android,ios,macos "$TMP_DIR/$PROJECT_NAME"
rsync -a "$TMP_DIR/$PROJECT_NAME/android/" "$ROOT/android/"
rsync -a "$TMP_DIR/$PROJECT_NAME/ios/" "$ROOT/ios/"
rsync -a "$TMP_DIR/$PROJECT_NAME/macos/" "$ROOT/macos/"

if [ -f "$ROOT/android/app/build.gradle.kts" ]; then
  perl -0pi -e 's/minSdk = flutter\.minSdkVersion/minSdk = 24/g' "$ROOT/android/app/build.gradle.kts"
fi
if [ -f "$ROOT/android/app/build.gradle" ]; then
  perl -0pi -e 's/minSdkVersion flutter\.minSdkVersion/minSdkVersion 24/g; s/minSdkVersion = flutter\.minSdkVersion/minSdkVersion = 24/g' "$ROOT/android/app/build.gradle"
fi
if [ -f "$ROOT/ios/Podfile" ]; then
  perl -0pi -e "s/# platform :ios, '[0-9.]+'/platform :ios, '14.0'/g; s/platform :ios, '[0-9.]+'/platform :ios, '14.0'/g" "$ROOT/ios/Podfile"
fi

ANDROID_PACKAGE="$ORG.$PROJECT_NAME"
ANDROID_PACKAGE_PATH="${ANDROID_PACKAGE//./\/}"
ANDROID_DEST="$ROOT/android/app/src/main/kotlin/$ANDROID_PACKAGE_PATH"
mkdir -p "$ANDROID_DEST"
sed "s/^package .*/package $ANDROID_PACKAGE/" "$ROOT/platform_overrides/android/app/src/main/kotlin/com/example/aqua_recover/MainActivity.kt" > "$ANDROID_DEST/MainActivity.kt"

ANDROID_MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"
if [ -f "$ANDROID_MANIFEST" ]; then
  python3 - "$ANDROID_MANIFEST" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
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

python3 - "$ROOT/ios/Runner.xcodeproj/project.pbxproj:RawBridge.swift:AppDelegate.swift" "$ROOT/macos/Runner.xcodeproj/project.pbxproj:RawBridge.swift:MainFlutterWindow.swift" <<'PY'
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

for spec in sys.argv[1:]:
    add_swift_source(spec)
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
    'NSPhotoLibraryUsageDescription': 'AquaRecover imports selected dive photos and videos for on-device restoration.',
    'NSPhotoLibraryAddUsageDescription': 'AquaRecover can save restored exports back to your photo library.',
    'PHPhotoLibraryPreventAutomaticLimitedAccessAlert': True,
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

echo "Bootstrap complete. Try: flutter run -d macos"
echo "For iPhone signing, open ios/Runner.xcworkspace and select your Apple team."
