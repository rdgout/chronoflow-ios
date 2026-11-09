import Observation

@MainActor @Observable
public final class AccountModel {
    public struct AttachmentToken: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    public enum LoadState: Equatable {
        case unknown
        case loaded(AccountRecord?)
        case failed
    }

    public private(set) var state: LoadState = .unknown
    public private(set) var epoch: UInt64 = 0
    public var attachmentToken: AttachmentToken { AttachmentToken(generation: generation) }
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var subscription: Task<Void, Never>?

    public init() {}

    public func attach(to repository: AccountRepository, epoch: UInt64, ifCurrent token: AttachmentToken? = nil) async {
        guard !Task.isCancelled, token == nil || token == attachmentToken else { return }
        let previous = cancelSubscription()
        self.epoch = epoch
        let generation = self.generation
        await previous?.value
        guard !Task.isCancelled, self.generation == generation else { return }
        subscription = Task { [weak self] in
            do {
                let values = try await repository.values()
                for try await value in values {
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    self.state = .loaded(value)
                }
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.state = .unknown
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.state = .failed
            }
        }
    }

    public func detach() async {
        let previous = cancelSubscription()
        await previous?.value
    }

    private func cancelSubscription() -> Task<Void, Never>? {
        generation &+= 1
        let previous = subscription
        subscription = nil
        previous?.cancel()
        state = .unknown
        return previous
    }

    deinit { subscription?.cancel() }
}
