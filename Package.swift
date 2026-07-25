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
  ],
  targets: [
    .target(name: "TypoverCore"),
    .executableTarget(
      name: "TypoverApp",
      dependencies: ["TypoverCore"]
    ),
    .testTarget(
      name: "TypoverCoreTests",
      dependencies: ["TypoverCore"]
    ),
  ]
)
