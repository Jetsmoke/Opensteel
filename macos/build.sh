#!/bin/sh
# Builds "Opensteel.app" next to this script.
set -e
cd "$(dirname "$0")"
APP="Opensteel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ../model/Aerox9.mesh "$APP/Contents/Resources/"
# One binary for Apple silicon and Intel, running on macOS 13 and later.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13.0" Opensteel.swift -o "/tmp/opensteel-$arch"
done
lipo -create /tmp/opensteel-arm64 /tmp/opensteel-x86_64 -output "$APP/Contents/MacOS/Opensteel"
rm -f /tmp/opensteel-arm64 /tmp/opensteel-x86_64
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Opensteel</string>
  <key>CFBundleIdentifier</key><string>local.opensteel</string>
  <key>CFBundleExecutable</key><string>Opensteel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
# Identify the app by its bundle ID rather than its exact build, so macOS privacy
# permissions (Input Monitoring) survive rebuilds.
codesign --force --sign - -r='designated => identifier "local.opensteel"' "$APP"
echo "Built $(pwd)/$APP"
