// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "Typover",
  platforms: [
    .macOS(.v27)
  ],
  products: [
    .executable(name: "Typover", targets: ["TypoverApp"]),
    .library(name: "TypoverCore", targets: ["TypoverCore"]),
    .library(name: "TypoverAppleSpell", targets: ["TypoverAppleSpell"]),
  ],
  targets: [
    .target(name: "TypoverCore"),
    .target(
      name: "TypoverAppleSpell",
      dependencies: ["TypoverCore"]
    ),
    .executableTarget(
      name: "TypoverApp",
      dependencies: ["TypoverAppleSpell", "TypoverCore"]
    ),
    .testTarget(
      name: "TypoverCoreTests",
      dependencies: ["TypoverAppleSpell", "TypoverCore"]
    ),
  ]
)
