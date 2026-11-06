import Testing

@testable import DesignSystem

@Suite struct SmokeTests {
    @Test @MainActor func designSystemModuleLoads() {}
}
