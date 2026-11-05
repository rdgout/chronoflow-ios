import CoreText
import Foundation

nonisolated public enum FontFace: String, CaseIterable, Sendable {
    case figtree400 = "CFFigtree-400"
    case figtree500 = "CFFigtree-500"
    case figtree600 = "CFFigtree-600"
    case figtree700 = "CFFigtree-700"
    case fraunces400Opsz20 = "CFFraunces-400-Opsz20"
    case fraunces400Opsz32 = "CFFraunces-400-Opsz32"
    case fraunces400Opsz48 = "CFFraunces-400-Opsz48"
    case fraunces500Opsz20 = "CFFraunces-500-Opsz20"
    case fraunces500Opsz32 = "CFFraunces-500-Opsz32"
    case fraunces500Opsz48 = "CFFraunces-500-Opsz48"
}

nonisolated public enum FontRegistry {
    public enum RegistrationError: Error, Sendable {
        case missingResource(String)
        case coreText([String])
    }

    public static func register() async throws {
        try await Task.detached(priority: .userInitiated) {
            let urls = try FontFace.allCases.map { face in
                guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: "ttf") else {
                    throw RegistrationError.missingResource(face.rawValue)
                }
                return url
            }
            var errors: Unmanaged<CFArray>?
            let registered = CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, &errors)
            let failures = (errors?.takeRetainedValue() as? [CFError] ?? []).filter {
                CFErrorGetCode($0) != CTFontManagerError.alreadyRegistered.rawValue
            }.map { String(describing: $0) }
            if !failures.isEmpty { throw RegistrationError.coreText(failures) }
            if !registered && errors == nil { throw RegistrationError.coreText(["CoreText registration failed"]) }

        }.value
    }
}
