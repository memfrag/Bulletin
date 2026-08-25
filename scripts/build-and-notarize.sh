#!/bin/bash
#
# Builds, signs, notarizes and releases Bulletin.
#
# Ships a DMG rather than a ZIP on purpose: Finder's Archive Utility resolves
# symlinks when it expands a zip, which breaks Sparkle's framework seal and gets
# the app rejected by Gatekeeper for "unsealed contents".
#
# ASCII only. Bash reads a Unicode character next to $VARIABLE as part of the
# variable name, and the failure looks nothing like the cause.

set -euo pipefail

# ---------------------------------------------------------------- constants

SCHEME="Bulletin (Release)"
APP_NAME="Bulletin"
BUNDLE_ID="pizza.martin.Bulletin"
KEYCHAIN_PROFILE="notary"
SPARKLE_VERSION="2.9.0"
GITHUB_REPO="memfrag/Bulletin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

# Outside build/, which is wiped at the start of every run.
SPARKLE_TOOLS_DIR="$PROJECT_DIR/Sparkle-tools"

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
INFO_PLIST="$PROJECT_DIR/Bulletin/macOS/Info.plist"

# ------------------------------------------------------------------ helpers

error() {
    echo "" >&2
    echo "ERROR: $1" >&2
    exit 1
}

step() {
    echo ""
    echo "==> $1"
}

show_log_on_failure() {
    local log="$1"
    if [ -f "$log" ]; then
        echo "--- last 30 lines of $(basename "$log") ---" >&2
        tail -30 "$log" >&2
    fi
}

# -------------------------------------------------------------------- setup

step "Preparing"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

command -v gh >/dev/null || error "The GitHub CLI (gh) is required. brew install gh"
command -v xcrun >/dev/null || error "Xcode command line tools are required."

if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    error "No notarization credentials named '$KEYCHAIN_PROFILE'. Create them with:
  xcrun notarytool store-credentials $KEYCHAIN_PROFILE --apple-id <APPLE_ID> --team-id CQXRBQKG85"
fi

if ! git -C "$PROJECT_DIR" remote get-url origin >/dev/null 2>&1; then
    error "No git remote named 'origin'. Releases are published to $GITHUB_REPO, so the
repository has to exist and be connected before this script can run."
fi

# ----------------------------------------------------------- sparkle tools

if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
    step "Downloading Sparkle $SPARKLE_VERSION tools"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        -o "$BUILD_DIR/Sparkle.tar.xz" || error "Could not download the Sparkle tools."
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf "$BUILD_DIR/Sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" || error "Could not unpack the Sparkle tools."
    rm "$BUILD_DIR/Sparkle.tar.xz"
fi

[ -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ] || error "The Sparkle tools are missing sign_update."

# ------------------------------------------------------------------ version

step "Checking the version"

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="$(xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
        | grep " MARKETING_VERSION" | head -1 | sed 's/.*= //' || true)"
fi
[ -n "$CURRENT_VERSION" ] || error "Could not determine the current version."

LATEST_RELEASE="$(gh release view --repo "$GITHUB_REPO" --json tagName -q '.tagName' 2>/dev/null || true)"

if [ -z "$LATEST_RELEASE" ]; then
    echo "No previous release found. This will be the first."
    VERSION="$CURRENT_VERSION"
else
    echo "Latest release: $LATEST_RELEASE"
    echo "Current version: $CURRENT_VERSION"

    # sort -V puts the greater version last, so if the current version is not
    # strictly greater it is not releasable as is.
    NEWER="$(printf '%s\n%s\n' "$LATEST_RELEASE" "$CURRENT_VERSION" | sort -V | tail -1)"
    if [ "$CURRENT_VERSION" = "$LATEST_RELEASE" ] || [ "$NEWER" != "$CURRENT_VERSION" ]; then
        read -r -p "New version number: " VERSION
        [ -n "$VERSION" ] || error "No version given."

        NEWER="$(printf '%s\n%s\n' "$LATEST_RELEASE" "$VERSION" | sort -V | tail -1)"
        if [ "$VERSION" = "$LATEST_RELEASE" ] || [ "$NEWER" != "$VERSION" ]; then
            error "$VERSION is not newer than the released $LATEST_RELEASE."
        fi
    else
        VERSION="$CURRENT_VERSION"
    fi
fi

