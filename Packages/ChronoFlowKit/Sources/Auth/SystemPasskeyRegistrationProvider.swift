#if canImport(UIKit)
    import AppCore
    import AuthenticationServices
    import Foundation
    import UIKit

    @MainActor
    public final class SystemPasskeyRegistrationProvider: NSObject, PasskeyRegistrationProviding,
        ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding
    {
        private let anchor: @MainActor () -> UIWindow?
        private var controller: ASAuthorizationController?
        private var continuation: CheckedContinuation<ApiPasskeyAttestation, any Error>?
        private var requestID: UUID?
        private var window: UIWindow?

        public init(anchor: @escaping @MainActor () -> UIWindow?) { self.anchor = anchor }

        public func registration(for challenge: ApiPasskeyRegistrationChallenge) async throws -> ApiPasskeyAttestation {
            guard continuation == nil else { throw PasskeyFailure.busy }
            guard #available(iOS 17.4, *) else { throw PasskeyFailure.unavailable }
            try Task.checkCancellation()
            guard let window = anchor(), !window.isHidden else { throw PasskeyFailure.unavailable }
            let options = challenge.options
            let bytes = try Base64URL.decode(options.challenge)
            let userID = try Base64URL.decode(options.user.id)
            let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
                .createCredentialRegistrationRequest(challenge: bytes, name: options.user.name, userID: userID)
            request.userVerificationPreference = .required
            request.attestationPreference = .none
            request.excludedCredentials = try Base64URL.excludedCredentialIDs(options).map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
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
            window ?? anchor() ?? ASPresentationAnchor()
        }
        public func authorizationController(
            controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard self.controller === controller else { return }
            guard
                let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
                let attestationObject = registration.rawAttestationObject
            else {
                finish(.failure(PasskeyFailure.unavailable))
                return
            }
            finish(
                .success(
                    Base64URL.attestation(
                        credentialID: registration.credentialID, clientDataJSON: registration.rawClientDataJSON,
                        attestationObject: attestationObject, transports: ["internal", "hybrid"])))
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
            } else if #available(iOS 18.0, *), failure.domain == ASAuthorizationError.errorDomain,
                failure.code == ASAuthorizationError.matchedExcludedCredential.rawValue
            {
                finish(.failure(PasskeyFailure.alreadyRegistered))
            } else {
                finish(.failure(PasskeyFailure.unavailable))
            }
        }
        private func finish(_ result: Result<ApiPasskeyAttestation, any Error>) {
            let continuation = continuation
            self.continuation = nil
            requestID = nil
            controller = nil
            window = nil
            continuation?.resume(with: result)
        }
    }
#endif
