#!/bin/zsh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

FLUTTER_TAG="3.35.6"

# Install Flutter using git.
git clone https://github.com/flutter/flutter.git --depth 1 -b $FLUTTER_TAG $HOME/flutter
# git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
# cd $HOME/flutter
# git checkout f73bfc4522dd0bc87bbcdb4bb3088082755c5e87
cd $CI_PRIMARY_REPOSITORY_PATH
export PATH="$PATH:$HOME/flutter/bin"


# Install Flutter artifacts for iOS (--ios), or macOS (--macos) platforms.
flutter precache --ios

# Install Flutter dependencies.
flutter pub get

# Install CocoaPods using Homebrew.
HOMEBREW_NO_AUTO_UPDATE=1 # disable homebrew's automatic updates.
brew install cocoapods

# Install CocoaPods dependencies.
cd ios && pod install # run `pod install` in the `ios` directory.

exit 0