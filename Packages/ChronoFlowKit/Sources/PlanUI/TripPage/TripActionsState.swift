import AppCore
import Foundation

nonisolated public enum TripAction: String, Sendable { case edit, duplicate }

nonisolated public struct TripActionsAvailability: Sendable, Equatable {
    public let edit: Bool
    public let duplicate: Bool

    public init(canEdit: Bool, canDuplicate: Bool, online: Bool, busy: Bool) {
        edit = canEdit && online && !busy
        duplicate = canDuplicate && online && !busy
    }

    public func enabled(_ action: TripAction) -> Bool { action == .edit ? edit : duplicate }
}

nonisolated public struct TripActionsHeader: Sendable, Equatable {
    public let title: String
    public let subtitle: String

    public init(card: TripCardView, detail: TripDetail?, language: Language) {
        let copy = PageCopy(language: language)
        title = copy("%@ → %@", card.from.city ?? card.from.iata, card.to.city ?? card.to.iata)
        var parts = [
            tripDatesText(start: card.departLocal, end: detail?.plan.days.last?.labelDate, language: language)
        ]
        if !card.connections.isEmpty {
            parts.append(copy("via %@", card.connections.map { $0.city ?? $0.iata }.joined(separator: ", ")))
        }
        if detail?.trip.legs.contains(where: \.returnLeg) == true { parts.append(copy("with return")) }
        subtitle = parts.joined(separator: " · ")
    }
}
