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
    .library(
      name: "TypoverBearAdapter",
      targets: ["TypoverBearAdapter"]
    ),
    .library(name: "TypoverOverlay", targets: ["TypoverOverlay"]),
    .library(name: "TypoverAppleSpell", targets: ["TypoverAppleSpell"]),
  ],
  targets: [
    .target(name: "TypoverCore"),
    .target(name: "TypoverAccessibility"),
    .target(
      name: "TypoverBearAdapter",
      dependencies: ["TypoverAccessibility", "TypoverCore"]
    ),
    .target(
      name: "TypoverOverlay",
      dependencies: ["TypoverAccessibility", "TypoverBearAdapter"]
    ),
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
        "TypoverBearAdapter",
        "TypoverCore",
        "TypoverOverlay",
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
        "TypoverBearAdapter",
        "TypoverCore",
        "TypoverEvaluation",
        "TypoverOverlay",
        "TypoverRemoteIntelligence",
      ]
    ),
  ]
)
