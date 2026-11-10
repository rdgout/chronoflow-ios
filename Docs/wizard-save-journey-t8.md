# Wizard save journey seed repair (t8)

`WizardSaveJourney` inherited the static board's AMS → NRT itinerary. `MockTripGeneration.airports()` includes HND, but excludes NRT. The live mock's `itinerary(_:)` rejects the unknown airport with an `outbound.legs.0.from_iata` validation error. The reported field is the mock's shared endpoint-lookup error, even though the missing airport is the destination.

`TripWizardErrors.map` converts that field to `legs.0.fromIata`; `MemberWizardModel.applyFailure` routes it to Where through `WizardJourney.errorStep`. Leaving Checking calls `cancelCheck()` and resets `checking` to zero ticks. The UI-test mock uses zero request delay by default, so this validation path can run before the first 0.4-second tick. The captured spinner does not imply a slow review request.

The seed now replaces only the journey's destination with HND and supplies its matching airport metadata, retaining the upcoming dates and Return choice start. Static design captures keep NRT. The seeded account already has completed sleep and screening answers and three credits; its saved profile is retained.

The wiring trace found no substitute generation service or second seeded model: `AppTabs.openWizard()` constructs one `MemberWizardModel` with `NativeSessionController.wizardGenerationService`, which uses the session's real `MockDataSource` and `.storing` effects. `WizardCompletionBoardSeed.apply` already excludes the journey, and the freeze helper does nothing at Return choice. Reseeding happens at launch boundaries, not during the journey. Production review/save logic and the existing UI smoke, including its five-second waits, are unchanged.

No tests or simulators were run by instruction. `make lint` passed (`build/t8-lint.log`), and Swift 6/iOS 17 Debug app module compilation passed (`build/t8-debug-compile.log`). `git diff --check` is clean. Runtime acceptance remains pending.
