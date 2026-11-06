import AppCore
import Foundation

actor StubReadiness: LaunchReadiness {
    enum Session: String, Sendable { case native, signedIn, signedOut, never }
    enum Stored: String, Sendable { case yes, no, never }

    struct Configuration: Sendable, Equatable {
        var session: Session = .native
        var gate: Gate = .app
        var stored: Stored = .yes
        var readyDelay: Duration = .zero
    }

    let configuration: Configuration
    private let store: any SessionStore
    private let clock: any LaunchClock
    private(set) var firstLoadCount = 0

    init(configuration: Configuration, store: any SessionStore, clock: any LaunchClock) {
        self.configuration = configuration
        self.store = store
        self.clock = clock
    }

    func session() async -> SessionPresence {
        #if DEBUG
            switch configuration.session {
            case .native: return await store.loadSession()
            case .signedIn: return .signedIn(accountID: "debug")
            case .signedOut: return .signedOut
            case .never:
                do { try await Task.sleep(for: .seconds(60)) } catch {}
                return .signedOut
            }
        #else
            return .signedOut
        #endif
    }

    func gate() -> Gate { configuration.gate }

    func hasStoredData() async -> Bool {
        if configuration.stored == .never {
            do { try await Task.sleep(for: .seconds(60)) } catch {}
        }
        return configuration.stored == .yes
    }

    func storedDataUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task { [configuration, clock] in
                if configuration.stored != .never {
                    continuation.yield(configuration.stored == .yes)
                    if configuration.stored == .no {
                        do { try await clock.sleep(until: configuration.readyDelay) } catch {
                            continuation.finish()
                            return
                        }
                        guard !Task.isCancelled else { return }
                        continuation.yield(true)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func allowFirstLoad() {
        guard firstLoadCount == 0 else { return }
        firstLoadCount = 1
    }
}
