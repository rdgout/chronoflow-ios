public enum Route: String, Sendable, Equatable, CaseIterable {
    case welcome, today, signIn, guestWizard, terms, verify, walkthrough
}

@MainActor
public protocol Navigator: AnyObject {
    func navigate(to route: Route)
}
