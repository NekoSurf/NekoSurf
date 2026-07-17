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
flutter build ios --config-only --no-codesign

exit 0