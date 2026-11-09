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
        content
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
            .task(id: model.presentationID) {
                guard !model.feedback.isEmpty else { return }
                AccessibilityNotification.Announcement(text).post()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                model.dismiss()
            }
            .onDisappear { model.dismiss() }
    }
}
