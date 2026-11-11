# Wizard save journey seed repair (t8)

`WizardSaveJourney` inherited the static board's AMS → NRT itinerary. `MockTripGeneration.airports()` includes HND, but excludes NRT. The original explanation that validation immediately left Checking before the first tick was not established. The user's t9 regression run failed waiting for any field error, so the earlier verdict of no production stall is withdrawn.

At t9, review built and rebased a plan before calling `itinerary(_:)`. An unknown departure could instead throw `reviewExpired` from `template(_:)`; an unknown destination reached validation only after rebasing. A finite yield loop was not a completion barrier. The t10 repair validates first and reports the correct endpoint. See [wizard-checking-t10.md](wizard-checking-t10.md) for the complete failure/cancellation trace and its limits; the original UI stall is not claimed to be reproduced.

The seed now replaces only the journey's destination with HND and supplies its matching airport metadata, retaining the upcoming dates and Return choice start. Static design captures keep NRT. The seeded account already has completed sleep and screening answers and three credits; its saved profile is retained.

The wiring trace found no substitute generation service or second seeded model: `AppTabs.openWizard()` constructs one `MemberWizardModel` with `NativeSessionController.wizardGenerationService`, which uses the session's real `MockDataSource` and `.storing` effects. `WizardCompletionBoardSeed.apply` already excludes the journey, and the freeze helper does nothing at Return choice. Reseeding happens at launch boundaries, not during the journey. Production review/save logic and the existing UI smoke, including its five-second waits, are unchanged.

No tests or simulators were run by instruction. `make lint` passed (`build/t8-lint.log`), and Swift 6/iOS 17 Debug app module compilation passed (`build/t8-debug-compile.log`). `git diff --check` is clean. Runtime acceptance remains pending.
