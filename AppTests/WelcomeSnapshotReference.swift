#if canImport(UIKit)
    import Foundation
    import UIKit

    @MainActor
    func verifyWelcomeSnapshot(
        of image: UIImage, named name: String, record: Bool, testName: String, file: StaticString = #filePath,
        directory: URL? = nil, content: SnapshotReference.Content = .visible
    ) throws -> String? {
        guard let png = image.pngData() else { return "Welcome capture could not be encoded as PNG" }
        return try verifyWelcomeSnapshot(
            of: SnapshotReference.Sample(png: png), named: name, record: record, testName: testName,
            file: file, directory: directory, content: content)
    }

    @MainActor
    func verifyWelcomeSnapshot(
        of sample: SnapshotReference.Sample, named name: String, record: Bool, testName: String,
        file: StaticString = #filePath, directory: URL? = nil, content: SnapshotReference.Content = .visible
    ) throws -> String? {
        let directory =
            directory
            ?? URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/WelcomeSnapshotTests", isDirectory: true)
        let reference = directory.appendingPathComponent("\(testName).\(name).png")
        // Compare the same immutable PNG decode path on both sides, including the first capture of a process.
        return try SnapshotReference.verify(sample: sample, reference: reference, record: record, content: content)
    }
#endif
