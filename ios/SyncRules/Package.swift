// swift-tools-version:5.9
// Tests for iCloud sync's rules (ios/Runner/SyncRules.swift, which the
// source here links to): `swift test --package-path ios/SyncRules`. Plain
// Swift, without CloudKit, so it runs anywhere, as on CI's Linux.
import PackageDescription

let package = Package(
  name: "SyncRules",
  targets: [
    .target(name: "SyncRulesKit"),
    .testTarget(name: "SyncRulesTests", dependencies: ["SyncRulesKit"]),
  ]
)
