#if DEBUG
    import DataAccess
    import Foundation
    import OSLog

    nonisolated enum UITestTimeline {
        static func record(_ event: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let test = AuthUITestConfiguration(environment: environment) else { return }
            let line =
                "CF_UI_TIMELINE id=\(test.id) pid=\(ProcessInfo.processInfo.processIdentifier) event=\(event) wall=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime)"
            Logger(subsystem: "net.chronoflow.app.native", category: "UITestTimeline").notice(
                "\(line, privacy: .public)")
        }
    }
#endif
