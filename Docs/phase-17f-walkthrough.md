# Walkthrough acceptance

Phase 17f replaces the D17 walkthrough seam with the three Walkthrough boards.
Skip and Done save the local flag and one existing walkthrough outbox row in a
single transaction. Account readiness observes that commit and opens Today;
completion never calls the network. SyncLifecycle already observes new outbox
IDs and schedules retries. Pending completion wins over stale session and identity
responses, including after reopening the database.

Walkthrough POST failures retain the row. A 401 from this optional POST ends that
sync flight as failed, before a full pull, and retries through the existing
backoff. Other authenticated requests keep their existing unauthorized-session
handling. Email verification and terms retain their gate precedence.

## Board interpretation

The 1 Nov canvas note settles Today after first run and Preferences after replay.
The boards implement Next/Done and Skip with decorative 24/8 pt pill indicators;
they do not specify swipe navigation. Native uses those controls instead of RN's
swipe pager. Both primary labels are 40 pt high as drawn by Button lg and the
explicit Done link; their hit targets are at least 44 pt. The timeline preview
keeps the supplied TimelineBlock component's compact icon-only breakpoint, with
its full localised copy on wide layouts. All art comes from existing category,
pattern and progress components. No image asset is missing.

Safe-area layout follows the RN rule: top inset + 8, horizontal insets + 16,
bottom max(inset, 32). The header and footer stay outside the vertically scrolling
content. Both appearances use generated tokens. Every copy entry has its exact
RN Dutch value; example times/flight number are language-neutral. The root's
xxLarge cap is unchanged. Reduce Motion disables indicator animation.

## Deferred

`WalkthroughModel.Mode.replay` invokes the caller's return action without writing
completion again. Preferences and its replay entry are deferred. Terms screens
and actual reminder activation/delivery remain outside this phase. The reminder
explanation remains the supplied board copy. MockDataSource already uses the
seed's default `walkthroughSeen: false`; this branch has no temporary override.

## Verification

Run the UI journeys later on one simulator:

```sh
make targeted DEVICES="17e" ONLY="AppUITests/WalkthroughTests"
```

The two journeys use UUID-scoped fresh accounts with mutation sends held offline:
demo Skip, and the second seeded account's Next/Next/Done in Dutch at xxLarge.
Both relaunch fully offline and require Today, proving an unsent completion does
not replay. Existing auth journeys now assert the real walkthrough title.

No simulator, profile snapshots or seven-device matrix was run for this task.
Host coverage uses the D1c Mac device table, including SE/17e/Duo/Pro Max, and
completion, retry, stale-session, relaunch, replay and bilingual-copy tests.

Validation in this workspace: strict `make lint`; 503 Swift Testing cases and 12
XCTest cases pass with only the existing sandbox-blocked loopback cookie test
excluded. `make quick` was run and fails at that test with EPERM. All 17 token/asset
tests and 100 resource/runner fixtures pass. An intermediate host run under
concurrent compiler load exceeded the existing S3 timeline performance budget;
the final isolated full host run passes. Direct iOS 17 SDK compilation covers the
app, PlanUI and hosted/UI test sources without simulator execution.

Delivery: `build/commits/1.patch` and `build/commits/messages.txt`, one atomic
Conventional Commit, based on `f173d1e` (`feat/phase-15-timeline`).