if [ "$VERSION" != "$CURRENT_VERSION" ]; then
    step "Setting the version to $VERSION"

    # All four have to agree. Sparkle compares CFBundleVersion and displays
    # CFBundleShortVersionString; if they drift, generate_appcast writes the
    # wrong sparkle:version and update checks quietly stop working.
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST" \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST" \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$INFO_PLIST"

    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $VERSION;/g" "$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"

    cd "$PROJECT_DIR"
    git add "$INFO_PLIST" "$APP_NAME.xcodeproj/project.pbxproj"
    git commit -m "Version $VERSION" || error "Could not commit the version bump."
    git push origin HEAD || error "Could not push the version bump."
fi

# ------------------------------------------------------------------ archive

step "Archiving"

xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    -arch arm64 \
    ENABLE_HARDENED_RUNTIME=YES \
    2>&1 | tee "$BUILD_DIR/archive.log" | tail -5

if [ ! -d "$ARCHIVE_PATH" ]; then
    show_log_on_failure "$BUILD_DIR/archive.log"
    error "The archive was not produced."
fi

step "Exporting"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | tee "$BUILD_DIR/export.log" | tail -5

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    show_log_on_failure "$BUILD_DIR/export.log"
    error "The exported app was not produced."
fi

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
echo "Built $APP_NAME $BUILT_VERSION"
[ "$BUILT_VERSION" = "$VERSION" ] || error "The built app reports $BUILT_VERSION but $VERSION was expected."

# ---------------------------------------------------------------- signature

step "Verifying the signature"

codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -5 \
    || error "The app is not correctly signed."

# ---------------------------------------------------------------------- dmg

step "Building the disk image"

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"

mkdir -p "$DMG_STAGING"
cp -a "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null \
    || error "Could not create the disk image."
rm -rf "$DMG_STAGING"

# --------------------------------------------------------------- notarizing

step "Notarizing (this takes a few minutes)"

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait \
    2>&1 | tee "$BUILD_DIR/notarize.log" | tail -10

grep -q "status: Accepted" "$BUILD_DIR/notarize.log" || {
    show_log_on_failure "$BUILD_DIR/notarize.log"
    error "Notarization was not accepted. For the details:
  xcrun notarytool log <submission-id> --keychain-profile $KEYCHAIN_PROFILE"
}

step "Stapling"
xcrun stapler staple "$DMG_PATH" || error "Could not staple the ticket to the disk image."
xcrun stapler validate "$DMG_PATH" || error "The stapled ticket does not validate."

# ------------------------------------------------------------------ sparkle

step "Signing for Sparkle"

SIGNATURE_OUTPUT="$("$SPARKLE_TOOLS_DIR/bin/sign_update" "$DMG_PATH")" \
    || error "Could not sign the update. Are the EdDSA keys in the keychain?"
echo "$SIGNATURE_OUTPUT"

# ------------------------------------------------------------------ release

step "Publishing release $VERSION"

cd "$PROJECT_DIR"

if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "Tag $VERSION already exists."
else
    git tag "$VERSION" || error "Could not create the tag."
    git push origin "$VERSION" || error "Could not push the tag."
fi

gh release create "$VERSION" \
    --repo "$GITHUB_REPO" \
    --title "$VERSION" \
    --generate-notes \
    "$DMG_PATH" \
    || error "Could not create the GitHub release."

# ------------------------------------------------------------------ appcast

step "Updating the appcast"

APPCAST_DIR="$BUILD_DIR/appcast-assets"
mkdir -p "$APPCAST_DIR"

# Append to the existing appcast rather than regenerating from every past
# release: older DMGs can share a CFBundleVersion, and generate_appcast refuses
# to run when it sees duplicates.
if [ -f "$PROJECT_DIR/appcast.xml" ]; then
    cp "$PROJECT_DIR/appcast.xml" "$APPCAST_DIR/"
fi
cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$VERSION/" \
    -o "$APPCAST_DIR/appcast.xml" \
    "$APPCAST_DIR" \
    || error "Could not generate the appcast."

cp "$APPCAST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"

git add appcast.xml
git commit -m "Update appcast for $VERSION" || error "Could not commit the appcast."
git push origin HEAD || error "Could not push the appcast."

step "Done"
echo "Released $APP_NAME $VERSION"
echo "  https://github.com/$GITHUB_REPO/releases/tag/$VERSION"
