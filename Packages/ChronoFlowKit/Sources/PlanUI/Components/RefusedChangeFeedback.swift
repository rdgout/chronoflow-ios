#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    private struct RefusedChangeFeedbackKey: EnvironmentKey {
        static var defaultValue: RefusedChangeModel? { nil }
    }

    extension EnvironmentValues {
        public var refusedChangeFeedback: RefusedChangeModel? {
            get { self[RefusedChangeFeedbackKey.self] }
            set { self[RefusedChangeFeedbackKey.self] = newValue }
        }
    }

    public struct RefusedChangeFeedback: View {
        @Environment(\.locale) private var locale
        @Environment(\.refusedChangeFeedback) private var model
        public init() {}
        public var body: some View {
            if let title = model?.text(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en) {
                FeedbackToast(title: title, identifier: "sync.refusal", success: false)
                    .onChange(of: title, initial: true) { _, title in
                        AccessibilityNotification.Announcement(title).post()
                    }
            }
        }
    }
#endif
