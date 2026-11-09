#if DEBUG || CHRONOFLOW_MOCK_SCENARIOS
    public enum MockScenarioValues {
        public static var demoID: String { "0199a3c0-0000-7000-8000-000000000000" }
        public static var twoFactorID: String { "0199a3c0-0000-7000-8000-000000000001" }
        public static var demoEmail: String { "demo@example.com" }
        public static var twoFactorEmail: String { "twofactor@example.com" }
        public static var password: String { "password" }
        public static var twoFactorCode: String { "123456" }
        public static var recoveryCode: String { "AbCdEf1234-GhIjKl5678" }
    }
#endif
