import DesignSystem
import SwiftUI
import Sync

#if canImport(UIKit)
    import UIKit
#endif

extension View {
    public func planRefreshContent() -> some View {
        #if canImport(UIKit)
            background(RefreshScrollConfiguration().accessibilityHidden(true))
        #else
            self
        #endif
    }

    public func planRefreshable(action: @escaping () async throws -> SyncResult?) -> some View {
        modifier(PlanRefreshable(action: action))
    }
}

#if canImport(UIKit)
    private struct RefreshScrollConfiguration: UIViewRepresentable {
        func makeUIView(context: Context) -> Probe { Probe() }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: String {
        model.feedback.map { $0.text(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en) }
            .joined(separator: " · ")
    }

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .tint(ColorToken.primary.color)
            .refreshable {
                await model.refresh(action: action)
                presentation = UUID()
            }
            .overlay(alignment: .top) {
                if !model.feedback.isEmpty {
                    Text(verbatim: text)
                        .font(Typography.screenBody.font)
                        .foregroundStyle(ColorToken.foreground.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                        .background(.regularMaterial, in: Capsule())
                        .padding(PlanUITokens.space3)
                        .accessibilityIdentifier("refresh.feedback")
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .default, value: model.feedback.isEmpty)
            .task(id: presentation) {
                guard !model.feedback.isEmpty else { return }
                AccessibilityNotification.Announcement(text).post()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                model.dismiss()
            }
            .onDisappear { model.dismiss() }
    }
}
