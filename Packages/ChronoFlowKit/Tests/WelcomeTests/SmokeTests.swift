import Foundation
import Testing

@testable import Welcome

@Suite struct SmokeTests {
    @Test @MainActor func welcomeModuleLoads() {
        #expect(FileManager.default.fileExists(atPath: Bundle.module.bundleURL.path))
    }
}
