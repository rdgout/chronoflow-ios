import DesignSystem
import SwiftUI

extension View {
    public func planRefreshFeedback(_ model: RefreshFeedbackModel) -> some View {
        modifier(PlanRefreshFeedback(model: model))
    }
}

private struct PlanRefreshFeedback: ViewModifier {
    let model: RefreshFeedbackModel
    @Environment(\.locale) private var locale

    private var text: String {
        model.feedback.map { $0.text(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en) }
            .joined(separator: " · ")
    }

    func body(content: Content) -> some View {
        debugContent(content)
            .overlay(alignment: .top) {
                if !model.feedback.isEmpty {
                    capsule(text: text, presentationID: model.presentationID)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: model.feedback.isEmpty)
    }

    private func capsule(text: String, presentationID: UUID) -> some View {
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
            .onAppear {
                #if DEBUG
                    model.debugMarkPresented(text)
                #endif
            }
            .task(id: presentationID) {
                AccessibilityNotification.Announcement(text).post()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                model.dismiss(presentationID: presentationID)
            }
    }

    @ViewBuilder private func debugContent(_ content: Content) -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CF_REFRESH_TEST_COUNTER"] == "1" {
                content.overlay(alignment: .bottomLeading) {
                    Text(verbatim: String(model.debugRefreshCount))
                        .font(.caption2).opacity(0.01).allowsHitTesting(false)
                        .accessibilityIdentifier("refresh.debug.count")
                        .accessibilityValue(Text(verbatim: String(model.debugRefreshCount)))
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: model.debugOutcome)
                        .font(.caption2).opacity(0.01).allowsHitTesting(false)
                        .accessibilityIdentifier("refresh.debug.outcome")
                }
                .overlay(alignment: .bottom) {
                    Text(verbatim: model.debugPresented)
                        .font(.caption2).opacity(0.01).allowsHitTesting(false)
                        .accessibilityIdentifier("refresh.debug.presented")
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}
