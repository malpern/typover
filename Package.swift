// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "Typover",
  platforms: [
    .macOS(.v27)
  ],
  products: [
    .executable(name: "Typover", targets: ["TypoverApp"]),
    .executable(name: "TypoverEval", targets: ["TypoverEval"]),
    .library(name: "TypoverCore", targets: ["TypoverCore"]),
    .library(name: "TypoverAppleSpell", targets: ["TypoverAppleSpell"]),
  ],
  targets: [
    .target(name: "TypoverCore"),
    .target(
      name: "TypoverAppleSpell",
      dependencies: ["TypoverCore"]
    ),
    .target(
      name: "TypoverEvaluation",
      dependencies: ["TypoverCore"],
      resources: [
        .process("Resources")
      ]
    ),
    .executableTarget(
      name: "TypoverEval",
      dependencies: [
        "TypoverAppleSpell",
        "TypoverCore",
        "TypoverEvaluation",
      ]
    ),
    .executableTarget(
      name: "TypoverApp",
      dependencies: ["TypoverAppleSpell", "TypoverCore"],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "TypoverCoreTests",
      dependencies: [
        "TypoverApp",
        "TypoverAppleSpell",
        "TypoverCore",
        "TypoverEvaluation",
      ]
    ),
  ]
)
