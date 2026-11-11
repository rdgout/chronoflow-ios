# No health data (server Phase 19)

The six retired medical answers are absent from Settings and wizard controls, outbound allowlists,
account JSON, review profiles, generated mobile screening cases, debug seeds and normal fixtures.
Legacy account responses and cached trip-response bytes are filtered before persistence; future
unrelated trip fields survive. Readiness keeps its shape without `lightDevicesAllowed`, uses
`adjusted`, and only targets age band or shift work. Both neutral preferences default to false.
Age under 18 and recent shift work still exclude a plan; unanswered age or shift work still block it.

`exclude_caffeine` preserves the old caffeine choice without recording a reason.
`flight_movement_breaks` never inherits an old VTE answer. Settings puts caffeine exclusion in
Caffeine, and movement breaks beside shift work in Safety checks (the server section remains
`health`). Fine-tune uses the same two native toggles; light-device extras have no medical gate.
The audience notice is beside the audience line on Where and in Settings; the eye caution is beside
the light-device choice in both flows. Notices are text, with no answer or acknowledgment stored.

## Sources and generation

Read-only sources: `../chronoflow-new/docs/ui-plan/phase-19-no-health-data.md`, the Phase 19 section
of `docs/ui-plan.md`, relevant screening/core sections of `docs/plan.md`, and `lang/en.json` / `nl.json`.
The server working tree was actively receiving Phase 19 changes during this task. The preference
and notice keys appeared in both language files before copy was imported here.

`make contracts` still reads the pinned TypeScript graph (`afd80dc0`) from the web repository.
`Tools/contracts-gen/generate.py` applies the Phase 19 mobile overlay: the app screening enum has
only shift work, the readiness banner enum uses `adjusted`, and review/plan decoding filters retired
prompts. The planner's server enum intentionally retains its old branches. Account body clock is
handwritten JSON in this app, so its allowlist and decode/encode defaults live in
`AppCore/Contracts/ProfilePreferences.swift` and `AccountTripContracts.swift`.
No generated Swift was edited by hand. `make plan-copy` uses the same pinned copy input plus
`Tools/PlanCopyGen/no-health-data.json` to remove retired prompts and supply the neutral reason.

## Copy provenance

English source sentences are also the backend **lang keys**. Every key below takes its EN and NL
value verbatim from the read-only server `lang/en.json` and `lang/nl.json`. The first seven are in
both Settings and wizard catalogs; remaining keys are in Settings. Existing age/shift blocking
and exclusion copy in PlanCopy stays sourced from the pinned backend catalog.

| Use | Exact lang key |
| --- | --- |
| Settings and wizard | `Leave caffeine out of my plan` |
| Settings and wizard | `Your plan won't suggest any caffeine.` |
| Settings and wizard | `Add movement breaks during long-flight sleep` |
| Settings and wizard | `Your plan breaks up long sleep on long flights with short movement breaks. If you're at higher risk of blood clots, choose this and ask your doctor about compression stockings and an aisle seat.` |
| Settings and wizard | `ChronoFlow is intended for adults with a regular nightly sleep pattern. It does not offer a plan if you have recently done shift work, or do not usually sleep in one regular nightly episode.` |
| Settings and wizard | `ChronoFlow is not suitable if you have bipolar disorder or have had a manic or hypomanic episode: sleep loss, bright light and long journeys can trigger mood episodes. Talk to your doctor before you travel.` |
| Settings and wizard | `Don't use a light box or light glasses if you have an eye disease, have had recent eye surgery or take medicine that makes your eyes sensitive to light. Ask your doctor first.` |
| Settings safety checks | `Safety checks` |
| Settings readiness | `Your plan is adjusted for your preferences and age range` |
| Settings readiness | `Your age range and shift-work answer are saved. You can add optional details below.` |
| Settings readiness | `This plan is not available for travellers under 18.` |
| Settings readiness | `This plan is not available if, in the past 14 days, you have worked night or rotating shifts or had a very irregular sleep schedule.` |
| Settings readiness | `No caffeine anywhere in your plan.` |
| Settings readiness | `Regular movement breaks on long flights, with shorter in-flight sleep stretches.` |
| Settings readiness | `Your plan takes your age range into account in its timing.` |
| Settings safety checks | `In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?` |

The only copy translated here because the key is absent from both server language files is:

| Catalog | English key/value | Dutch value |
| --- | --- | --- |
| PlanCopy (mock/legacy needs-answers reason) | `Answer the questions to get your plan.` | `Beantwoord de vragen om je plan te krijgen.` |

## Upgrade behavior

GRDB migration `v2-no-health-data` cleans cached body-clock values and invalid drafts, rewrites or
deletes pending body-clock outbox rows, removes cached readiness, and strips retired values/prompts
from cached plan responses without dropping unknown plan fields. Recovery drafts containing retired
values are discarded because their server tokens may reference already-submitted answers; unaffected
recovery rows stay. These are local iOS caches, separate from server plans/drafts left unchanged by
P19-D13. Legacy mock snapshots/drafts are decoded and rewritten without the retired data.

## Verification and limits

No tests or simulator sessions were run, as requested. Regression tests cover legacy decoding,
PATCH/review serialization, default preferences, readiness, migration/reopen, cache bytes, prompt
filtering and mock 422s. Changed screen coverage launches seeded; removed question captures are gone.
Completed checks (no test execution):

| Check | Result | Log under `build/` |
| --- | --- | --- |
| `make lint` | Passed | `no-health-lint.log` |
| Contracts generator `--check` | Passed | `no-health-contracts-check.log` |
| PlanCopy generator `--check` | Passed | `no-health-copy-check.log` |
| SwiftPM host `build --build-tests` | Passed; compiled test executables, never ran them | `no-health-host-compile.log` |
| SwiftPM iOS 17 simulator-target package build | Passed; compiled Settings and TripWizardUI | `no-health-ios-package-compile.log` |
| Changed App seed fixtures, `swiftc -typecheck` | Passed | `no-health-seeds-typecheck.log` |
| Complete AppUITests target sources, `swiftc -typecheck` | Passed | `no-health-ui-typecheck.log` |

The full Xcode app build (`build-for-testing`, without running tests) cannot resolve package manifests in this sandbox (`sandbox-exec:
sandbox_apply: Operation not permitted`). SwiftPM can compile the host tests and the iOS package,
including the changed SwiftUI screens; separate seed-file typechecking covers the edited App fixtures.
Device fit, UI behavior and test execution remain for the user. No Duo or seven-device matrix ran.

No requested native Phase 19 behavior is deferred. The existing guest-wizard phase remains deferred;
the server owns its web wizard, science/terms pages and planner mapping. An old server that still
requires retired screening answers cannot complete that review with this client; shipping Phase 19
on the server resolves that dependency. The client never sends replacement medical answers.

Git metadata is outside the writable worktree, so commits use the requested ordered-patch fallback
in `build/commits/nh1-N.patch` and `build/commits/nh1-messages.txt`. Neither server nor RN sources
were modified.
