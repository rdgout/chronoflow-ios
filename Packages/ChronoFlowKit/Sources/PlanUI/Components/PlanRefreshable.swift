import DesignSystem
import SwiftUI
import Sync

#if canImport(UIKit)
    import UIKit
#endif

extension View {
    public func planRefreshContent() -> some View {
        #if canImport(UIKit)
            background(RefreshScrollConfiguration())
        #else
            self
        #endif
    }

    public func planRefreshScroll() -> some View {
        modifier(PlanRefreshScroll())
    }

    public func planRefreshable(action: @escaping () async throws -> SyncResult?) -> some View {
        modifier(PlanRefreshable(action: action))
    }
}

private struct PlanRefreshActionKey: EnvironmentKey {
    static var defaultValue: (@MainActor () async -> Void)? { nil }
}

extension EnvironmentValues {
    fileprivate var planRefreshAction: (@MainActor () async -> Void)? {
        get { self[PlanRefreshActionKey.self] }
        set { self[PlanRefreshActionKey.self] = newValue }
    }
}

private struct PlanRefreshScroll: ViewModifier {
    @Environment(\.planRefreshAction) private var refresh

    @ViewBuilder func body(content: Content) -> some View {
        if let refresh {
            content.scrollBounceBehavior(.always, axes: .vertical)
                .tint(ColorToken.primary.color)
                .refreshable { await refresh() }
        } else {
            content
        }
    }
}

#if canImport(UIKit)
    private struct RefreshScrollConfiguration: UIViewRepresentable {
        func makeUIView(context: Context) -> Probe {
            let view = Probe()
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            return view
        }
        func updateUIView(_ view: Probe, context: Context) { view.setNeedsLayout() }

        final class Probe: UIView {
            override func layoutSubviews() {
                super.layoutSubviews()
                var ancestor = superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView {
                        scroll.alwaysBounceVertical = true
                        scroll.refreshControl?.tintColor = UIColor(ColorToken.primary.color)
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
#endif

private struct PlanRefreshable: ViewModifier {
    let action: () async throws -> SyncResult?
    @State private var model = RefreshFeedbackModel()
    @State private var presentation = UUID()
    @Environment(\.locale) private var locale

    private var text: String {
        model.feedback.map { $0.text(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en) }
            .joined(separator: " · ")
    }

    func body(content: Content) -> some View {
        content
            .environment(
                \.planRefreshAction,
                {
                    await model.refresh(action: action)
                    presentation = UUID()
                }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.feedback.isEmpty {
                    Text(verbatim: text)
                        .font(Typography.screenBody.font)
                        .foregroundStyle(ColorToken.foreground.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                        .background(ColorToken.card.color, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: text))
                        .accessibilityIdentifier("refresh.feedback")
                        .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                        .planPageRail()
                        .frame(maxWidth: .infinity)
                        .background(ColorToken.background.color)
                }
            }
            .task(id: presentation) {
                guard !model.feedback.isEmpty else { return }
                AccessibilityNotification.Announcement(text).post()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                model.dismiss()
            }
            .onDisappear { model.dismiss() }
    }
}
