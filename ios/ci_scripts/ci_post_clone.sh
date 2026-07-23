#!/bin/zsh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH # change working directory to the root of your cloned repo.

# Resolve project metadata up front so Xcode Cloud opens the native Runner target cleanly.
xcodebuild -project ios/Runner.xcodeproj -scheme Runner -resolvePackageDependencies

exit 0