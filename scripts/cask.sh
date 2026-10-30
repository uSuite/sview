#!/bin/sh
# Fills the Homebrew cask from the release zip (SV-508). REPOSITORY is the
# GitHub owner/name the release is published under (default uSuite/sview).
set -eu
VERSION=$(cat VERSION)
ZIP=build/release/sView-$VERSION.zip
REPOSITORY=${REPOSITORY:-uSuite/sview}
[ -f "$ZIP" ] || { echo "cask: build $ZIP first with make release" >&2; exit 1; }
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
sed -e "s|@VERSION@|$VERSION|" -e "s|@SHA256@|$SHA|" -e "s|@REPOSITORY@|$REPOSITORY|g" \
    packaging/homebrew/sview.rb.template > build/release/sview.rb
echo "cask: build/release/sview.rb for $REPOSITORY $VERSION"
