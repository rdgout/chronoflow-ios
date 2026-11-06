import AppCore
import Foundation

nonisolated public enum AuthCopy {
    public static func string(_ key: String, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier == "nl" ? "nl" : "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path)
        else {
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    public static func field(_ message: FieldMessage, locale: Locale) -> String? {
        switch message.key {
        case "Please fill this in.", "Enter a valid email address, like name@example.com.",
            "The passwords don't match yet.", "Use both uppercase and lowercase letters.",
            "Use at least one letter.", "Use at least one number.", "Use at least one symbol.",
            "This password has appeared in a data leak. Choose a different password.",
            "This email verification link is invalid or has expired.",
            "Enter the 6-digit code from your authenticator app.",
            "Enter one of the recovery codes you saved when you set up two-factor authentication.",
            "The authentication code was not accepted. Try again.",
            "This recovery code was not accepted. Try another saved code.":
            return string(message.key, locale: locale)
        case "Use no more than :max characters.", "Use at least :min characters.",
            "Use no more than {{max}} characters.", "Use at least {{min}} characters.":
            let name = message.key.contains("max") ? "max" : "min"
            guard case .number(let value) = message.arguments[name], value >= 0, value <= Decimal(Int64.max),
                value == Decimal(NSDecimalNumber(decimal: value).int64Value)
            else { return nil }
            let key = name == "max" ? "Use no more than %lld characters." : "Use at least %lld characters."
            return String(
                format: string(key, locale: locale), locale: locale, NSDecimalNumber(decimal: value).int64Value)
        default: return nil
        }
    }

    public static func supports(_ message: FieldMessage) -> Bool {
        field(message, locale: Locale(identifier: "en")) != nil
    }
}
