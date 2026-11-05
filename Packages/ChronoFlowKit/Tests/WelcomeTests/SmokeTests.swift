import Foundation
import SnapshotTesting
import Testing

@testable import Welcome

@Test @MainActor func welcomeModuleLoads() {
    #expect(FileManager.default.fileExists(atPath: Bundle.module.bundleURL.path))
}
