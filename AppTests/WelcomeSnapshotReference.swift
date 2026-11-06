#if canImport(UIKit)
    import Foundation
    import UIKit

    @MainActor
    func verifyWelcomeSnapshot(
        of image: UIImage, named name: String, record: Bool, testName: String, file: StaticString = #filePath,
        directory: URL? = nil
    ) throws -> String? {
        let directory =
            directory
            ?? URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/WelcomeSnapshotTests", isDirectory: true)
        let reference = directory.appendingPathComponent("\(testName).\(name).png")
        guard let png = image.pngData() else { return "Welcome capture could not be encoded as PNG" }
        // Compare the same immutable PNG decode path on both sides, including the first capture of a process.
        return try SnapshotReference.verify(png: png, reference: reference, record: record)
    }
#endif
