// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Typover",
  platforms: [
    .macOS(.v15)
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
