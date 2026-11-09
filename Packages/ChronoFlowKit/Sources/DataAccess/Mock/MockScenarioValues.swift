#if DEBUG || CHRONOFLOW_MOCK_SCENARIOS
    enum MockScenarioValues {
        static var demoID: String { "0199a3c0-0000-7000-8000-000000000000" }
        static var twoFactorID: String { "0199a3c0-0000-7000-8000-000000000001" }
        static var demoEmail: String { "demo@example.com" }
        static var twoFactorEmail: String { "twofactor@example.com" }
        static var password: String { "password" }
        static var twoFactorCode: String { "123456" }
        static var recoveryCode: String { "AbCdEf1234-GhIjKl5678" }
    }
#endif
