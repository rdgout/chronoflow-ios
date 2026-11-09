#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct TodayStepRow: View {
        @Environment(\.locale) private var locale
        public let block: BlockView
        public let mark: CheckMark?
        public let now: Date
        public let formatter: CopyLineFormatter
        public let trip: TripDetailView?
        public let timeFormat: TimeFormat
        public let running: Bool
        public let action: () -> Void
        public init(
            block: BlockView, mark: CheckMark?, now: Date, formatter: CopyLineFormatter,
            trip: TripDetailView?, timeFormat: TimeFormat = .value24, running: Bool, action: @escaping () -> Void
        ) {
            self.block = block
            self.mark = mark
            self.now = now
            self.formatter = formatter
            self.trip = trip
            self.timeFormat = timeFormat
            self.running = running
            self.action = action
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String, _ values: [String: String] = [:]) -> String {
            PlanStrings.text(key, language: language, values)
        }
        public var body: some View {
            let options = CopyFormat(
                language: language, timeFormat: timeFormat, displayZone: block.displayTz, trip: trip)
            let title = formatter.format(block.text, options: options)
            let zone = zoneLabel(block.displayTz, trip: trip)
            let minutes = max(0, ceil(planDate(running ? block.endUtc : block.startUtc).timeIntervalSince(now) / 60))
            let duration = formatter.formatMinutes(minutes, language: language, duration: true)
            let time = formatter.formatInstant(running ? block.endUtc : block.startUtc, options: options)
            let subtitle =
                mark.map {
                    t(
                        $0.status == .done ? "Done · {{time}} · {{zone}}" : "Skipped · {{time}} · {{zone}}",
                        [
                            "time": [.caffeineServing, .zoneChange].contains(block.type)
                                || block.startUtc == block.endUtc
                                ? formatter.formatInstant(block.startUtc, options: options)
                                : formatter.blockInterval(block, options: options, separator: " → "), "zone": zone,
                        ])
                }
                ?? "\(running ? "→ " : "")\(time) · \(zone) · "
                + t(running ? "{{duration}} left" : "In {{duration}}", ["duration": duration])
            return Button {
                action()
            } label: {
                HStack(spacing: PlanUITokens.space3) {
                    CategorySwatch(block.type).opacity(mark == nil ? 1 : PlanUITokens.markedOpacity)
                    VStack(alignment: .leading) {
                        Text(title).planTextStyle(
                            Typography.screenBodyLg, color: mark == nil ? .foreground : .mutedForeground,
                            context: "\(block.id).title")
                        Text(subtitle).planTextStyle(
                            Typography.screenBody, color: .mutedForeground, context: "\(block.id).subtitle"
                        ).monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let mark {
                        Image(systemName: mark.status == .done ? "checkmark" : "forward.end")
                            .font(Typography.screenBody.font)
                            .frame(width: PlanUITokens.space1 * 7, height: PlanUITokens.space1 * 7)
                            .foregroundStyle(
                                (mark.status == .done ? ColorToken.dawnForeground : .mutedForeground).color
                            )
                            .background((mark.status == .done ? ColorToken.dawn : .card).color, in: Circle())
                            .overlay {
                                if mark.status != .done {
                                    Circle().strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.focusWidth)
                                }
                            }
                            .accessibilityHidden(true)
                    }
                }.frame(minHeight: PlanUITokens.space14).padding(PlanUITokens.space2)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityElement(children: .combine)
                .accessibilityIdentifier(
                    "today.step.\(block.actionable && block.checkKey != nil ? "actionable." : "")\(block.id)"
                )
                .accessibilityLabel(
                    mark.map { t($0.status == .done ? "{{title}}, done" : "{{title}}, skipped", ["title": title]) }
                        ?? "\(title), \(subtitle)")
        }
    }
#endif
