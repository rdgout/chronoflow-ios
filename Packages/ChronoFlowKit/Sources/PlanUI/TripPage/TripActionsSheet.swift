#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    public struct TripActionsSheet: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        @State private var contentHeight: CGFloat = 0
        let card: TripCardView
        let detail: TripDetail?
        let online: Bool
        let busy: Bool
        let onAction: ((TripAction) -> Void)?

        public init(
            card: TripCardView, detail: TripDetail?, online: Bool, busy: Bool = false,
            onAction: ((TripAction) -> Void)? = nil
        ) {
            self.card = card
            self.detail = detail
            self.online = online
            self.busy = busy
            self.onAction = onAction
        }

        private var copy: PageCopy {
            PageCopy(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        private var availability: TripActionsAvailability {
            TripActionsAvailability(
                canEdit: card.canEdit && onAction != nil, canDuplicate: card.canDuplicate && onAction != nil,
                online: online, busy: busy)
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                    let header = TripActionsHeader(card: card, detail: detail, language: copy.language)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(header.title).planTextStyle(Typography.screenCardTitle).accessibilityAddTraits(.isHeader)
                        Text(header.subtitle).font(Typography.screenBody.font)
                            .foregroundStyle(ColorToken.mutedForeground.color).monospacedDigit()
                    }.padding(.horizontal, PlanUITokens.space1)
                    VStack(spacing: 0) {
                        row(.edit, title: "Edit trip", symbol: "square.and.pencil")
                        Divider().overlay(ColorToken.border.color)
                        row(.duplicate, title: "Duplicate trip", symbol: "square.on.square")
                    }.background(ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl))
                    Button(copy("Cancel")) { dismiss() }
                        .buttonStyle(.plain).font(Typography.wizardSecondary.font)
                        .frame(maxWidth: .infinity, minHeight: AuthTokens.touch)
                        .disabled(busy).accessibilityIdentifier("trip.actions.cancel")
                }.planContentBounds().padding(.horizontal, PlanUITokens.space4)
                    .padding(.top, PlanUITokens.space6).padding(.bottom, PlanUITokens.space8).planPageRail()
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        contentHeight = $0
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .foregroundStyle(ColorToken.foreground.color).background(ColorToken.card.color)
            .presentationDragIndicator(.visible)
            .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large])
            .interactiveDismissDisabled(busy)
            .accessibilityElement(children: .contain).accessibilityIdentifier("trip.actions")
        }

        private func row(_ action: TripAction, title: String, symbol: String) -> some View {
            let enabled = availability.enabled(action)
            return Button {
                onAction?(action)
            } label: {
                HStack(spacing: PlanUITokens.wizardContentGap) {
                    Image(systemName: symbol).font(.system(size: PlanUITokens.space5)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(copy(title)).font(Typography.screenBodyLg.font.weight(.medium))
                        if !enabled {
                            Text(copy("Needs a connection.")).font(Typography.screenBody.font)
                                .foregroundStyle(ColorToken.mutedForeground.color)
                        } else if action == .duplicate {
                            Text(copy("Same flights and answers, new dates")).font(Typography.screenBody.font)
                                .foregroundStyle(ColorToken.mutedForeground.color)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                    .frame(minHeight: PlanUITokens.space14)
            }.buttonStyle(.plain).disabled(!enabled)
                .opacity(enabled ? 1 : PlanUITokens.priorityOptionalOpacity)
                .accessibilityIdentifier("trip.actions.\(action.rawValue)")
        }
    }
#endif
