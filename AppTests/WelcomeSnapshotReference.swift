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
        guard WelcomeSnapshotPixels.hasVisibleVariation(pixels(image)) else {
            return "Welcome capture is uniform or transparent; refusing snapshot"
        }
        if record {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.pngData()!.write(to: reference, options: .atomic)
            return "Record mode is on. Recorded \(reference.lastPathComponent)"
        }
        guard let expected = UIImage(contentsOfFile: reference.path) else {
            return "Missing Welcome reference: \(reference.path). Record explicitly with SNAPSHOT_RECORD=1."
        }
        guard image.cgImage?.width == expected.cgImage?.width,
            image.cgImage?.height == expected.cgImage?.height,
            pixels(image) == pixels(expected)
        else {
            return "Welcome pixels differ from \(reference.path)"
        }
        return nil
    }
#endif
