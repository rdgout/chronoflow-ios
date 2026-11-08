#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct LegendSheet: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        public init() {}
        private func t(_ key: String) -> String {
            PlanStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.space5) {
                        Text(
                            t(
                                "Each kind of step has its own icon and pattern, so you can tell them apart without colour."
                            )
                        ).planTextStyle(Typography.screenBody, color: .mutedForeground)
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                                Text(t(group.0).uppercased()).planTextStyle(
                                    Typography.screenLabel, color: .mutedForeground
                                ).accessibilityAddTraits(
                                    .isHeader)
                                ForEach(group.1, id: \.rawValue) { type in
                                    HStack(spacing: PlanUITokens.space3) {
                                        CategorySwatch(type)
                                        VStack(alignment: .leading) {
                                            Text(t(stepLabelKey(type) ?? "Note")).planTextStyle(Typography.screenBodyLg)
                                            Text(t(legendDescription(type))).planTextStyle(
                                                Typography.screenBody, color: .mutedForeground)
                                        }
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                        }
                        Text(t("How important")).planTextStyle(Typography.screenLabel, color: .mutedForeground)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                            Text(t("Priority")).planTextStyle(Typography.screenLabel).accessibilityAddTraits(.isHeader)
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading),
                                ], alignment: .leading, spacing: PlanUITokens.space2
                            ) {
                                ForEach([Priority.core, .recommended, .optional, .info], id: \.rawValue) { priority in
                                    HStack(spacing: PlanUITokens.space2) {
                                        PrioritySample(priority: priority)
                                        VStack(alignment: .leading) {
                                            Text(t(priorityKey(priority))).font(
                                                Typography.screenBody.font.weight(.medium))
                                            Text(t(priorityDescription(priority))).planTextStyle(
                                                Typography.screenMeta, color: .mutedForeground)
                                        }
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }.padding(PlanUITokens.space5)
                }
                .navigationTitle(t("What the steps mean")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("Close")) { dismiss() }.accessibilityIdentifier("legend.close")
                    }
                }
                .background(ColorToken.card.color).accessibilityIdentifier("legend.sheet")
            }.presentationDragIndicator(.visible)
        }
        private var groups: [(String, [BlockType])] {
            [
                ("Sleep", [.sleep, .nap, .rest]), ("Light", [.seekLight, .lightOK, .lightNeutral, .avoidLight]),
                ("Caffeine", [.caffeineServing, .caffeineRoutine, .caffeineOK, .noCaffeine]),
                ("Travel", [.flight, .layover, .transfer, .movementBreak, .zoneChange, .note]),
            ]
        }
    }
#endif
