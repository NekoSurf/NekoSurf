#!/bin/zsh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Regenerate iOS build settings and generated Swift package manifests.
# This avoids stale/default deployment targets (e.g. 13.0) in
# FlutterGeneratedPluginSwiftPackage when Xcode Cloud archives directly.
#
# Use Xcode Cloud's own build number so uploads never collide. Prepare Release
# predicts this number, so it normally matches the tag; warn if it doesn't.
PUBSPEC_BUILD=$(sed -nE 's/^version: .*\+([0-9]+)$/\1/p' pubspec.yaml)
if [[ -n "$CI_BUILD_NUMBER" && "$CI_BUILD_NUMBER" != "$PUBSPEC_BUILD" ]]; then
  echo "warning: Xcode Cloud build number $CI_BUILD_NUMBER differs from pubspec ($PUBSPEC_BUILD)"
fi
flutter build ios --config-only --no-codesign ${CI_BUILD_NUMBER:+--build-number=$CI_BUILD_NUMBER}

exit 0