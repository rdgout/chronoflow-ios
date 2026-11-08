import AppCore
import Foundation

public actor AirportSearchService {
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    private let search: @Sendable (String) async throws -> [ApiAirportSuggestion]
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private var nextRequest = Date.distantPast

    public init(source: any DataSource) {
        search = { try await source.searchAirports(query: $0, limit: 8) }
        now = { Date() }
        sleep = { try await Task.sleep(for: .seconds($0)) }
    }

    public init(
        search: @escaping @Sendable (String) async throws -> [ApiAirportSuggestion],
        now: @escaping @Sendable () -> Date, sleep: @escaping Sleep
    ) {
        self.search = search
        self.now = now
        self.sleep = sleep
    }

    public func results(for raw: String) async throws -> [ApiAirportSuggestion] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(query.count) else { return [] }
        try await sleep(0.35)
        try Task.checkCancellation()
        while now() < nextRequest {
            try await sleep(nextRequest.timeIntervalSince(now()))
            try Task.checkCancellation()
        }
        nextRequest = now().addingTimeInterval(1.02)
        try Task.checkCancellation()
        do { return try await search(query) } catch let failure as DataFailure {
            if case .throttled(let seconds, _) = failure {
                nextRequest = max(nextRequest, now().addingTimeInterval(seconds))
            }
            throw failure
        }
    }
}
