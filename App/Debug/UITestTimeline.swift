#if DEBUG
    import DataAccess
    import Foundation
    import OSLog

    @MainActor enum UITestTimeline {
        static func record(
            _ event: String, environment: [String: String] = UITestRuntime.environment, details: String = "",
            allowUngated: Bool = false
        ) {
            let test = AuthUITestConfiguration(environment: environment)
            guard test != nil || allowUngated else { return }
            let line =
                "CF_UI_TIMELINE id=\(test?.id ?? "ungated") pid=\(ProcessInfo.processInfo.processIdentifier) event=\(event) wall=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime) \(details)"
            Logger(subsystem: "net.chronoflow.app.native", category: "UITestTimeline").notice(
                "\(line, privacy: .public)")
        }
    }
#endif
