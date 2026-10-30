#!/bin/sh
# Wrap the SPM-built sView executable into build/sView.app with an ad-hoc
# signature. Used when Xcode or XcodeGen is not available.
set -eu

SWIFT=${SWIFT:-swift}
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
CONFIG=${CONFIG:-debug}
APP=build/sView.app

sh -c "$SWIFT build -c $CONFIG --product sView"
BIN_DIR=$(sh -c "$SWIFT build -c $CONFIG --show-bin-path")

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/sView" "$APP/Contents/MacOS/sView"
sed \
    -e "s/\$(EXECUTABLE_NAME)/sView/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/io.github.usuite.sview/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp scripts/sview "$APP/Contents/Resources/sview"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP $VERSION ($BUILD_NUMBER)"
