# Wizard board-fidelity follow-up

Read the complete independently verified handoff audit (all confirmed and rejected findings) before editing. This round addresses all eight high and eighteen medium findings and the inexpensive low findings across the four groups. Existing customer-flow identifiers are retained; `wizard.title` and `wizard.checking.secondary-close` are additional capture/behavior anchors.

| Group | Changes | Remaining differences and reasons |
| --- | --- | --- |
| Chrome / Where | Generated 4 pt muted/dawn capsule; muted Figtree 15/500 navigation title; native minimal back label; 40 pt guarded interactive glass swap and 0.35 empty opacity; straight-topped invalid To outline; 14/2 pt gaps; empty progress 8%. Card-coloured search sheet with 38 pt corners, background-coloured bordered results, full-width separators, 44 pt code column at 15/700 with scaled tracking, 16/21 names, caption before native search field and dawn Cancel. | Navigation/glass/search chrome uses real system controls, so its OS rendering differs from the HTML's simulated iOS chrome. Below iOS 26 the swap uses the requested plain fallback. No hand-drawn glass. |
| Outbound | Flight time from airport-zone instants before Checking; local connection duration and complete-night preview, with checked layover facts retained when available. Dotted horizontal stop rules; compact neutral chip/removal glyph; neutral empty picker pills; external field errors and a ring only around the date field; board duration units without zero padding; route text/icon colours, 15 pt stop link, empty progress 22%, exact audited Dutch strings. Multi-leg journeys omit the single-flight duration line. | Native compact DatePicker and SF plane retain OS glyph/picker rendering. The Overnight illustration's 23:25 → two days later 02:05 interval contains no full local 23:00–07:00 window; the preview preserves the product's night rule. Capture uses 22:25 arrival to demonstrate the drawn one-night chip truthfully. |
| Return / Sleep | Compact fixed-column From/To card, trailing lock/disclosure, return-specific bordered Past notice, local return flight duration, route/link styling, return stop label. Web choice first; 76 pt choice minima and board insets/hints/disclosures; pinned bottom hint; 16/22 chronotype titles, 10/14 padding, no extra checkmark; audited Dutch sleep copy. | Actual flight data determine times/lengths. Member Sleep keeps member-path progress; the standalone Sleep wrapper depicts the guest path. Native time pickers retain OS rendering. |
| Checking / Questions | Failure Back restored and Close confirms discard; secondary Close above CTA in foreground 16/500; neutral exclusion action. Dawn uppercase eyebrow above server title, 24/30 long titles, 64 pt question card minima, 10 pt option gaps, selection border without a checkmark, pinned bottom hint. Failure card 26 pt radius, 28/20 padding, 52/24 circle/glyph and 22/28 + 15/22 copy. Checking spacing/padding, soft shadow, 26 pt IATA, 40 pt arc, 10 pt dot, dash spacing, muted mini-spinner; exclusion line rhythm. | Server question/exclusion wording remains authoritative (WizardSpec), including wording that differs from illustrative boards. Progress follows the live question count and never retreats when questions appear, so illustrative wrapper percentages are not imposed. SF glyphs and the native spinner remain system-rendered; the dashed border approximates browser dash tessellation. |

The local preview counts complete local 23:00–07:00 windows exactly as the read-only web app's `app/Planner/Itinerary/LayoverClasses.php` does, including DST nights. It does not change review input, validation timing or server authority. Host regression cases cover flight-zone subtraction, invalid order, connection minutes, incomplete nights, DST and return-specific Past copy. The throttle clock test now waits for the next scheduled tick before advancing the injected clock, removing a scheduler race.

## Opt-in visual capture

`WizardBoardCaptureTests` is Debug-only and classified as `capture`, outside every default, matrix, runtime and snapshot set. It authenticates against the isolated mock namespace, walks 34 named board states through the real wizard views, and attaches `XCUIScreen.main.screenshot()` in light/dark and EN/NL (136 attachments). The Debug seed supplies board data and freezes transient Checking states; it adds no screens, controls, snapshot baselines or production behavior. Regular wizard UI journeys still test the live transitions.

```sh
make generate
WIZARD_BOARD_CAPTURE=1 make targeted DEVICES="17e" ONLY="AppUITests/WizardBoardCaptureTests"
```

Attachments use board names with `Dark`, `NL` or `DarkNL` suffixes. The shared board's theme/language properties cover variants without separate wrapper files. Captures include Where/Empty/Same, airport From/Home and stop search, all built Outbound variants, Return/Web/Flight/Past, Sleep, Checking/Again/Slow, Offline/Server/Throttle, all seven question kinds, both exclusions and Discard. CheckPractice, guest/edit context and unbuilt 16c destinations remain outside this round.

## Verification

- `make lint` passes (`build/wizard-fidelity-lint.log`).
- `make quick` runs all package host suites. All 60 wizard tests pass; the sole final failure is the pre-existing APICookieTests loopback-listener `Operation not permitted` in this sandbox (`build/wizard-fidelity-quick-final.log`). No cookie test or budget was weakened.
- TokenGen: 11 tests; AssetGen: 7 tests; resource/signing/contracts/runner: 101 fixtures pass (`build/wizard-fidelity-support.log`). The runner fixture proves capture selection is explicit and absent from all default sets. Generated outputs are regenerated after the final token additions.
- iOS 17 simulator package compilation and direct Swift 6 app/UI type checks pass (`build/wizard-fidelity-ios-final.log`, `build/wizard-fidelity-typecheck-final.log`). The app retains the existing unreachable-default warning in Settings navigation.
- `git diff --check` passes. No simulator, screenshot execution, snapshot recording, matrix or Duo run was performed here; runtime capture and visual acceptance remain pending.

Five ordered atomic group/capture patches and their Conventional Commit subjects are in `build/commits/`. Branch refs are unchanged; temporary commit objects/indexes live under ignored `build/` because the worktree's Git metadata is read-only in this environment.
