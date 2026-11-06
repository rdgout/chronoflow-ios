# Sanitized response fixtures

Derived from read-only chronoflow-new PHP DTOs, request rules, controller responses and API feature assertions on 6 November 2026, including branch feat/mobile-api-passkeys at 841be4bd. No live API capture. Tokens, passwords, signed inputs, email addresses and credential assertions are artificial test values. RN fixture credentials appear only in named test scenarios.

Sources: app/Data/Api/Api{Session,Account,AccountSnapshot,AccountSettings,TripListItem,TripDetail,TripCheckResult,Passkey*}.php; app/Http/Requests/Api/V1; tests/Feature/Api; docs/ui-plan/phase-18-mobile-api-passkeys.md (iOS handoff).

Nested, currently unconsumed account/plan presentation objects remain extensible JSON objects. Sync metadata, identity, settings sections and check-state keys are typed; missing required envelope members fail decoding.

Exact assertion references:
- `AccountSnapshotTest::test_absent_rows_return_the_exact_snapshot_defaults_without_creating_rows` supplies account defaults (including empty PHP arrays inside JSON).
- `LoginTest`, `TwoFactorTest`, `RegistrationTest`, `PasswordRecoveryTest` and `EmailVerificationTest` supply result discriminators, no-content responses, reset revocation and signed verification rules.
- `TripIndexTest`, `TripShowTest` and `TripCheckOffTest` supply list/detail/check envelopes and replay behavior. Trip presentation objects here are intentionally structural subsets: no full planner result is recorded or asserted.
- `ErrorEnvelopeTest` and the passkey handoff supply error codes, fields and arguments. Error fixture messages are artificial except where a sentence key itself is under test; no real response body or secret has been captured.
- `Fixtures/MockScenarios.swift` explicitly names RN's `password`, two-factor code and recovery code as test scenario values. Production mock starts empty, with no built-in credential or assertion provider that accepts sign-in.

Mock verification uses an independent fake-server HMAC key, persisted across restart; these inputs are never valid production links. Mock passkey assertions are accepted only by the injected scenario provider and do not exercise WebAuthn cryptography. Production policy's uncompromised-password service is deliberately not called by mock tests.
