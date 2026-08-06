// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "Typover",
  platforms: [
    // Typover ships as a macOS 27 app: Support/Typover-Info.plist sets
    // LSMinimumSystemVersion to 27.0 and verify-beta-app.sh enforces it. The
    // compile target is deliberately one release lower so the test suite can
    // run on GitHub's hosted runners, whose newest image is a macOS 26 host
    // (the `xcode-27` label is macOS 26 with Xcode 27). Compiling at 26 keeps
    // availability checking honest: a macOS 27-only API becomes a build error
    // instead of a runtime crash.
    .macOS(.v26)
  ],
  products: [
    .executable(name: "Typover", targets: ["TypoverApp"]),
    .executable(name: "TypoverEval", targets: ["TypoverEval"]),
    .executable(
      name: "TypoverBearHIDHarness",
      targets: ["TypoverBearHIDHarness"]
    ),
    .library(name: "TypoverCore", targets: ["TypoverCore"]),
    .library(name: "TypoverHIDTesting", targets: ["TypoverHIDTesting"]),
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
    .target(name: "TypoverHIDTesting"),
    .target(name: "TypoverAccessibility"),
    .target(
      name: "TypoverBearAdapter",
      dependencies: ["TypoverAccessibility", "TypoverCore"]
    ),
    .target(
      name: "TypoverOverlay",
      dependencies: [
        "TypoverAccessibility",
        "TypoverBearAdapter",
        "TypoverCore",
      ]
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
    .executableTarget(
      name: "TypoverBearHIDHarness",
      dependencies: [
        "TypoverAccessibility",
        "TypoverHIDTesting",
        "TypoverOverlay",
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
        "TypoverHIDTesting",
        "TypoverOverlay",
        "TypoverRemoteIntelligence",
      ]
    ),
  ]
)
