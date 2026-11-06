#if canImport(UIKit)
    import AppCore
    import AuthenticationServices
    import Foundation
    import UIKit

    @MainActor
    public final class SystemPasskeyAssertionProvider: NSObject, PasskeyAssertionProviding,
        ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding
    {
        private let anchor: @MainActor () -> UIWindow?
        private var controller: ASAuthorizationController?
        private var continuation: CheckedContinuation<ApiPasskeyAssertion, any Error>?
        private var requestID: UUID?
        private var window: UIWindow?

        public init(anchor: @escaping @MainActor () -> UIWindow?) { self.anchor = anchor }

        public func assertion(for challenge: ApiPasskeyChallenge) async throws -> ApiPasskeyAssertion {
            guard continuation == nil else { throw PasskeyFailure.busy }
            try Task.checkCancellation()
            guard let window = anchor(), !window.isHidden else { throw PasskeyFailure.unavailable }
            let bytes = try Base64URL.decode(challenge.options.challenge)
            let request = ASAuthorizationPlatformPublicKeyCredentialProvider(
                relyingPartyIdentifier: challenge.options.rpId
            )
            .createCredentialAssertionRequest(challenge: bytes)
            request.userVerificationPreference = .required
            let id = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuation = continuation
                    self.requestID = id
                    self.window = window
                    let controller = ASAuthorizationController(authorizationRequests: [request])
                    self.controller = controller
                    controller.delegate = self
                    controller.presentationContextProvider = self
                    controller.performRequests()
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard self?.requestID == id else { return }
                    self?.controller?.cancel()
                    self?.finish(.failure(CancellationError()))
                }
            }
        }
        public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            precondition(self.controller === controller && window != nil)
            return window!
        }
        public func authorizationController(
            controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard self.controller === controller else { return }
            guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion
            else {
                finish(.failure(PasskeyFailure.unavailable))
                return
            }
            finish(
                .success(
                    Base64URL.assertion(
                        credentialID: assertion.credentialID, clientDataJSON: assertion.rawClientDataJSON,
                        authenticatorData: assertion.rawAuthenticatorData, signature: assertion.signature,
                        userHandle: assertion.userID)))
        }
        public func authorizationController(
            controller: ASAuthorizationController, didCompleteWithError error: any Error
        ) {
            guard self.controller === controller else { return }
            let failure = error as NSError
            if failure.domain == ASAuthorizationError.errorDomain
                && failure.code == ASAuthorizationError.canceled.rawValue
            {
                finish(.failure(PasskeyFailure.canceled))
            } else {
                finish(.failure(PasskeyFailure.unavailable))
            }
        }
        private func finish(_ result: Result<ApiPasskeyAssertion, any Error>) {
            let continuation = continuation
            self.continuation = nil
            requestID = nil
            controller = nil
            window = nil
            continuation?.resume(with: result)
        }
    }
#endif
