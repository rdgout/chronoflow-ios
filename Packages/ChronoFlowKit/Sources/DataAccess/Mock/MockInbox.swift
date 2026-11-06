import AppCore
import Foundation

public enum MockMail: Codable, Sendable, Equatable {
    case passwordReset(id: String, to: String, sentAt: TimeInterval, input: ResetPasswordInput)
    case verification(id: String, to: String, sentAt: TimeInterval, input: SignedVerificationInput)
}
