# Sanitized response fixtures

Derived from read-only chronoflow-new PHP DTOs, request rules, controller responses and API feature assertions on 6 November 2026, including branch feat/mobile-api-passkeys at 841be4bd. No live API capture. Tokens, passwords, signed inputs, email addresses and credential assertions are artificial test values. RN fixture credentials appear only in named test scenarios.

Sources: app/Data/Api/Api{Session,Account,AccountSnapshot,AccountSettings,TripListItem,TripDetail,TripCheckResult,Passkey*}.php; app/Http/Requests/Api/V1; tests/Feature/Api; docs/ui-plan/phase-18-mobile-api-passkeys.md (iOS handoff).

Nested, currently unconsumed account/plan presentation objects remain extensible JSON objects. Sync metadata, identity, settings sections and check-state keys are typed; missing required envelope members fail decoding.
