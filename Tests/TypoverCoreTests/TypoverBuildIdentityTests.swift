import Foundation
import Testing

@testable import TypoverApp

struct TypoverBuildIdentityTests {
  @Test("Reads release identity and shortens its source revision")
  func readsReleaseIdentity() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": "0.1.2",
        "CFBundleVersion": "20260802001425",
        "TypoverSourceRevision": "20e8e2f322877a310fddda3fc853414fb0196c77",
        "TypoverSourceDirty": false,
      ]
    )

    #expect(identity.version == "0.1.2")
    #expect(identity.build == "20260802001425")
    #expect(identity.sourceRevision == "20e8e2f322877a310fddda3fc853414fb0196c77")
    #expect(identity.shortSourceRevision == "20e8e2f322")
    #expect(identity.sourceIsDirty == false)
    #expect(identity.versionAndBuild?.version == "0.1.2")
    #expect(identity.versionAndBuild?.build == "20260802001425")
  }

  @Test("Treats incomplete development metadata as unavailable")
  func handlesMissingMetadata() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": "  ",
        "TypoverSourceRevision": "\n",
      ]
    )

    #expect(identity.version == nil)
    #expect(identity.build == nil)
    #expect(identity.versionAndBuild == nil)
    #expect(identity.sourceRevision == nil)
    #expect(identity.shortSourceRevision == nil)
    #expect(identity.sourceIsDirty == nil)
  }

  @Test("Normalizes string metadata written by alternate build tooling")
  func normalizesStringMetadata() {
    let identity = TypoverBuildIdentity(
      infoDictionary: [
        "CFBundleShortVersionString": " 0.2 ",
        "CFBundleVersion": " 42\n",
        "TypoverSourceRevision": " abcdef ",
        "TypoverSourceDirty": "YES",
      ]
    )

    #expect(identity.version == "0.2")
    #expect(identity.build == "42")
    #expect(identity.sourceRevision == "abcdef")
    #expect(identity.shortSourceRevision == "abcdef")
    #expect(identity.sourceIsDirty == true)
  }
}
