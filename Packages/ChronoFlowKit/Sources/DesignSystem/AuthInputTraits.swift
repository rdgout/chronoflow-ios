#if canImport(UIKit)
    nonisolated public enum AuthPasswordPolicy {
        public static var hint: String {
            "Use at least 12 characters, with uppercase and lowercase letters, numbers and symbols. Choose a password that has not appeared in a data leak."
        }
    }
#endif
