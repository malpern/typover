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
    .library(
      name: "TypoverAppleIntelligence",
      targets: ["TypoverAppleIntelligence"]
    ),
    .library(
      name: "TypoverRemoteIntelligence",
      targets: ["TypoverRemoteIntelligence"]
    ),
    .library(
      name: "TypoverAccessibility",
      targets: ["TypoverAccessibility"]
    ),
    .library(name: "TypoverAppleSpell", targets: ["TypoverAppleSpell"]),
  ],
  targets: [
    .target(name: "TypoverCore"),
    .target(name: "TypoverAccessibility"),
    .target(
      name: "TypoverAppleIntelligence",
      dependencies: ["TypoverCore"]
    ),
    .target(
      name: "TypoverAppleSpell",
      dependencies: ["TypoverCore"]
    ),
    .target(
      name: "TypoverRemoteIntelligence",
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
        "TypoverAppleIntelligence",
        "TypoverAppleSpell",
        "TypoverCore",
        "TypoverEvaluation",
      ]
    ),
    .executableTarget(
      name: "TypoverApp",
      dependencies: [
        "TypoverAppleIntelligence",
        "TypoverAppleSpell",
        "TypoverAccessibility",
        "TypoverCore",
        "TypoverRemoteIntelligence",
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "TypoverCoreTests",
      dependencies: [
        "TypoverApp",
        "TypoverAppleIntelligence",
        "TypoverAppleSpell",
        "TypoverAccessibility",
        "TypoverCore",
        "TypoverEvaluation",
        "TypoverRemoteIntelligence",
      ]
    ),
  ]
)
