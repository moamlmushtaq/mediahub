#!/usr/bin/env bash
#
# Turns the SwiftPM executable into MediaHub.app. Runs on macOS only.
#
# WHY THE BUNDLE IS ASSEMBLED BY HAND
# ==================================
# Because the package is built with SwiftPM rather than from an Xcode project,
# and `swift build` produces a bare Mach-O executable — not a bundle. An app
# needs a directory with an Info.plist, an icon and a signature, and this
# assembles exactly that. The advantage is that the whole project stays a
# `Package.swift` with no 40,000-line pbxproj to merge, and it builds with one
# command on any Mac and in CI.
#
# ☠️ CFBundleName is not a display string. It is fine here because there are no
# helper processes, but the sibling Electron client shipped a version that
# crashed on every launch in 80 milliseconds because Electron derives its
# helper paths from that key. Treat every Info.plist key as functional until
# proven otherwise.
#
set -euo pipefail

cd "$(dirname "$0")/.."

app_name="MediaHub"
display_name="ميديا هَب"
bundle_id="com.msol.mediahub.native"
version="$(sed -n 's/.*MARKETING_VERSION *= *"\(.*\)".*/\1/p' Packaging/version.txt 2>/dev/null || echo "1.0.0")"

out="dist"
app="${out}/${app_name}.app"

say () { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "building"
# ☠️ NOT `swift build --arch arm64 --arch x86_64`.
#
# Passing two architectures to one invocation makes SwiftPM hand the build to
# Xcode's build system, which then fails with a wall of "duplicate output file
# .../TitleView.o" — every source file in the target, once per architecture.
# Nothing in the message says "you asked for two architectures".
#
# Two separate invocations plus `lipo` does work, and has the additional virtue
# that the second one is allowed to fail: an Intel slice is a courtesy, and the
# absence of one should not cost the household a build.
swift build -c release
native="$(swift build -c release --show-bin-path)/${app_name}"

staged="$(mktemp -d)/${app_name}"

if swift build -c release --arch x86_64 >/dev/null 2>&1; then
    intel="$(swift build -c release --arch x86_64 --show-bin-path)/${app_name}"
    lipo -create -output "$staged" "$native" "$intel"
    say "universal: $(lipo -archs "$staged")"
else
    cp "$native" "$staged"
    say "NOTE: the Intel slice did not build; shipping $(lipo -archs "$staged") only"
fi

binary="$staged"

say "assembling the bundle"
rm -rf "$app"
mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"

cp "$binary" "${app}/Contents/MacOS/${app_name}"
cp Packaging/MediaHub.icns "${app}/Contents/Resources/${app_name}.icns"

cat > "${app}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>${app_name}</string>
    <key>CFBundleDisplayName</key>       <string>${display_name}</string>
    <key>CFBundleIdentifier</key>        <string>${bundle_id}</string>
    <key>CFBundleExecutable</key>        <string>${app_name}</string>
    <key>CFBundleIconFile</key>          <string>${app_name}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key>           <string>${version}</string>
    <key>CFBundleDevelopmentRegion</key> <string>ar</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.entertainment</string>
    <key>NSHumanReadableCopyright</key>  <string>مكتبة عائلية خاصة</string>
    <!-- The app is dark by design and has no light appearance to fall back to. -->
    <key>NSRequiresAquaSystemAppearance</key> <false/>
    <!-- A laptop playing a film should not wake the discrete GPU to do it. -->
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Playback fetches from a CDN over HTTPS; no exception is needed, and
         declaring one would weaken every other connection the app makes. -->
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
</dict>
</plist>
PLIST

# The Arabic name for the menu bar, which reads the *localized* value.
for lang in ar en Base; do
    mkdir -p "${app}/Contents/Resources/${lang}.lproj"
    printf '"CFBundleName" = "%s";\n"CFBundleDisplayName" = "%s";\n' \
        "$display_name" "$display_name" > "${app}/Contents/Resources/${lang}.lproj/InfoPlist.strings"
done

say "signing"
# Ad-hoc. On Apple Silicon this is not optional polish: macOS refuses to
# execute an unsigned arm64 binary at all — it kills the process rather than
# warning. Notarizing needs a paid Developer ID and an upload to Apple, so the
# first launch still needs right-click → Open.
codesign --force --deep --sign - --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"

say "verifying"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "${app}/Contents/Info.plist"
lipo -archs "${app}/Contents/MacOS/${app_name}"

say "zipping"
# ditto, not zip: it is the only tool that preserves the resource forks and
# extended attributes a signed bundle carries, and a plain zip can invalidate
# the signature it just took a step to apply.
( cd "$out" && ditto -c -k --sequesterRsrc --keepParent "${app_name}.app" "${app_name}-${version}.zip" )

say "done"
ls -lh "${out}"/*.zip
