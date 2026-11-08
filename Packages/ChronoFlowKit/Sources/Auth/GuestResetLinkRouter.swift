import AppCore

@MainActor public final class GuestResetLinkRouter {
    public private(set) var pending: ResetPasswordLink?
    private let session: SessionController
    private let open: @MainActor (ResetPasswordLink) -> Void
    private var subscription: Task<Void, Never>?

    public init(session: SessionController, open: @escaping @MainActor (ResetPasswordLink) -> Void) {
        self.session = session
        self.open = open
        subscription = Task { [weak self, session] in
            for await update in await session.updates() {
                guard !Task.isCancelled else { return }
                if update.presence == .signedOut { await self?.consume() }
            }
        }
    }

    public func receive(_ link: ResetPasswordLink) async {
        pending = link
        await consume()
    }

    private func consume() async {
        guard await session.presence == .signedOut, let link = pending else { return }
        pending = nil
        open(link)
    }

    deinit { subscription?.cancel() }
}
