import Testing

@MainActor struct WelcomeSnapshotGuardTests {
    @Test func rejectsUniformAndTransparentCaptures() {
        let white = Array(repeating: UInt8(255), count: 4096)
        let transparent = Array(repeating: UInt8(0), count: 4096)
        #expect(!WelcomeSnapshotPixels.hasVisibleVariation([]))
        #expect(!WelcomeSnapshotPixels.hasVisibleVariation([0, 1, 2, 3, 4]))
        #expect(!WelcomeSnapshotPixels.hasVisibleVariation(white))
        #expect(!WelcomeSnapshotPixels.hasVisibleVariation(transparent))
        #expect(!WelcomeSnapshotPixels.hasVisibleVariation([0, 0, 0, 0, 255, 255, 255, 0]))
        var marked = white
        marked.replaceSubrange(4..<8, with: [0, 0, 0, 255])
        #expect(WelcomeSnapshotPixels.hasVisibleVariation(marked))
    }

    @Test func rejectsIdenticalAndNegligiblyDifferentOppositeVariants() {
        let white = Array(repeating: UInt8(255), count: 4096)
        #expect(!WelcomeSnapshotPixels.differ([], []))
        #expect(!WelcomeSnapshotPixels.differ(white, Array(white.dropLast())))
        #expect(!WelcomeSnapshotPixels.differ(white, white))
        #expect(!WelcomeSnapshotPixels.differ(white, Array(repeating: 254, count: white.count)))
        var marked = white
        marked.replaceSubrange(4..<8, with: [0, 0, 0, 255])
        #expect(!WelcomeSnapshotPixels.differ(white, marked))
        marked.replaceSubrange(8..<12, with: [0, 0, 0, 255])
        #expect(WelcomeSnapshotPixels.differ(white, marked))
    }
}

#if canImport(UIKit)
    import UIKit

    extension WelcomeSnapshotGuardTests {
        @Test func referenceRecordingIsExplicitAndComparisonUsesPixels() throws {
            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/WelcomeReferenceTests/\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            func image(mark: Bool) -> UIImage {
                UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                    UIColor.black.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: mark ? 8 : 4, height: 4))
                }
            }
            let original = image(mark: false)
            let missing = try verifyWelcomeSnapshot(
                of: original, named: "fixture", record: false, testName: "guard", directory: directory)
            #expect(missing?.hasPrefix("Missing Welcome reference:") == true)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            let recorded = try verifyWelcomeSnapshot(
                of: original, named: "fixture", record: true, testName: "guard", directory: directory)
            #expect(recorded?.hasPrefix("Record mode is on.") == true)
            #expect(
                try verifyWelcomeSnapshot(
                    of: original, named: "fixture", record: false, testName: "guard", directory: directory) == nil)
            let changed = try verifyWelcomeSnapshot(
                of: image(mark: true), named: "fixture", record: false, testName: "guard", directory: directory)
            #expect(changed?.hasPrefix("Welcome pixels differ") == true)
            let uniform = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { _ in }
            let rejected = try verifyWelcomeSnapshot(
                of: uniform, named: "invalid", record: true, testName: "guard", directory: directory)
            #expect(rejected?.contains("uniform or transparent") == true)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("guard.invalid.png").path))
        }
    }
#endif
