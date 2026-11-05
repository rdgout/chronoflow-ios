import Foundation
import SnapshotTesting
import Testing

@testable import Launch

@Test @MainActor func launchModuleLoads() {
    #expect(FileManager.default.fileExists(atPath: Bundle.module.bundleURL.path))
}
