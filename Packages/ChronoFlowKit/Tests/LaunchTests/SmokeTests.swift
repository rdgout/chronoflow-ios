import Foundation
import SnapshotTesting
import Testing

@testable import Launch

@Suite struct SmokeTests {
    @Test @MainActor func launchModuleLoads() {
        #expect(FileManager.default.fileExists(atPath: Bundle.module.bundleURL.path))
    }
}
