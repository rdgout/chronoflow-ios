# Phase 16c review round 3

All 19 supplied findings are addressed. Boards and WizardCopy take precedence over RN. No design files or external worktrees were changed.

| Finding | Result |
| --- | --- |
| 1 | Fixed: TripWizardUI owns both sheet validation keys, including the board's Dutch drinks wording ending in “te bewaren”. |
| 2 | Fixed: the credit balance has a singular variant, uses credit/credits in Dutch and has no trailing period. |
| 3 | Fixed: scoped room rows use Dark room / Donkere kamer before the city. |
| 4 | Fixed: answered extras use foreground; Add uses dawn text. |
| 5 | Fixed: room availability uses a contextual From / Vanaf entry; route From remains Van. |
| 6 | Fixed: Ready/save notices include the board's leading info circle at the generated notice size. |
| 7 | Fixed: latest wake uses the native inline wheel, with its 180-point height generated from WizardSheet. WizardSheet's free-day variant explicitly uses time pills, so those retain their board layout. |
| 8 | Fixed: the adjusted wake row includes the localized assumed suffix. |
| 9 | Fixed: Today uses the shared full-width primary and ghost buttons, with Plan a trip first and 48-point minimum heights. |
| 10 | Fixed: busy intervals share one compact bordered list, with circular × removal and a dawn + Add busy hours link. Add/edit reuses the existing PickerDateTime sheet for the From and To endpoints; cancel does not mutate the interval. |
| 11 | Fixed: Ready price amounts and the destructive no-credit balance use semibold emphasis. |
| 12 | Fixed by the shared retry lifecycle described below. |
| 13 | Fixed by the shared retry lifecycle described below. |
| 14 | Fixed: Updated requires a previous review of the same input, and revisiting a Ready row clears it. |
| 15 | Fixed: successful server creation navigates to the saved trip even if local reminders/recovery cleanup fails. A retained recovery row still carries the saved ID. |
| 16 | Fixed: the created-trip change fires the success notification haptic before navigation. |
| 17 | Fixed by the shared retry lifecycle described below. |
| 18 | Fixed by the shared retry lifecycle described below. |
| 19 | Fixed: generation returns the known saved ID for non-cancellation local write errors, so the model persists it and a fresh service bypasses another creation. Local failures cannot expire an already-created trip. |

The model now owns one deadline-derived retry task for Checking and Ready. Both ordinary Checking and inline review failures start it. It stops at the exact deadline, including fractional Retry-After values, clears expired deadlines, and re-derives the displayed seconds whenever navigation or failure state changes. Leaving Ready clears the control lock; returning without edits uses only the unexpired part of the original deadline. Successful review removes the failure and countdown together. Saves remain manual.

The info circle, plus and × are SF Symbols clearly drawn on the boards. All dimensions and colors use generated tokens; the new wheel height comes from TokenGen's board-source metrics. New/contextual copy, including the range removal accessibility label, has English and Dutch entries in TripWizardUI's catalog.

## Verification limits

No tests, simulators, app launches, UI tests or snapshots were executed. Package regressions were authored for inline and ordinary review throttles, autonomous save countdowns, navigation and failure resets, manual retry, Updated semantics, failed local saved-ID writes, recovery after service recreation, and cleanup failure after successful creation. Copy assertions cover the changed English/Dutch strings and balance counts 0/1/3.

Compile-only validation uses Swift 6 and an iOS 17 simulator target, cached dependency products, and temporary Bundle accessors. It does not validate runtime layout, resources or haptics. Debug/Release compilation of TripWizard, DesignSystem, PlanUI and TripWizardUI and type checking of TripWizardTests pass. Strict `make lint`, TokenGen output verification and `git diff --check` pass. Logs and temporary compiler products are under `build/`; no runtime acceptance is claimed.

## Delivery

Git cannot create `/Users/rickgout/Sites/chronoflow-ios/.git/worktrees/chronoflow-ios-16c/index.lock` under this session's filesystem permissions. No commits, merges or pushes were created. The ordered patches are `build/commits/r3-1.patch` through `r3-5.patch`; subjects are in `build/commits/r3-messages.txt`, separated by `---`. They apply in order to `f17970b5`. The working tree already contains their final state; do not apply them over the current changes. Applying the patches to isolated copies of their original files reproduces the final working files exactly.
