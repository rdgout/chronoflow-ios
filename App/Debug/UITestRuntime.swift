#if DEBUG
    import Foundation
    import UIKit

    @MainActor enum UITestRuntime {
        static var environment: [String: String] {
            (UIApplication.shared.delegate as? AppDelegate)?.uiTestEnvironment ?? ProcessInfo.processInfo.environment
        }

        static var arguments: [String] {
            (UIApplication.shared.delegate as? AppDelegate)?.uiTestArguments ?? ProcessInfo.processInfo.arguments
        }
    }
#endif
