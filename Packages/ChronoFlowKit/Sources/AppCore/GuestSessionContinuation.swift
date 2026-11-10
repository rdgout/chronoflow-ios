public enum AuthenticationMethod: Sendable, Equatable { case signUp, password, passkey, twoFactor }

public enum GuestSessionContinuation: Codable, Sendable, Equatable {
    case trip(String)
    case memberWizard
    case trips
}
